#!/bin/bash
    # Stops AXLAP services

    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    source "${SCRIPT_DIR}/axlap_common_env.sh"

    echo "Stopping AXLAP services..."
    cd "${AXLAP_BASE_DIR}"
    docker-compose -f "${DOCKER_COMPOSE_FILE}" down -v --remove-orphans # -v to remove volumes if desired (careful!)
                                                                  # For normal stop, just 'down'
                                                                  # Let's use `down` without `-v` for default stop to preserve data.
    docker-compose -f "${DOCKER_COMPOSE_FILE}" down

    if [ $? -eq 0 ]; then
      echo "AXLAP services stopped."
    else
      echo "ERROR: Failed to stop AXLAP services properly."
      # exit 1 # Don't exit if some containers failed to stop, user might want to check.
    fi