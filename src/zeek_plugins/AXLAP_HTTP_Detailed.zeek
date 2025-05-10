# @namespace AXLAP_HTTP
    #
    # Logs additional HTTP details, including all headers and potentially bodies.
    # Configurable for performance.

    @load base/frameworks/logging
    @load base/protocols/http

    module AXLAP_HTTP;

    export {
        # Redefinable options
        option log_all_request_headers: bool = T &redef;
        option log_all_response_headers: bool = T &redef;
        option max_header_value_len: int = 1024 &redef; # Truncate long header values
        # option log_http_bodies: bool = F &redef; # Logging bodies can be very verbose

        # Custom log stream for detailed HTTP info
        redef enum Log::ID += { LOG_HTTP_DETAILED };

        type Info: record {
            ts: time        &log;
            uid: string      &log;
            id: conn_id    &log;
            trans_depth: count &log; # HTTP transaction depth

            method: string   &log &optional;
            host: string     &log &optional;
            uri: string      &log &optional;
            referrer: string &log &optional;
            user_agent: string &log &optional;
            request_body_len: count &log &optional;
            response_body_len: count &log &optional;
            status_code: count &log &optional;
            status_msg: string &log &optional;
            tags: set[string] &log &optional; # Tags from HTTP analysis

            # All headers (can be very verbose)
            request_headers: vector of string &log &optional;
            response_headers: vector of string &log &optional;

            # Potential future additions
            request_body_md5: string &log &optional;
            response_body_md5: string &log &optional;
        } &log;
    }

    event zeek_init() &priority=5
    {
        Log::create_stream(AXLAP_HTTP::LOG_HTTP_DETAILED, [$columns=Info, $path="axlap_http_detailed"]);
    }

    function format_header(name: string, value: string): string
    {
        local val = value;
        if ( |val| > max_header_value_len )
            val = val[0:max_header_value_len] + "...";
        return fmt("%s: %s", name, val);
    }

    event http_transaction(c: connection, is_orig: bool, h: http_header_info, b: string) &priority=-5
    {
        # This event is for older Zeek versions. Newer Zeek uses http_begin_entity, http_end_entity, http_header.
        # This simplified example focuses on http_message_done.
    }

    event http_message_done(c: connection, is_orig: bool, stat: http_message_stat)
    {
        if ( ! c?$http ) return; # Connection or http state might not exist

        local info: Info;
        info$ts = network_time();
        info$uid = c$uid;
        info$id = c$id;
        info$trans_depth = c$http$trans_depth;

        info$method = c$http$method;
        info$host = c$http$host;
        info$uri = c$http$uri;
        info$user_agent = c$http$user_agent;
        info$request_body_len = c$http$request_body_len;
        info$response_body_len = c$http$response_body_len;
        info$status_code = c$http$status_code;
        info$status_msg = c$http$status_msg;
        info$tags = c$http$tags;

        if ( AXLAP_HTTP::log_all_request_headers && c$http?$request_headers ) {
            info$request_headers = vector();
            for (name, value in c$http$request_headers)
                info$request_headers[|info$request_headers|] = format_header(name, value);
        }

        if ( AXLAP_HTTP::log_all_response_headers && c$http?$response_headers ) {
            info$response_headers = vector();
            for (name, value in c$http$response_headers)
                info$response_headers[|info$response_headers|] = format_header(name, value);
        }

        # Calculate and log MD5 hashes of request and response bodies (if available)
        if ( c$http?$orig && c$http$orig?$body ) {
            info$request_body_md5 = md5(c$http$orig$body);
        }
        if ( c$http?$resp && c$http$resp?$body ) {
            info$response_body_md5 = md5(c$http$resp$body);
        }
        
        Log::write(AXLAP_HTTP::LOG_HTTP_DETAILED, info);
    }

    # To get Referrer, need to parse headers manually if not directly in c$http
    event http_header(c: connection, is_orig: bool, name: string, value: string)
    {
        if ( ! c?$http ) return;
        if ( is_orig && to_lower(name) == "referer" ) # Note: "referer" is the common spelling in HTTP
            c$http$referrer = value; # Zeek's http_conn record doesn't have referrer by default, add it if needed
                                     # Or handle in http_message_done if available in c$http$request_headers
    }

    # Add referrer to c$http if it's not there
    hook Notice::policy(n: Notice::Info)
    {
        if ( n$conn?$http && n$conn$http?$request_headers ) {
            for (name, value in n$conn$http$request_headers) {
                if ( to_lower(name) == "referer" ) {
                    # This is just an example, how you store/use it depends on needs
                    # add n$conn$http$tags["Referer:" + value];
                    break;
                }
            }
        }
    }