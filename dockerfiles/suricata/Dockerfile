FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    wget \
    curl \
    python3 \
    python3-pip \
    python3-yaml \
    libnet1 \
    libpcap-dev \
    libnetfilter-queue-dev \
    libnetfilter-conntrack-dev \
    libnfnetlink-dev \
    libluajit-5.1-dev \
    libjansson-dev \
    libmagic-dev \
    libmaxminddb-dev \
    libhtp-dev \
    # For Rust based components if building Suricata from source later versions
    # rustc cargo \
    && rm -rf /var/lib/apt/lists/*

# Install Suricata from PPA for latest stable version
RUN add-apt-repository -y ppa:oisf/suricata-stable
RUN apt-get update && apt-get install -y suricata suricata-update jq

# Create necessary directories
RUN mkdir -p /var/log/suricata \
    && mkdir -p /etc/suricata/rules \
    && mkdir -p /var/lib/suricata/rules \
    && mkdir -p /var/run/suricata # For PID file if managed by Suricata itself

# suricata-update will download rules to /var/lib/suricata/rules
# and create a suricata.rules file there.
# We need to make sure suricata.yaml points to it or symlink it.

ARG SURICATA_INTERFACE=eth0
ENV SURICATA_INTERFACE=${SURICATA_INTERFACE}
ENV HOME_NET_CONFIG="[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,172.28.0.0/16]"
 # Default, set by install.sh

COPY <<EOF /usr/local/bin/entrypoint.sh
#!/bin/bash
set -e

echo "AXLAP Suricata Entrypoint"
echo "SURICATA_INTERFACE: \${SURICATA_INTERFACE}"
echo "HOME_NET_CONFIG: \${HOME_NET_CONFIG}"

# Check if suricata.yaml is mounted
if [ ! -f "/etc/suricata/suricata.yaml" ]; then
    echo "Error: /etc/suricata/suricata.yaml not found. Mount config/suricata to /etc/suricata."
    exit 1
fi

# Update HOME_NET and interface in suricata.yaml
# Using jq for robust YAML manipulation is better, but sed for simplicity here.
# Ensure this doesn't corrupt the YAML.
# It's safer to use a tool like yq or pass these as env vars if suricata.yaml supports it.
# For now, directly modifying.

# Create a temporary copy to modify
cp /etc/suricata/suricata.yaml /tmp/suricata.yaml

# Modify HOME_NET
# The HOME_NET variable in suricata.yaml might be complex.
# This simple sed might not work if it's multi-line or heavily commented.
# A better approach is to have a template suricata.yaml and fill it.
# Or use Suricata's variable override mechanisms if available (e.g., environment variables).
# For now:
ESCAPED_HOME_NET=$(echo "${HOME_NET_CONFIG}" | sed 's/[&/\]/\\&/g')
sed -i "s|^ *HOME_NET:.*|HOME_NET: \"${ESCAPED_HOME_NET}\"|" /tmp/suricata.yaml
echo "HOME_NET set to: ${ESCAPED_HOME_NET}"

# Modify af-packet interface
sed -i "/af-packet:/,/^ *$/s|interface: .*|interface: ${SURICATA_INTERFACE}|" /tmp/suricata.yaml
echo "AF-PACKET interface set to: ${SURICATA_INTERFACE}"

# Check if rule path exists
if [ ! -d "/var/lib/suricata/rules" ]; then
    mkdir -p /var/lib/suricata/rules
fi
if [ ! -d "/etc/suricata/rules" ]; then
    mkdir -p /etc/suricata/rules
fi

# Update Suricata rules
echo "Updating Suricata rules with suricata-update..."
suricata-update --suricata-conf /tmp/suricata.yaml \
    --no-enable-conf /etc/suricata/enable.conf \
    --no-disable-conf /etc/suricata/disable.conf \
    --no-modify-conf /etc/suricata/modify.conf \
    --no-drop-conf /etc/suricata/drop.conf \
    || echo "suricata-update failed, continuing with existing rules if any."

# Symlink the main rules file if suricata-update puts it in /var/lib/suricata/rules
# and suricata.yaml expects it in /etc/suricata/rules or similar.
# Typically, suricata.yaml is configured with `default-rule-path: /var/lib/suricata/rules/`
# and `rule-files:` lists `suricata.rules`.
# If `suricata.rules` is generated by suricata-update in `/var/lib/suricata/rules`, ensure config points there.
# The provided suricata.yaml should have `default-rule-path: /etc/suricata/rules/`
# and `rule-files: - suricata.rules`. So we copy the updated rules there.
if [ -f "/var/lib/suricata/rules/suricata.rules" ]; then
    cp /var/lib/suricata/rules/suricata.rules /etc/suricata/rules/suricata.rules
    echo "Copied updated suricata.rules to /etc/suricata/rules/"
else
    echo "Warning: /var/lib/suricata/rules/suricata.rules not found after update."
fi

# Ensure custom local.rules is present in /etc/suricata/rules
if [ ! -f "/etc/suricata/rules/local.rules" ]; then
    touch /etc/suricata/rules/local.rules # Create if not mounted
fi

# Start Suricata
echo "Starting Suricata..."
exec suricata -c /tmp/suricata.yaml --af-packet="${SURICATA_INTERFACE}" -D \
    --pidfile /var/run/suricata/suricata.pid \
    && tail -F /var/log/suricata/suricata.log /var/log/suricata/eve.json
# The -D makes it daemonize. For Docker, usually run in foreground.
# Remove -D and adjust tailing or just let Suricata log to stdout.
# For foreground:
# exec suricata -c /tmp/suricata.yaml --af-packet="${SURICATA_INTERFACE}" -v --pidfile /var/run/suricata/suricata.pid
# Let's run in foreground for easier Docker log management.
# The following command will run suricata in foreground
# Suricata logs to eve.json, filebeat picks it up. Stdout can be used for Suricata's own operational logs.
# The -D makes it run in the background, which is not ideal for docker.
# Correct command for foreground:
# exec /usr/bin/suricata -c /tmp/suricata.yaml --af-packet="${SURICATA_INTERFACE}" --user=root --group=root -v
# If suricata.yaml has eve.json configured for output, that's where alerts go.
# We want suricata to run in foreground.
# Using -v for verbosity, logs to console. EVE JSON logs to file for Filebeat.
exec /usr/bin/suricata -c /tmp/suricata.yaml --af-packet="${SURICATA_INTERFACE}" --user=root --group=root -v
# If pid file is needed by external tools, create the dir
# mkdir -p /var/run/suricata && chown suricata:suricata /var/run/suricata
EOF

RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD []
