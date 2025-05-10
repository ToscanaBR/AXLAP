FROM ubuntu:22.04

ARG ZEEK_VERSION=5.0.8 # Choose a stable Zeek version
# For Zeek 6+, JSON logging is more streamlined. Using 5.0.8 for wider compatibility.

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    make \
    swig \
    libssl-dev \
    libGeoIP-dev \
    libpcap-dev \
    libmaxminddb-dev \
    python3 \
    python3-dev \
    python3-pip \
    python3-git \
    python3-semantic-version \
    zlib1g-dev \
    curl \
    git \
    bison \
    flex \
    && rm -rf /var/lib/apt/lists/*

# Install Zeek from source
RUN mkdir /opt/zeek_src && cd /opt/zeek_src \
    && curl -sSL https://download.zeek.org/zeek-${ZEEK_VERSION}.tar.gz -o zeek-${ZEEK_VERSION}.tar.gz \
    && tar -xzf zeek-${ZEEK_VERSION}.tar.gz \
    && cd zeek-${ZEEK_VERSION} \
    && ./configure --prefix=/usr/local/zeek --disable-broker --disable-jemalloc --enable-json-logs --enable-af-packet \
    && make -j$(nproc) \
    && make install \
    && cd / && rm -rf /opt/zeek_src

# Set up Zeek environment
ENV PATH="/usr/local/zeek/bin:${PATH}"

# Create necessary directories for Zeek
RUN mkdir -p /usr/local/zeek/spool \
    && mkdir -p /usr/local/zeek/logs \
    && mkdir -p /var/log/zeek_json \
    && mkdir -p /data/pcap \
    && mkdir -p /opt/axlap/zeek_plugins \
    && mkdir -p /opt/axlap/threat_intel

# Copy Zeek configurations
COPY ./config/zeek/node.cfg /usr/local/zeek/etc/node.cfg
COPY ./config/zeek/networks.cfg /usr/local/zeek/etc/networks.cfg
# local.zeek will be mounted to /usr/local/zeek/share/zeek/site/local.zeek

# ZeekControl setup
RUN echo "export PATH=/usr/local/zeek/bin:\$PATH" >> /etc/bash.bashrc
RUN /usr/local/zeek/bin/zeekctl install

# Expose ZEEK_LOG_JSON for local.zeek or scripts to potentially use
ARG ZEEK_INTERFACE=eth0
ENV ZEEK_INTERFACE=${ZEEK_INTERFACE}

# Configure logging directory in zeekctl.cfg
RUN sed -i "s|^LogDir.*|LogDir = /usr/local/zeek/logs|" /usr/local/zeek/etc/zeekctl.cfg \
    && sed -i "s|^SpoolDir.*|SpoolDir = /usr/local/zeek/spool|" /usr/local/zeek/etc/zeekctl.cfg \
    # Configure Zeek to output JSON logs to the mounted volume
    # This can also be done via local.zeek: redef Log::logdir = "/var/log/zeek_json";
    # And ensuring JSON output: redef Log::default_log_writer = Log::WRITER_JSON;
    # Here, we assume local.zeek handles these definitions.
    # Add mail_dest to avoid zeekctl warnings, even if not sending mail
    && echo "MailTo = root@localhost" >> /usr/local/zeek/etc/zeekctl.cfg \
    && echo "LogRotationInterval = 3600" >> /usr/local/zeek/etc/zeekctl.cfg \ 
    && echo "JsonLog::enable = T" >> /usr/local/zeek/etc/zeekctl.cfg # For zkg packages using JsonLog module \
    && echo "LocalSite::local_nets += { ${LOCAL_NETS_FROM_ENV:-192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12} }" >> /usr/local/zeek/share/zeek/site/local.zeek
    # The line above for LocalSite::local_nets is an example; networks.cfg is primary.

# Entrypoint script to start Zeek
COPY <<EOF /usr/local/bin/entrypoint.sh
#!/bin/bash
set -e

echo "AXLAP Zeek Entrypoint"
echo "ZEEK_INTERFACE: \${ZEEK_INTERFACE}"
echo "Configuring Zeek interface in node.cfg..."
sed -i "s|interface=.*|interface=\${ZEEK_INTERFACE}|" /usr/local/zeek/etc/node.cfg

# Ensure site/local.zeek is present from volume mount, otherwise create a basic one
if [ ! -f "/usr/local/zeek/share/zeek/site/local.zeek" ]; then
    echo "Error: /usr/local/zeek/share/zeek/site/local.zeek not found. Mount config/zeek to this location."
    exit 1
fi
# Ensure plugin directory is accessible
if [ ! -d "/opt/axlap/zeek_plugins" ]; then
    echo "Warning: /opt/axlap/zeek_plugins not found."
fi

# Ensure log directory exists and has correct permissions for zeek user
if getent passwd zeek > /dev/null 2>&1; then
    mkdir -p /var/log/zeek_json
    chown -R zeek:zeek /var/log/zeek_json
else
    echo "Warning: 'zeek' user not found. Ensure correct permissions for log directory if needed."
fi

# Check zeekctl config and install if needed
echo "Running zeekctl install..." && /usr/local/zeek/bin/zeekctl install || echo "Zeekctl install may have non-fatal errors, continuing..."

# Deploy Zeek using zeekctl
echo "Deploying Zeek..."
/usr/local/zeek/bin/zeekctl deploy

# Keep container running and show logs
echo "Tailing Zeek manager log..."
tail -F /usr/local/zeek/spool/manager/current.status /usr/local/zeek/spool/manager/*.log /var/log/zeek_json/*
EOF

RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD [] # Not needed due to entrypoint
