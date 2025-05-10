# axlap/config/zeek/local.zeek
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

# Enable JSON logging for all logs
redef Log::default_log_writer = Log::WRITER_JSON;

# Store logs in a specific directory (mounted as /var/log/zeek_json)
redef Log::logdir = "/var/log/zeek_json";

# Load custom AXLAP plugins
@load /opt/axlap/zeek_plugins/AXLAP_HTTP_Detailed.zeek
@load /opt/axlap/zeek_plugins/AXLAP_DNS_Anomalies.zeek
@load /opt/axlap/zeek_plugins/AXLAP_Connection_Stats.zeek

# Intel framework configuration
redef Intel::read_files += {"/opt/axlap/threat_intel/ips.dat", "/opt/axlap/threat_intel/domains.dat"};

event zeek_init() &priority=5
{
    print "AXLAP Zeek configuration loaded. Interface: ", get_interface_name();
}

function get_interface_name(): string {
    return run_func::get_interface_name();
}
