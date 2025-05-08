@namespace AXLAP;

    # Load standard Zeek scripts
    @load base/protocols/conn
    @load base/protocols/dns
    @load base/protocols/http
    @load base/protocols/ftp
    @load base/protocols/smtp
    @load base/protocols/ssh
    @load base/protocols/ssl
    @load base/protocols/files
    @load base/protocols/notice
    @load policy/frameworks/intel/seen
    @load policy/frameworks/intel/do_notice
    @load policy/frameworks/files/extract_common_mime_types
    # @load policy/frameworks/signatures # If using Zeek signatures

    # Enable JSON logging for all logs
    redef Log::default_log_writer = Log::WRITER_JSON;
    # redef LogAscii::json_timestamps = JSON::TS_ISO8601; # For newer Zeek versions for ISO8601 in JSON

    # Set log rotation interval if not using external log rotation
    # redef Log::default_rotation_interval = 1hr;
    # redef Log::default_rotation_size = 100MB;

    # Store logs in a specific directory (mounted as /var/log/zeek_json)
    # This path is relative to Zeek's spool directory, but we'll symlink or configure output dir
    # Zeek's default logging behavior with JSON writer in Zeek 4+ typically logs to current dir.
    # In the Docker container, we'll ensure Zeek is run from a directory that maps to /var/log/zeek_json,
    # or configure Log::logdir.
    redef Log::logdir = "/var/log/zeek_json";

    # PCAP Handling for Arkime
    # Zeek can write PCAPs per connection or per time interval.
    # For Arkime, we want PCAPs that Arkime can find and index.
    # Option 1: Zeek writes hourly PCAPs, Arkime capture watches this directory.
    # Option 2: Configure Zeek to only log, and Arkime does its own capture (less ideal for integration).
    # Option 3: Use a script to move/organize Zeek's per-connection PCAPs if that feature is used.

    # For simplicity, we'll assume a main pcap-writing process (like daemonlogger or Arkime capture itself if live)
    # or if Zeek is to write PCAPs:
    # @load packages/zeek/spicy-analyzers/dpd/plugin/Zeek_DPD # Example for DPD, not pcap writing
    # For writing pcaps with Zeek:
    # redef Pcap::snaplen = 1500; # Set snapshot length
    # redef Pcap::dir = "/data/pcap"; # Directory where Zeek writes pcap files
    # redef Pcap::write_current = Pcap::WRITE_PER_INTERVAL;
    # redef Pcap::interval = 3600; # Write one pcap file per hour
    # redef Pcap::prefix = "zeekcapture";
    # Note: This needs zeek to be compiled with --enable-pcap-writing if not default

    # Load custom AXLAP plugins
    @load /opt/axlap/zeek_plugins/AXLAP_HTTP_Detailed.zeek
    @load /opt/axlap/zeek_plugins/AXLAP_DNS_Anomalies.zeek
    @load /opt/axlap/zeek_plugins/AXLAP_Connection_Stats.zeek

    # Example: Configure a setting for a custom plugin
    # redef AXLAP::HTTP::max_uri_length_notice = 2048;

    # Intel framework configuration
    redef Intel::read_files += {"/opt/axlap/threat_intel/ips.dat", "/opt/axlap/threat_intel/domains.dat"};
    # (These files would need to be populated by the update scripts)

    # Reduce some noisy notices if needed, e.g.:
    # redef नोनोटीस += { SSH::Password_Guessing };

    # Ensure Zeek logs are in JSON format (this is crucial for Filebeat)
    # This is often handled by command line arguments or zeekctl config as well.
    # For JSON output to files, ensure Zeek version supports it well or use `zeek-json-logger` plugin if older.
    # Zeek 4.0+ has native JSON logging:
    # In scripts/init.sh for Zeek container:
    # zeekctl config "Log::default_log_writer=Log::WRITER_JSON"
    # zeekctl config "LogAscii::json_timestamps=JSON::TS_ISO8601"
    # zeekctl config "Log::logdir=/var/log/zeek_json"

    event zeek_init() &priority=5
    {
        print "AXLAP Zeek configuration loaded.";
        # Example: Log all HTTP headers
        # Log::add_filter(HTTP::LOG, [$name="default-http", $pred(rec: HTTP::Info) = { return T; }]);
    }
