#!/bin/bash
# Arkime Configuration Helper (Example)

    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    source "${SCRIPT_DIR}/axlap_common_env.sh"
    LOG_FILE="${AXLAP_BASE_DIR}/logs/arkime_config.log"

    echo "[$(date)] Arkime configuration script started." | tee -a "${LOG_FILE}"
    cd "${AXLAP_BASE_DIR}"

    # This is largely handled by install.sh now.
    # Could be used for re-initialization or adding more users.

    # Example: Add another Arkime user
    # read -p "Enter username for new Arkime user: " arkime_user
    # read -s -p "Enter password for ${arkime_user}: " arkime_pass
    # echo
    # docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T arkime-viewer /opt/arkime/bin/arkime_add_user.sh "${arkime_user}" "New User" "${arkime_pass}" >> "${LOG_FILE}" 2>&1
    # if [ $? -eq 0 ]; then
    #   echo "Successfully added Arkime user ${arkime_user}." | tee -a "${LOG_FILE}"
    # else
    #   echo "Failed to add Arkime user ${arkime_user}." | tee -a "${LOG_FILE}"
    # fi

echo "[$(date)] Arkime configuration script finished." | tee -a "${LOG_FILE}"