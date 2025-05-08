#!/bin/bash
    # Checks status of AXLAP services

    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    source "${SCRIPT_DIR}/axlap_common_env.sh"

    echo "AXLAP Service Status:"
    cd "${AXLAP_BASE_DIR}"
    docker-compose -f "${DOCKER_COMPOSE_FILE}" ps
    echo ""
    echo "Key Endpoints (if services are up):"
    echo "  AXLAP TUI: Python script (run manually)"
    echo "  Arkime UI: http://127.0.0.1:8005"
    echo "  OpenCTI UI: http://127.0.0.1:8080"
    echo "  Elasticsearch: http://127.0.0.1:9200"