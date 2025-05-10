#!/bin/bash
# Updates Suricata rules and threat feeds for OpenCTI/MISP

    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    source "${SCRIPT_DIR}/axlap_common_env.sh"
    LOG_FILE="${AXLAP_BASE_DIR}/logs/updates.log"

    echo "[$(date)] Starting AXLAP rules and feeds update..." | tee -a "${LOG_FILE}"

    # 1. Update Suricata Rules
    echo "Updating Suricata rules..." | tee -a "${LOG_FILE}"
    # The Suricata container's entrypoint script handles the update.
    # We can trigger it or exec into the container.
    # To re-run the update part of the entrypoint, it's complex.
    # Simpler: `docker-compose exec suricata suricata-update ...`
    # The entrypoint in the suricata Dockerfile already does suricata-update on start.
    # For a periodic update, we'd typically run `suricata-update` and then SIGHUP suricata.
    # Assuming suricata container has `suricata-update` in PATH and correct config.
    # Note: suricata-update downloads to /var/lib/suricata/rules by default, but uses /etc/suricata/rules in config.
    # The --suricata-conf /tmp/suricata.yaml is likely incorrect. It should point to the actual config.
    # The --no-reload prevents the rules from being loaded, so SIGHUP is still needed.
    if docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T axlap-suricata suricata-update; then
        echo "Suricata rules updated. Reloading Suricata..." | tee -a "${LOG_FILE}"
        # Send SIGHUP to Suricata process to reload rules. Find PID or use killall.
        # This depends on how Suricata is run in the container.
        # If Suricata is PID 1, `docker kill -s HUP axlap-suricata` might work.
        # Or, `docker-compose exec axlap-suricata kill -HUP $(pidof suricata)`
        # The PID file might not always be present.
        docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T axlap-suricata pkill -HUP suricata >> "${LOG_FILE}" 2>&1
        echo "Suricata reload signal sent." | tee -a "${LOG_FILE}"
    else
        echo "ERROR: Suricata rule update failed." | tee -a "${LOG_FILE}"
    fi

    # 2. Update OpenCTI Feeds
    # This is managed by OpenCTI connectors. They have polling intervals.
    # To force a connector run, you'd typically use OpenCTI's API or UI.
    # For now, we assume connectors are configured to poll periodically.
    # Example: Trigger MISP connector (if it has a "run now" capability via API)
    # This requires knowing the connector ID and using OpenCTI's GraphQL API.
    echo "OpenCTI connectors update feeds based on their own schedules.  Manual triggering requires OpenCTI API calls." | tee -a "${LOG_FILE}"
    # Potentially, one could script API calls to OpenCTI to trigger specific connectors if needed.
    # For instance, find connector by name, then trigger a "reset" or "run" if API allows.
    # Example (conceptual, requires jq and knowing your OPENCTI_TOKEN):
    # OPENCTI_URL_INTERNAL="http://localhost:8080" # Replace with your internal OpenCTI URL if different
    # if [ -n "${OPENCTI_ADMIN_TOKEN}" ]; then
    #   MISP_CONNECTOR_ID=$(curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer ${OPENCTI_ADMIN_TOKEN}" \
    #     ${OPENCTI_URL_INTERNAL}/graphql --data '{"query":"query { connectors { edges { node { id name } } } }"}' | jq -r '.data.connectors.edges[] | select(.node.name=="MISP").node.id')
    #   if [ -n "$MISP_CONNECTOR_ID" ] && [ "$MISP_CONNECTOR_ID" != "null" ]; then
    #     curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer ${OPENCTI_ADMIN_TOKEN}" \
    #       ${OPENCTI_URL_INTERNAL}/graphql --data "{\"query\":\"mutation ConnectorRun(\$id: ID!) { connectorRun(id: \$id) { id } }\", \"variables\":{\"id\":\"${MISP_CONNECTOR_ID}\"}}"
    #     echo "Sent run signal to MISP connector ID ${MISP_CONNECTOR_ID}" | tee -a "${LOG_FILE}"
    #   else
    #     echo "Could not find MISP connector ID to trigger or OPENCTI_ADMIN_TOKEN not set." | tee -a "${LOG_FILE}"
    #   fi
    # else
    #   echo "OPENCTI_ADMIN_TOKEN not set. Cannot trigger OpenCTI connector." | tee -a "${LOG_FILE}"
    # fi

    # 3. Update Zeek Intel Files (if using Intel::read_files)
    # This would involve downloading fresh IOC lists (IPs, domains, etc.)
    # and placing them in /opt/axlap/threat_intel/ for Zeek to pick up.
    # Then, `zeekctl deploy` or a signal to Zeek to reload intel.
    echo "Updating Zeek threat intelligence files (example)..." | tee -a "${LOG_FILE}"
    # Example: Download a blocklist (replace with actual feed URLs)
    # curl -s https://example.com/bad_ips.txt > "${AXLAP_BASE_DIR}/config/zeek/intel/ips.dat.tmp"
    # if [ -s "${AXLAP_BASE_DIR}/config/zeek/intel/ips.dat.tmp" ]; then
    #   mv "${AXLAP_BASE_DIR}/config/zeek/intel/ips.dat.tmp" "${AXLAP_BASE_DIR}/config/zeek/intel/ips.dat"
    #   echo "Updated ips.dat for Zeek." | tee -a "${LOG_FILE}"
    #   # Reload Zeek intel (this is complex, might need `zeekctl deploy` or specific script)
    #   # docker-compose exec axlap-zeek zeekctl deploy # Might restart all of Zeek
    #   # A less disruptive way is needed if Zeek supports dynamic intel updates.
    #   # For now, a full deploy:
    #   # docker-compose exec -T axlap-zeek /usr/local/zeek/bin/zeekctl check >> "${LOG_FILE}" 2>&1
    #   # docker-compose exec -T axlap-zeek /usr/local/zeek/bin/zeekctl deploy >> "${LOG_FILE}" 2>&1
    #   echo "Zeek intel updated. A 'zeekctl deploy' might be needed for changes to take full effect." | tee -a "${LOG_FILE}"
    # else
    #   rm -f "${AXLAP_BASE_DIR}/config/zeek/intel/ips.dat.tmp"
    #   echo "Failed to download new ips.dat for Zeek." | tee -a "${LOG_FILE}"
    # fi

echo "[$(date)] AXLAP update process finished." | tee -a "${LOG_FILE}"