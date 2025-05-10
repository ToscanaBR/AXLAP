#!/bin/bash
# Checks status of AXLAP services

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/axlap_common_env.sh"

echo "AXLAP Service Status:"
cd "${AXLAP_BASE_DIR}" || exit 1  # Exit if changing directory fails
docker-compose -f "${DOCKER_COMPOSE_FILE}" ps

if [ $? -ne 0 ]; then
  echo "Error: Could not retrieve service status. Check Docker Compose configuration."
  exit 1
fi

echo ""
echo "Key Endpoints (if services are up):"
echo "  AXLAP TUI: Python script (run manually)"
echo "  Arkime UI: http://127.0.0.1:8005"
echo "  OpenCTI UI: http://127.0.0.1:8080"
echo "  Elasticsearch: http://127.0.0.1:9200"