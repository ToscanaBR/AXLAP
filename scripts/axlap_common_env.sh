 #!/bin/bash
    # Common environment variables for AXLAP scripts
    # This can be sourced by other scripts or used by systemd EnvironmentFile.

    export AXLAP_BASE_DIR="/opt/axlap"
    export DOCKER_COMPOSE_FILE="${AXLAP_BASE_DIR}/docker-compose.yml"
    # export CAPTURE_INTERFACE="eth0" # Set during install, or read from a persistent config
    # export HOME_NETS="..."

    # Load .env file if it exists for docker-compose variables
    if [ -f "${AXLAP_BASE_DIR}/.env" ]; then
      export $(cat "${AXLAP_BASE_DIR}/.env" | sed 's/#.*//g' | xargs)
    fi