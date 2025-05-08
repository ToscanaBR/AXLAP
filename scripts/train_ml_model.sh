#!/bin/bash
    # Triggers ML model training within the ml_engine container.

    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    source "${SCRIPT_DIR}/axlap_common_env.sh"
    LOG_FILE="${AXLAP_BASE_DIR}/logs/ml_train.log"

    echo "[$(date)] Starting ML model training..." | tee -a "${LOG_FILE}"
    cd "${AXLAP_BASE_DIR}"

    # Ensure ML engine container has necessary environment variables set in docker-compose.yml
    # (e.g., ELASTICSEARCH_HOST)
    docker-compose -f "${DOCKER_COMPOSE_FILE}" run --rm ml_engine python ml_engine/train.py >> "${LOG_FILE}" 2>&1

    if [ $? -eq 0 ]; then
      echo "ML model training script completed successfully." | tee -a "${LOG_FILE}"
    else
      echo "ERROR: ML model training script failed. Check ${LOG_FILE} for details." | tee -a "${LOG_FILE}"
      exit 1
    fi

    echo "[$(date)] ML model training finished." | tee -a "${LOG_FILE}"