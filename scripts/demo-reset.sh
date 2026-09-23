#!/usr/bin/env bash
set -eo pipefail

# Reset the demo to a clean, working state:
# - Renew both certs to 90 days (no alerts)
# - Clear Splunk triggered alerts
# - Clear all ServiceNow CRs and incidents
#
# Run this BEFORE the demo to ensure a clean starting point.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
KEY="${REPO_ROOT}/setup/terraform/demo-key.pem"
INVENTORY="${REPO_ROOT}/setup/playbooks/inventory/hosts.yml"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  source "${REPO_ROOT}/.env"
  set +a
fi

HOST_IP="${DEMO_HOST_IP:-63.32.42.56}"
SPLUNK_ADMIN_PASSWORD="${SPLUNK_PASSWORD:-changeme123}"

echo "============================================================"
echo "  DEMO RESET — Restoring Clean State"
echo "============================================================"
echo ""

# 1. Renew both certs to full 90-day validity using the actual renewal playbooks
echo "  [1/4] Renewing both certificates to 90 days..."
ansible-playbook -i "${INVENTORY}" "${REPO_ROOT}/playbooks/renew_certificate.yml" \
  -e "cert_domain=certdemo.demoredhat.com" 2>/dev/null | tail -3
ansible-playbook -i "${INVENTORY}" "${REPO_ROOT}/playbooks/renew_keystore_certificate.yml" \
  -e "cert_domain=certdemo.demoredhat.com" 2>/dev/null | tail -3
echo "  Both certs renewed (~90 days)"
echo ""

# 2. Reset Splunk: clean index + recreate alert from scratch
echo "  [2/4] Resetting Splunk..."
SPLUNK_AUTH="admin:${SPLUNK_ADMIN_PASSWORD}"
ssh -i "${KEY}" -o StrictHostKeyChecking=no ec2-user@${HOST_IP} "
  # Delete existing alert
  sudo curl -sk -X DELETE \
    'https://localhost:8089/servicesNS/admin/search/saved/searches/Certificate%20Expiry%20Alert' \
    -u '${SPLUNK_AUTH}' -o /dev/null 2>/dev/null

  # Stop Splunk, clean index, restart (must stop first — clean as root fails)
  sudo podman exec -u splunk splunk /opt/splunk/bin/splunk stop  >/dev/null 2>&1
  sudo podman exec -u splunk splunk /opt/splunk/bin/splunk clean eventdata -index main -f >/dev/null 2>&1
  sudo podman exec -u splunk splunk /opt/splunk/bin/splunk start >/dev/null 2>&1

  # Wait for Splunk REST to be ready
  for i in \$(seq 1 30); do
    sudo curl -sk -o /dev/null -w '%{http_code}' \
      'https://localhost:8089/services/server/info' -u '${SPLUNK_AUTH}' 2>/dev/null | grep -q 200 && break
    sleep 2
  done

  # Recreate alert
  sudo curl -sk -X POST 'https://localhost:8089/servicesNS/admin/search/saved/searches' -u '${SPLUNK_AUTH}' \
    -d 'name=Certificate Expiry Alert' \
    -d 'search=index=main sourcetype=cert_monitor days_remaining<=7 earliest=-10m | head 1' \
    -d 'is_scheduled=1&cron_schedule=* * * * *' \
    -d 'alert_type=number of events&alert_comparator=greater than&alert_threshold=0' \
    -d 'actions=webhook&action.webhook.param.url=https://webhook.site/test' \
    -d 'alert.track=1&alert.suppress=1&alert.suppress.period=5m&alert.suppress.fields=service' \
    -d 'dispatch.earliest_time=-10m&dispatch.latest_time=now' -o /dev/null 2>/dev/null
" 2>/dev/null
echo "  Splunk reset (index cleaned, alert recreated)"
echo ""

# 3. Clear ServiceNow CRs
echo "  [3/4] Clearing ServiceNow change requests..."
curl -sk "${SERVICENOW_INSTANCE_URL}/api/now/table/change_request?sysparm_fields=sys_id&sysparm_limit=200" \
  -u "${SERVICENOW_USERNAME}:${SERVICENOW_PASSWORD}" \
  -H "Accept: application/json" | python3 -c "
import sys,json
for r in json.load(sys.stdin).get('result',[]): print(r['sys_id'])
" 2>/dev/null | while read SID; do
  curl -sk -X DELETE "${SERVICENOW_INSTANCE_URL}/api/now/table/change_request/${SID}" \
    -u "${SERVICENOW_USERNAME}:${SERVICENOW_PASSWORD}" -o /dev/null
done
echo "  Change requests cleared"
echo ""

# 4. Clear ServiceNow incidents
echo "  [4/4] Clearing ServiceNow incidents..."
curl -sk "${SERVICENOW_INSTANCE_URL}/api/now/table/incident?sysparm_fields=sys_id&sysparm_limit=200" \
  -u "${SERVICENOW_USERNAME}:${SERVICENOW_PASSWORD}" \
  -H "Accept: application/json" | python3 -c "
import sys,json
for r in json.load(sys.stdin).get('result',[]): print(r['sys_id'])
" 2>/dev/null | while read SID; do
  curl -sk -X DELETE "${SERVICENOW_INSTANCE_URL}/api/now/table/incident/${SID}" \
    -u "${SERVICENOW_USERNAME}:${SERVICENOW_PASSWORD}" -o /dev/null
done
echo "  Incidents cleared"
echo ""

echo "============================================================"
echo "  DEMO RESET COMPLETE"
echo "============================================================"
echo ""
echo "  Both certs: ~90 days remaining (no alerts)"
echo "  Splunk: alert reset, no triggered alerts"
echo "  ServiceNow: clean (no CRs or incidents)"
echo ""
echo "  Ready to start demo:"
echo "    ./scripts/expire-pem.sh          # Expire nginx cert"
echo "    ./scripts/expire-keystore.sh     # Expire Tomcat cert"
echo "    ./scripts/test-trigger.sh        # Fire PEM workflow"
echo "    ./scripts/test-trigger.sh keystore  # Fire keystore workflow"
echo "============================================================"
