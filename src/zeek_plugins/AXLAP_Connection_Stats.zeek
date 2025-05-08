# @namespace AXLAP_CONN_STATS
    #
    # Calculates and logs enhanced connection statistics.
    # E.g., bits per second, packets per second, flow directionality.

    @load base/frameworks/logging
    @load base/protocols/conn

    module AXLAP_CONN_STATS;

    export {
        redef enum Log::ID += { LOG_CONN_STATS };

        type Info: record {
            ts: time        &log;
            uid: string      &log;
            id: conn_id    &log;
            proto: transport_proto &log;
            duration: interval  &log &optional;

            orig_bytes: count   &log &optional;
            resp_bytes: count   &log &optional;
            orig_pkts: count    &log &optional;
            resp_pkts: count    &log &optional;

            orig_bytes_per_sec: double &log &optional;
            resp_bytes_per_sec: double &log &optional;
            orig_pkts_per_sec: double  &log &optional;
            resp_pkts_per_sec: double  &log &optional;

            # Ratio of originator bytes to total bytes. 0.5 is balanced. >0.5 means orig sent more.
            flow_directionality: double &log &optional;
            # Connection state
            conn_state: string &log &optional;
            history: string &log &optional;
        } &log;
    }

    event zeek_init() &priority=5
    {
        Log::create_stream(AXLAP_CONN_STATS::LOG_CONN_STATS, [$columns=Info, $path="axlap_conn_stats"]);
    }

    event connection_state_remove(c: connection)
    {
        if ( ! c?$conn_stats_info ) # Check if we've already processed this uid for stats
            return;

        local info: Info;
        info$ts = network_time(); # Log time is when event is processed
        info$uid = c$uid;
        info$id = c$id;
        info$proto = c$id$resp_p; # Transport protocol
        info$duration = c$duration;

        info$orig_bytes = c$orig?$size : 0;
        info$resp_bytes = c$resp?$size : 0;
        info$orig_pkts = c$orig?$num_pkts : 0;
        info$resp_pkts = c$resp?$num_pkts : 0;

        local dur_sec = c$duration > 0.0 ? c$duration : 1.0; # Avoid division by zero, min 1s effective duration

        info$orig_bytes_per_sec = c$orig?$size / dur_sec : 0.0;
        info$resp_bytes_per_sec = c$resp?$size / dur_sec : 0.0;
        info$orig_pkts_per_sec = c$orig?$num_pkts / dur_sec : 0.0;
        resp_pkts_per_sec = c$resp?$num_pkts / dur_sec : 0.0; # Corrected variable name

        local total_bytes = (c$orig?$size : 0) + (c$resp?$size : 0);
        if ( total_bytes > 0 )
            info$flow_directionality = (c$orig?$size : 0) / total_bytes;
        else
            info$flow_directionality = 0.5; # Undefined or balanced if no bytes

        info$conn_state = c$conn_state;
        info$history = c$history;

        Log::write(AXLAP_CONN_STATS::LOG_CONN_STATS, info);
        delete c$conn_stats_info; # Mark as processed
    }

    # Use connection_established to potentially initialize per-connection data
    event connection_established(c: connection)
    {
        # Add a tag to conn record to ensure we process it once in connection_state_remove
        add c$conn_stats_info;
    }