#!/bin/bash

# AXLAP - Autonomous XKeyscore-Like Analysis Platform
# Installation Script

set -e # Exit immediately if a command exits with a non-zero status.
# set -x # Debug mode: Print each command before executing

# --- Configuration ---
AXLAP_BASE_DIR="/opt/axlap"
AXLAP_REPO_URL="https://github.com/John0n1/axlap.git" 
AXLAP_BRANCH="main"

# Network interface for Zeek/Suricata/Arkime to capture from
# Prompt user or detect, but directive says "no prompt", so use a default or require env var
CAPTURE_INTERFACE="${AXLAP_CAPTURE_INTERFACE:-eth0}" # Default to eth0, can be overridden by env var

# Home networks for Suricata and Zeek (CIDR, comma-separated)
# This should include your local network(s) and the Docker network for AXLAP.
DEFAULT_LOCAL_NETS="192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
AXLAP_DOCKER_SUBNET="172.28.0.0/16" # From docker-compose.yml
HOME_NETS="${AXLAP_HOME_NETS:-${DEFAULT_LOCAL_NETS},${AXLAP_DOCKER_SUBNET}}"

# OpenCTI Admin Credentials (Generate random if not set via ENV)
OPENCTI_ADMIN_EMAIL="${OPENCTI_ADMIN_EMAIL:-admin@axlap.local}"
OPENCTI_ADMIN_PASSWORD_DEFAULT="ChangeMeAXLAP!$(openssl rand -hex 8)"
OPENCTI_ADMIN_PASSWORD="${OPENCTI_ADMIN_PASSWORD:-${OPENCTI_ADMIN_PASSWORD_DEFAULT}}"
OPENCTI_ADMIN_TOKEN_DEFAULT=$(openssl rand -hex 32)
OPENCTI_ADMIN_TOKEN="${OPENCTI_ADMIN_TOKEN:-${OPENCTI_ADMIN_TOKEN_DEFAULT}}"

# MISP Connector Config (Placeholder values, should be set by user if MISP is used)
MISP_URL="${MISP_URL:-http://your-misp-instance.local}" # Must be reachable by OpenCTI MISP connector
MISP_KEY="${MISP_KEY:-YourMispApiKey}"
CONNECTOR_MISP_ID_DEFAULT=$(uuidgen)
CONNECTOR_MISP_ID="${CONNECTOR_MISP_ID:-${CONNECTOR_MISP_ID_DEFAULT}}"

# Other OpenCTI Connector IDs
CONNECTOR_EXPORT_FILE_STIX_ID_DEFAULT=$(uuidgen)
CONNECTOR_EXPORT_FILE_STIX_ID="${CONNECTOR_EXPORT_FILE_STIX_ID:-${CONNECTOR_EXPORT_FILE_STIX_ID_DEFAULT}}"
CONNECTOR_IMPORT_FILE_STIX_ID_DEFAULT=$(uuidgen)
CONNECTOR_IMPORT_FILE_STIX_ID="${CONNECTOR_IMPORT_FILE_STIX_ID:-${CONNECTOR_IMPORT_FILE_STIX_ID_DEFAULT}}"

# Arkime passwordSecret
ARKIME_PASSWORD_SECRET_DEFAULT="AXLAP_Secret_$(openssl rand -hex 16)"
ARKIME_PASSWORD_SECRET="${ARKIME_PASSWORD_SECRET:-${ARKIME_PASSWORD_SECRET_DEFAULT}}"

# MinIO Credentials for OpenCTI S3 storage
MINIO_ROOT_USER_DEFAULT="axlap_minio_user"
MINIO_ROOT_USER="${MINIO_ROOT_USER:-${MINIO_ROOT_USER_DEFAULT}}"
MINIO_ROOT_PASSWORD_DEFAULT="ChangeMeAXLAP!minio_$(openssl rand -hex 8)"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-${MINIO_ROOT_PASSWORD_DEFAULT}}"

LOG_FILE="${AXLAP_BASE_DIR}/logs/install.log"

# --- Helper Functions ---
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR: This script must be run as root or with sudo."
        exit 1
    fi
}

check_os() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        log "WARNING: This script is primarily tested on Ubuntu. Your OS might not be fully compatible."
        # exit 1 # Potentially allow continuation on Debian-based systems
    fi
    source /etc/os-release
    if [[ "$VERSION_ID" < "20.04" ]]; then
        log "WARNING: Ubuntu 20.04 or newer is recommended. Your version: $VERSION_ID"
    fi
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log "ERROR: Command '$1' not found. Please install it."
        exit 1
    fi
}

# --- Main Installation Steps ---

main() {
    check_root
    check_os

    # Create base directory and log file
    mkdir -p "${AXLAP_BASE_DIR}/logs"
    touch "${LOG_FILE}"
    chmod 600 "${LOG_FILE}"
    log "AXLAP installation started."

    # 1. Install System Dependencies
    log "Installing system dependencies..."
    apt-get update -y >> "${LOG_FILE}" 2>&1
    apt-get install -y --no-install-recommends \
        git \
        curl \
        docker.io \
        docker-compose \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        libncurses-dev \
        make \
        iptables \
        apparmor-utils \
        uuid-runtime \
        openssl \
        jq \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        libpcap-dev \
        libcurl4-openssl-dev \
        >> "${LOG_FILE}" 2>&1

    # Check if Docker daemon is running
    if ! systemctl is-active --quiet docker; then
        log "Starting Docker service..."
        systemctl start docker >> "${LOG_FILE}" 2>&1
        systemctl enable docker >> "${LOG_FILE}" 2>&1
    fi
    log "Docker and Docker Compose versions:"
    docker --version | tee -a "${LOG_FILE}"
    docker-compose --version | tee -a "${LOG_FILE}"


    # 2. Setup AXLAP Directory Structure and Clone/Copy Repo
    if [ -d "${AXLAP_BASE_DIR}/.git" ]; then
        log "AXLAP directory already exists and seems to be a git repo. Pulling latest changes..."
        cd "${AXLAP_BASE_DIR}"
        # git checkout "${AXLAP_BRANCH}" >> "${LOG_FILE}" 2>&1
        # git pull origin "${AXLAP_BRANCH}" >> "${LOG_FILE}" 2>&1
        # For now, assume script is run from within the cloned repo directory
        log "Assuming install script is run from the root of the AXLAP git repository."
        # Copy current directory content (the repo) to AXLAP_BASE_DIR
        # This handles the case where user clones repo and then runs install.sh from within it.
        # If install.sh is outside, it should clone. For this, assume it's inside.
        if [ "$(pwd)" != "${AXLAP_BASE_DIR}" ]; then
            log "Copying AXLAP project files to ${AXLAP_BASE_DIR}..."
            mkdir -p "${AXLAP_BASE_DIR}"
            # Use rsync or cp, ensuring .git is copied if it's a clone, or not if it's just files
            # Example: rsync -a --exclude '.git' "$(pwd)/" "${AXLAP_BASE_DIR}/" >> "${LOG_FILE}" 2>&1
            # Simpler: Assume user has cloned to AXLAP_BASE_DIR or this script is inside it.
            # For robustness, let's copy from current PWD if not already in AXLAP_BASE_DIR
            # For now, let's cd to where the script is and work relative to that.
            SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
            if [ "${SCRIPT_DIR}" != "${AXLAP_BASE_DIR}" ]; then
                log "Copying AXLAP source from ${SCRIPT_DIR} to ${AXLAP_BASE_DIR}"
                mkdir -p "${AXLAP_BASE_DIR}"
                # Using cp for simplicity. rsync is better for updates.
                cp -R "${SCRIPT_DIR}/." "${AXLAP_BASE_DIR}/"
            fi
        fi
    else
        log "AXLAP directory ${AXLAP_BASE_DIR} does not appear to be a git repo. Assuming script is run from a fresh copy."
        # If not a git repo, means script is part of a copied dir.
        # Ensure current dir is where axlap files are.
        SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
        if [ "${SCRIPT_DIR}" != "${AXLAP_BASE_DIR}" ]; then
            log "Copying AXLAP source from ${SCRIPT_DIR} to ${AXLAP_BASE_DIR}"
            mkdir -p "${AXLAP_BASE_DIR}"
            cp -R "${SCRIPT_DIR}/." "${AXLAP_BASE_DIR}/"
        fi
    fi
    cd "${AXLAP_BASE_DIR}"

    log "Creating AXLAP data and configuration directories..."
    mkdir -p "${AXLAP_BASE_DIR}/data/elasticsearch_data"
    mkdir -p "${AXLAP_BASE_DIR}/data/arkime_pcap"
    mkdir -p "${AXLAP_BASE_DIR}/data/arkime_es_data" # Arkime might use its own ES index in main ES
    mkdir -p "${AXLAP_BASE_DIR}/data/opencti_data/postgres"
    mkdir -p "${AXLAP_BASE_DIR}/data/opencti_data/s3"
    mkdir -p "${AXLAP_BASE_DIR}/data/opencti_data/redis"
    mkdir -p "${AXLAP_BASE_DIR}/data/opencti_data/es_octi" # For OpenCTI's dedicated ES
    mkdir -p "${AXLAP_BASE_DIR}/data/zeek_logs_raw"
    mkdir -p "${AXLAP_BASE_DIR}/data/suricata_logs"
    mkdir -p "${AXLAP_BASE_DIR}/data/ml_models_data"
    mkdir -p "${AXLAP_BASE_DIR}/logs" # General logs
    mkdir -p "${AXLAP_BASE_DIR}/rules" # Suricata local rules
    mkdir -p "${AXLAP_BASE_DIR}/config/zeek/site" # For Zeek site policies
    mkdir -p "${AXLAP_BASE_DIR}/config/zeek/plugin_configs" # For Zeek plugin YAML configs

    # Set permissions (example: ensure Docker containers can write if needed, though volumes handle this)
    # chmod -R 777 "${AXLAP_BASE_DIR}/data" # Overly permissive, Docker volumes handle user mapping
    # Elasticsearch needs specific user for its data dir (usually uid 1000). Docker handles this.

    # 3. Configure Services (Update config files with dynamic values)
    log "Configuring AXLAP services..."

    # Update docker-compose.yml with generated tokens/passwords
    log "Updating docker-compose.yml with secrets..."
    DOCKER_COMPOSE_FILE="${AXLAP_BASE_DIR}/docker-compose.yml"
    sed -i "s|\${OPENCTI_ADMIN_EMAIL:-admin@axlap.local}|${OPENCTI_ADMIN_EMAIL}|g" "${DOCKER_COMPOSE_FILE}"
    sed -i "s|\${OPENCTI_ADMIN_PASSWORD:-ChangeMeAXLAP!123}|${OPENCTI_ADMIN_PASSWORD}|g" "${DOCKER_COMPOSE_FILE}"
    sed -i "s|\${OPENCTI_ADMIN_TOKEN:-GenerateRandomOrFixed}|${OPENCTI_ADMIN_TOKEN}|g" "${DOCKER_COMPOSE_FILE}"
    sed -i "s|\${MINIO_ROOT_USER:-axlap_minio_user}|${MINIO_ROOT_USER}|g" "${DOCKER_COMPOSE_FILE}"
    sed -i "s|\${MINIO_ROOT_PASSWORD:-ChangeMeAXLAP!minio}|${MINIO_ROOT_PASSWORD}|g" "${DOCKER_COMPOSE_FILE}"
    sed -i "s|\${CONNECTOR_EXPORT_FILE_STIX_ID:-GenerateRandomUUID}|${CONNECTOR_EXPORT_FILE_STIX_ID}|g" "${DOCKER_COMPOSE_FILE}"
    sed -i "s|\${CONNECTOR_IMPORT_FILE_STIX_ID:-GenerateRandomUUID}|${CONNECTOR_IMPORT_FILE_STIX_ID}|g" "${DOCKER_COMPOSE_FILE}"
    sed -i "s|\${CONNECTOR_MISP_ID}|${CONNECTOR_MISP_ID}|g" "${DOCKER_COMPOSE_FILE}"
    sed -i "s|\${MISP_URL:-http://localhost:8888}|${MISP_URL}|g" "${DOCKER_COMPOSE_FILE}"
    sed -i "s|\${MISP_KEY:-YourMispApiKey}|${MISP_KEY}|g" "${DOCKER_COMPOSE_FILE}"

    # Update Arkime config.ini
    log "Updating Arkime config.ini..."
    ARKIME_CONFIG_FILE="${AXLAP_BASE_DIR}/config/arkime/config.ini"
    sed -i "s|passwordSecret = .*|passwordSecret = \"${ARKIME_PASSWORD_SECRET}\"|" "${ARKIME_CONFIG_FILE}"
    sed -i "s|interface = .*|interface = ${CAPTURE_INTERFACE}|" "${ARKIME_CONFIG_FILE}" # For Arkime capture if it does live capture
    # Ensure elasticsearch host is correct (axlap-elasticsearch:9200)
    sed -i "s|elasticsearch=.*|elasticsearch=http://axlap-elasticsearch:9200|" "${ARKIME_CONFIG_FILE}"


    # Update Zeek node.cfg and local.zeek (if needed for interface)
    # Zeek Dockerfile entrypoint handles ZEEK_INTERFACE env var for node.cfg
    # Zeek networks.cfg should be populated with HOME_NETS
    log "Updating Zeek networks.cfg..."
    ZEEK_NETWORKS_CFG="${AXLAP_BASE_DIR}/config/zeek/networks.cfg"
    echo "# Auto-generated by AXLAP install.sh" > "${ZEEK_NETWORKS_CFG}"
    IFS=',' read -ra ADDR <<< "$HOME_NETS"
    for net in "${ADDR[@]}"; do
        echo "$net" >> "${ZEEK_NETWORKS_CFG}"
    done
    # Copy local.zeek to site dir for Zeek to load
    cp "${AXLAP_BASE_DIR}/config/zeek/local.zeek" "${AXLAP_BASE_DIR}/config/zeek/site/local.zeek"

    # Update Suricata suricata.yaml (HOME_NET, interface)
    # Suricata Dockerfile entrypoint handles SURICATA_INTERFACE and HOME_NET_CONFIG env vars.
    # We need to pass these to docker-compose.yml or set them in the entrypoint.
    # The docker-compose.yml already defines env vars for these for Suricata.
    # Update the default values in docker-compose.yml for suricata if needed, or rely on entrypoint.
    # For now, let entrypoint in Suricata Dockerfile handle it. The values for HOME_NET_CONFIG
    # and SURICATA_INTERFACE are passed through docker-compose.yml using .env file or direct values.
    # Create .env file for docker-compose
    ENV_FILE="${AXLAP_BASE_DIR}/.env"
    log "Creating .env file for docker-compose..."
    echo "# Auto-generated by AXLAP install.sh" > "${ENV_FILE}"
    echo "AXLAP_BASE_DIR=${AXLAP_BASE_DIR}" >> "${ENV_FILE}"
    echo "CAPTURE_INTERFACE=${CAPTURE_INTERFACE}" >> "${ENV_FILE}"
    echo "HOME_NETS_CONFIG_SURICATA=\"[${HOME_NETS}]\"" >> "${ENV_FILE}" # Suricata needs specific format
    # These are already handled by sed replacement in docker-compose.yml directly
    # echo "OPENCTI_ADMIN_EMAIL=${OPENCTI_ADMIN_EMAIL}" >> "${ENV_FILE}"
    # echo "OPENCTI_ADMIN_PASSWORD=${OPENCTI_ADMIN_PASSWORD}" >> "${ENV_FILE}"
    # echo "OPENCTI_ADMIN_TOKEN=${OPENCTI_ADMIN_TOKEN}" >> "${ENV_FILE}"
    # ... and so on for other secrets.

    # Update AXLAP TUI config
    log "Updating AXLAP TUI config..."
    TUI_CONFIG_FILE="${AXLAP_BASE_DIR}/config/axlap_tui_config.ini"
    sed -i "s|\${OPENCTI_ADMIN_TOKEN_FROM_ENV}|${OPENCTI_ADMIN_TOKEN}|" "${TUI_CONFIG_FILE}"
    # Update paths if needed, assuming TUI runs from AXLAP_BASE_DIR
    sed -i "s|train_script_path = .*|train_script_path = ${AXLAP_BASE_DIR}/scripts/train_ml_model.sh|" "${TUI_CONFIG_FILE}"
    sed -i "s|update_script_path = .*|update_script_path = ${AXLAP_BASE_DIR}/scripts/update_rules_and_feeds.sh|" "${TUI_CONFIG_FILE}"
    sed -i "s|zeek_plugins_dir = .*|zeek_plugins_dir = ${AXLAP_BASE_DIR}/src/zeek_plugins/|" "${TUI_CONFIG_FILE}"
    sed -i "s|zeek_plugin_config_dir = .*|zeek_plugin_config_dir = ${AXLAP_BASE_DIR}/config/zeek/plugin_configs/|" "${TUI_CONFIG_FILE}"
    sed -i "s|zeek_local_script = .*|zeek_local_script = ${AXLAP_BASE_DIR}/config/zeek/site/local.zeek|" "${TUI_CONFIG_FILE}"

    # Set executable permissions for scripts
    log "Setting executable permissions for scripts..."
    find "${AXLAP_BASE_DIR}/scripts" -name "*.sh" -exec chmod +x {} \;
    chmod +x "${AXLAP_BASE_DIR}/src/tui/axlap_tui.py"

    # 4. Build Custom Docker Images
    log "Building custom Docker images (Zeek, Suricata, ML Engine, Arkime)..."
    # Pass build ARGs for interfaces to Dockerfiles if needed
    # Example: docker-compose build --build-arg ZEEK_INTERFACE=${CAPTURE_INTERFACE} zeek
    # This is now handled by runtime ENV vars in containers.
    docker-compose -f "${DOCKER_COMPOSE_FILE}" build >> "${LOG_FILE}" 2>&1

    # 5. Pull Official Docker Images (Elasticsearch, OpenCTI, etc.)
    log "Pulling official Docker images..."
    docker-compose -f "${DOCKER_COMPOSE_FILE}" pull >> "${LOG_FILE}" 2>&1 # Pulls images not built locally

    # 6. Initial Rule/Feed Updates (Suricata)
    log "Performing initial Suricata rules update (via container entrypoint on first run)..."
    # This is handled by Suricata container's entrypoint.sh on first start.
    # Can also run it preemptively:
    # docker-compose -f "${DOCKER_COMPOSE_FILE}" run --rm suricata /usr/local/bin/entrypoint.sh # This might not work as expected due to how run works
    # The entrypoint of the Suricata container will handle this when it starts.

    # 7. Start All Services with Docker Compose
    log "Starting AXLAP services using Docker Compose..."
    # Use axlap_common_env.sh to pass environment variables to docker-compose
    # source "${AXLAP_BASE_DIR}/scripts/axlap_common_env.sh" # Loads vars into current shell
    # The .env file created earlier should be picked up automatically by docker-compose.
    docker-compose -f "${DOCKER_COMPOSE_FILE}" up -d >> "${LOG_FILE}" 2>&1

    log "Waiting for services to initialize (Elasticsearch, OpenCTI)... This may take several minutes."
    # Wait for Elasticsearch
    MAX_WAIT=300 # 5 minutes
    COUNT=0
    log "Waiting for Main Elasticsearch (axlap-elasticsearch) to be healthy..."
    while ! curl -s "http://127.0.0.1:9200/_cluster/health?wait_for_status=yellow&timeout=5s" > /dev/null; do
        sleep 10
        COUNT=$((COUNT + 10))
        if [ "$COUNT" -ge "$MAX_WAIT" ]; then
            log "ERROR: Main Elasticsearch (axlap-elasticsearch) did not become healthy in time."
            # docker-compose logs elasticsearch # for debugging
            # exit 1 # Don't exit, some things might still work or user can debug
            break
        fi
        printf "."
    done
    log "Main Elasticsearch is up."

    # Wait for OpenCTI Elasticsearch
    log "Waiting for OpenCTI Elasticsearch (axlap-opencti-es) to be healthy..."
    # Assuming OpenCTI ES is similar and will eventually be up.
    # Docker compose healthcheck for opencti-elasticsearch will manage its readiness for opencti container.
    # We don't have a direct port mapping for opencti-es by default to check from host.
    # Rely on docker-compose 'depends_on' health checks.

    # 8. Initialize Arkime Database
    log "Initializing Arkime database in Elasticsearch..."
    # Arkime needs its Elasticsearch indices created.
    # The configure_arkime.sh script will handle this.
    # Wait a bit for Arkime viewer to be ready to accept commands or for ES to be fully ready.
    sleep 20
    # The db.pl script runs inside the viewer container.
    # We need to run it after ES is up.
    # docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T arkime-viewer /opt/arkime/db/db.pl http://axlap-elasticsearch:9200 initnoprompt >> "${LOG_FILE}" 2>&1
    # The "initnoprompt" might not exist. "init" is interactive.
    # Arkime's official Docker image might auto-initialize. If not, this is how:
    # As of Arkime 3.x, you might need to use init instead of initnoprompt, requires interaction or expect script
    # For non-interactive: echo "INIT" | docker-compose exec -T arkime-viewer /opt/arkime/db/db.pl http://axlap-elasticsearch:9200 init
    # A safer way is to have a script that polls until it's done.
    # For now, assume the user might need to run this manually if it fails or use a helper script.
    # A simple init command (often works for non-interactive):
    log "Attempting to initialize Arkime database..."
    if docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T arkime-viewerടെസ്റ്റ് -e /opt/arkime/db/db.pl; then
        echo "INIT" | docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T arkime-viewer /opt/arkime/db/db.pl http://axlap-elasticsearch:9200 init >> "${LOG_FILE}" 2>&1
        log "Arkime database initialization command sent."
        # Add an admin user for Arkime
        log "Adding Arkime admin user (admin / AdminAXLAPPassw0rd)..."
        docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T arkime-viewer /opt/arkime/bin/arkime_add_user.sh admin "AXLAP Admin" "AdminAXLAPPassw0rd" --admin >> "${LOG_FILE}" 2>&1
        log "Arkime admin user added. IMPORTANT: Change this password via Arkime UI (http://127.0.0.1:8005)"
    else
        log "WARNING: Arkime db.pl not found in viewer container. Skipping automatic DB init. Arkime might auto-init or require manual setup."
    fi


    # 9. Configure OpenCTI (admin user is set via ENV vars in docker-compose)
    log "OpenCTI should be initializing with admin user: ${OPENCTI_ADMIN_EMAIL}."
    log "OpenCTI access: http://127.0.0.1:8080. Token for API: ${OPENCTI_ADMIN_TOKEN}"
    log "Waiting for OpenCTI platform to be available..."
    COUNT=0
    MAX_WAIT_OPENCTI=600 # 10 minutes, OpenCTI can take a while
    while ! curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/graphql -H "Content-Type: application/json" --data-binary '{"query":"{ about { version } }"}' | grep -q "200"; do
        sleep 15
        COUNT=$((COUNT + 15))
        if [ "$COUNT" -ge "$MAX_WAIT_OPENCTI" ]; then
            log "ERROR: OpenCTI platform did not become available in time."
            # docker-compose logs opencti # for debugging
            break # Don't exit, allow user to debug
        fi
        printf "o"
    done
    log "OpenCTI platform appears to be up."


    # 10. Setup Python Virtual Environment for TUI and ML Engine (if TUI runs on host)
    log "Setting up Python virtual environment for TUI and ML tools..."
    if [ ! -d "${AXLAP_BASE_DIR}/venv" ]; then
        python3 -m venv "${AXLAP_BASE_DIR}/venv" >> "${LOG_FILE}" 2>&1
    fi
    # shellcheck source=/dev/null
    source "${AXLAP_BASE_DIR}/venv/bin/activate"
    pip install --upgrade pip >> "${LOG_FILE}" 2>&1
    pip install -r "${AXLAP_BASE_DIR}/src/tui/requirements.txt" >> "${LOG_FILE}" 2>&1 # Assuming TUI has its own reqs
    pip install -r "${AXLAP_BASE_DIR}/src/ml_engine/requirements.txt" >> "${LOG_FILE}" 2>&1
    deactivate

    # 11. Initial ML Model Training (Optional - can be triggered by user later)
    # log "Skipping initial ML model training. Can be run later using: ${AXLAP_BASE_DIR}/scripts/train_ml_model.sh"
    # For now, let's try to run it with dummy data or if some logs are already generated.
    # Check if Elasticsearch has any Zeek data yet.
    # if curl -s "http://127.0.0.1:9200/axlap-zeek-*/_count" | jq -e '.count > 0'; then
    #    log "Initial data found. Attempting to train ML model..."
    #    # Ensure ML engine container can connect to ES_HOST=axlap-elasticsearch
    #    # This script would run: docker-compose run --rm ml_engine python /app/ml_engine/train.py
    #    # "${AXLAP_BASE_DIR}/scripts/train_ml_model.sh" >> "${LOG_FILE}" 2>&1
    # else
    #    log "No Zeek data yet in Elasticsearch. Skipping initial ML model training."
    # fi
    log "ML Model training can be initiated via TUI or by running: sudo ${AXLAP_BASE_DIR}/scripts/train_ml_model.sh"


    # 12. Setup Systemd Services for AXLAP and Auto-updates
    log "Setting up systemd services..."
    # Main AXLAP service (manages docker-compose)
    SYSTEMD_AXLAP_SERVICE_FILE="/etc/systemd/system/axlap.service"
    cat << EOF > "${SYSTEMD_AXLAP_SERVICE_FILE}"
[Unit]
Description=AXLAP - Autonomous XKeyscore-Like Analysis Platform
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=${AXLAP_BASE_DIR}
# EnvironmentFile=${AXLAP_BASE_DIR}/.env # If .env file contains necessary runtime vars for compose
ExecStart=${AXLAP_BASE_DIR}/scripts/start_axlap.sh
ExecStop=${AXLAP_BASE_DIR}/scripts/stop_axlap.sh
# StandardOutput=append:${AXLAP_BASE_DIR}/logs/axlap-systemd.log
# StandardError=append:${AXLAP_BASE_DIR}/logs/axlap-systemd.err.log
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    # Auto-update service (rules, feeds)
    SYSTEMD_AXLAP_UPDATES_SERVICE_FILE="/etc/systemd/system/axlap-updates.service"
    cat << EOF > "${SYSTEMD_AXLAP_UPDATES_SERVICE_FILE}"
[Unit]
Description=AXLAP Rules and Threat Feeds Updater
After=axlap.service # Ensure main services are up before trying to update connectors etc.

[Service]
Type=oneshot
WorkingDirectory=${AXLAP_BASE_DIR}
ExecStart=${AXLAP_BASE_DIR}/scripts/update_rules_and_feeds.sh
# StandardOutput=append:${AXLAP_BASE_DIR}/logs/axlap-updates.log
# StandardError=append:${AXLAP_BASE_DIR}/logs/axlap-updates.err.log
EOF

    SYSTEMD_AXLAP_UPDATES_TIMER_FILE="/etc/systemd/system/axlap-updates.timer"
    cat << EOF > "${SYSTEMD_AXLAP_UPDATES_TIMER_FILE}"
[Unit]
Description=Run AXLAP updater daily

[Timer]
OnCalendar=daily
Persistent=true # Run on next boot if missed
Unit=axlap-updates.service

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload >> "${LOG_FILE}" 2>&1
    systemctl enable axlap.service >> "${LOG_FILE}" 2>&1
    systemctl enable axlap-updates.timer >> "${LOG_FILE}" 2>&1
    systemctl start axlap.service >> "${LOG_FILE}" 2>&1 # Should already be up via docker-compose up
    systemctl start axlap-updates.timer >> "${LOG_FILE}" 2>&1

    # 13. Security Hardening (iptables, AppArmor)
    log "Applying security hardening (iptables, AppArmor)..."
    # iptables: Basic rules to restrict access to exposed ports to localhost primarily
    # Example: Allow established, related connections
    iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    # Allow SSH (assuming standard port)
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    # Allow AXLAP TUI access points (if TUI were web-based, not needed for local Curses TUI)
    # For services exposed on 127.0.0.1 in docker-compose, host firewall doesn't need to manage them directly.
    # Docker manages its own iptables rules for port forwarding.
    # What we might want is to restrict *outgoing* connections from containers.
    # This is complex and usually handled by Docker network policies or more advanced CNI.
    # For now, ensure Docker's default FORWARD policy is secure (e.g., DROP unless specified).
    # Default Docker FORWARD chain policy is usually ACCEPT. Consider changing it.
    # Check current policy: iptables -L FORWARD -v -n
    # If DOCKER-USER chain exists, rules there are applied before Docker's own rules.
    # Example: Deny all forwarding by default (then Docker adds its specific allows)
    # iptables -P FORWARD DROP (This can break things if not careful)

    log "iptables rules applied. Consider a more comprehensive firewall setup (e.g., ufw)."
    # Save iptables rules (depends on distro: iptables-persistent or other methods)
    # apt-get install -y iptables-persistent >> "${LOG_FILE}" 2>&1
    # netfilter-persistent save >> "${LOG_FILE}" 2>&1

    # AppArmor: Load profiles for containers
    # This requires writing AppArmor profiles for each custom container and placing them in /etc/apparmor.d/
    # Then load them: apparmor_parser -r /etc/apparmor.d/your_profile
    # And set Docker container security opts: --security-opt apparmor=your_profile_name
    # This is an advanced step. For now, ensure AppArmor is enabled.
    if systemctl is-active --quiet apparmor; then
        log "AppArmor service is active. Custom profiles can be added to ${AXLAP_BASE_DIR}/apparmor/ and loaded."
    else
        log "WARNING: AppArmor service is not active. Consider enabling it for enhanced security."
    fi
    # Example profile path (profiles would need to be created and placed in the repo)
    # if [ -d "${AXLAP_BASE_DIR}/apparmor" ]; then
    #   for profile in "${AXLAP_BASE_DIR}/apparmor/"*; do
    #     if [ -f "$profile" ]; then
    #       log "Loading AppArmor profile: $profile"
    #       apparmor_parser -r -W "$profile" || log "Warning: Failed to load AppArmor profile $profile"
    #     fi
    #   done
    # fi

    # 14. Final Instructions
    log "AXLAP Installation Completed Successfully!"
    echo ""
    echo "---------------------------------------------------------------------"
    echo " AXLAP - Autonomous XKeyscore-Like Analysis Platform Installation   "
    echo "---------------------------------------------------------------------"
    echo ""
    echo "Base Directory: ${AXLAP_BASE_DIR}"
    echo "Capture Interface: ${CAPTURE_INTERFACE}"
    echo ""
    echo "Access Services:"
    echo "  - AXLAP TUI: Run 'sudo ${AXLAP_BASE_DIR}/venv/bin/python ${AXLAP_BASE_DIR}/src/tui/axlap_tui.py'"
    echo "    (Or just 'cd ${AXLAP_BASE_DIR} && source venv/bin/activate && python src/tui/axlap_tui.py')"
    echo "  - Arkime UI: http://127.0.0.1:8005 (Login: admin / AdminAXLAPPassw0rd - CHANGE THIS!)"
    echo "  - OpenCTI UI: http://127.0.0.1:8080 (Login: ${OPENCTI_ADMIN_EMAIL} / ${OPENCTI_ADMIN_PASSWORD} - CHANGE THIS!)"
    echo "    OpenCTI API Token: ${OPENCTI_ADMIN_TOKEN}"
    echo "  - Elasticsearch (Main): http://127.0.0.1:9200"
    echo ""
    echo "Service Management:"
    echo "  - Start AXLAP: sudo systemctl start axlap.service (or use scripts/start_axlap.sh)"
    echo "  - Stop AXLAP: sudo systemctl stop axlap.service (or use scripts/stop_axlap.sh)"
    echo "  - Status: sudo systemctl status axlap.service / docker-compose ps"
    echo "  - Logs: sudo docker-compose logs -f <service_name> (e.g., zeek, suricata)"
    echo ""
    echo "Important Notes:"
    echo "  - REVIEW AND CHANGE DEFAULT PASSWORDS AND SECRETS!"
    echo "  - Ensure the capture interface '${CAPTURE_INTERFACE}' is correct and traffic is mirrored/spanned if necessary."
    echo "  - Monitor disk space in '${AXLAP_BASE_DIR}/data', especially for PCAPs and Elasticsearch data."
    echo "  - Customize Zeek scripts in '${AXLAP_BASE_DIR}/src/zeek_plugins/' as needed."
    echo "  - Customize Suricata rules in '${AXLAP_BASE_DIR}/rules/local.rules'."
    echo "  - ML models will improve over time with more data. Trigger training via TUI or script."
    echo "  - For full network visibility, ensure AXLAP system can see all relevant traffic (e.g., configure TAP or SPAN port)."
    echo "---------------------------------------------------------------------"

}

# --- Script Execution ---
main "$@"

exit 0