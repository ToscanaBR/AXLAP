#!/bin/bash
    # Starts AXLAP services using Docker Compose

    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    source "${SCRIPT_DIR}/axlap_common_env.sh"

    echo "Starting AXLAP services from ${DOCKER_COMPOSE_FILE}..."
    cd "${AXLAP_BASE_DIR}" # Ensure docker-compose runs from the correct directory

    # Make sure .env file is loaded if it has critical vars for compose file itself
    # docker-compose --env-file .env -f "${DOCKER_COMPOSE_FILE}" up -d
    docker-compose -f "${DOCKER_COMPOSE_FILE}" up -d

    if [ $? -eq 0 ]; then
      echo "AXLAP services started successfully."
      echo "Run 'docker-compose ps' to check status."
    else
      echo "ERROR: Failed to start AXLAP services."
      exit 1
    fi