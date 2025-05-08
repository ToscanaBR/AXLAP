 # @namespace AXLAP_DNS
    #
    # Detects various DNS anomalies like high NXDOMAIN count, DGA-like names, etc.

    @load base/frameworks/logging
    @load base/frameworks/notice
    @load base/protocols/dns

    module AXLAP_DNS;

    export {
        # Redefinable thresholds
        option nxdomain_threshold_per_host: count = 10 &redef; # NXDOMAINs in window
        option nxdomain_window: interval = 5min &redef;
        option dga_entropy_threshold: double = 3.5 &redef; # Shannon entropy threshold for DGA detection
        option dga_min_len: count = 8 &redef; # Min length for DGA check
        option suspicious_tlds: set[string] = {".tk", ".top", ".xyz", ".pw", ".cc", ".online"} &redef;

        # Custom Notices
        redef enum Notice::Type += {
            High_NXDOMAIN_Rate,
            Potential_DGA_Query,
            Suspicious_TLD_Query
        };
    }

    # Track NXDOMAINs per source IP
    global nxdomains_count: table[addr] of count &read_expire=nxdomain_window;

    # Basic Shannon entropy calculation
    function shannon_entropy(s: string): double
    {
        if ( |s| == 0 ) return 0.0;
        local counts: table[string] of count;
        for ( i in s )
            ++counts[s[i]];

        local entropy = 0.0;
        for ( c in counts )
        {
            local p = counts[c] / |s|;
            entropy -= p * log2(p);
        }
        return entropy;
    }

    event dns_rejected(c: connection, msg: dns_msg, query: string, qtype: count, qclass: count, id: count, raised: bool)
    {
        # dns_rejected might indicate server-side issues, not always client NXDOMAIN
    }

    event dns_A_reply(c: connection, msg: dns_msg, ans: dns_answer, num_replies: count) { } # Placeholder if needed
    event dns_AAAA_reply(c: connection, msg: dns_msg, ans: dns_answer, num_replies: count) { }

    event dns_query_reply(c: connection, msg: dns_msg, query: string, qtype: count, qclass: count, answers: dns_answer_vector)
    {
        # Placeholder - actual NXDOMAIN logic better in dns_message or specific reply types
    }

    event dns_message(c: connection, is_orig: bool, msg: dns_msg)
    {
        if ( is_orig ) return; # Only look at responses

        if ( msg?$rcode && msg$rcode == DNS::RCODE_NXDOMAIN ) {
            local client_ip = c$id$orig_h;
            ++nxdomains_count[client_ip];
            if ( nxdomains_count[client_ip] >= nxdomain_threshold_per_host ) {
                NOTICE([$note=High_NXDOMAIN_Rate,
                        $msg=fmt("Client %s exceeded NXDOMAIN threshold (%d/%s)",
                                 client_ip, nxdomains_count[client_ip], nxdomain_window),
                        $src=client_ip,
                        $sub=query, # Query not directly available here, need to grab from conn
                        $conn=c]);
                # Reset or adjust count to avoid continuous notices for same burst
                # Or use Notice framework's suppression features
                nxdomains_count[client_ip] = 0; # Simple reset
            }
        }

        if ( msg?$query && msg?$qtype && msg$qtype == DNS::TYPE_A || msg$qtype == DNS::TYPE_AAAA) {
            local query_name = msg$query;

            # DGA-like check (very basic entropy)
            # More sophisticated DGA detection would use ML or character frequency analysis
            local domain_parts = split_string(query_name, /\./);
            if ( |domain_parts| > 0 ) {
                local check_part = domain_parts[0]; # Check first subdomain part
                if ( |check_part| >= dga_min_len ) {
                    local entropy = shannon_entropy(check_part);
                    if ( entropy > dga_entropy_threshold ) {
                        NOTICE([$note=Potential_DGA_Query,
                                $msg=fmt("Potential DGA query: %s (entropy %.2f)", query_name, entropy),
                                $src=c$id$orig_h,
                                $dst=c$id$resp_h,
                                $sub=query_name,
                                $conn=c]);
                    }
                }
            }

            # Suspicious TLD check
            for ( i in domain_parts ) { # Check all parts for TLD match for generality
                local tld_candidate = "." + to_lower(domain_parts[i]);
                if ( tld_candidate in suspicious_tlds ) {
                     # More accurately, check the actual TLD part:
                     # local actual_tld = "." + to_lower(domain_parts[|domain_parts|-1]);
                     # if (actual_tld in suspicious_tlds && |domain_parts| > 1) {
                     # Simplified: if any part matches common shorteners/free TLDs if they appear as subdomains too.
                     # A proper TLD extraction is needed for accuracy.
                     # Using the last part as TLD:
                     if ( |domain_parts| >= 2 ) { # Ensure there's a domain and TLD
                        local actual_tld = "." + to_lower(domain_parts[|domain_parts|-1]);
                        if ( actual_tld in suspicious_tlds ) {
                             NOTICE([$note=Suspicious_TLD_Query,
                                     $msg=fmt("Query to suspicious TLD %s: %s", actual_tld, query_name),
                                     $src=c$id$orig_h,
                                     $dst=c$id$resp_h,
                                     $sub=query_name,
                                     $conn=c]);
                             break; # Only one notice per query for TLD
                        }
                     }
                }
            }
        }
    }