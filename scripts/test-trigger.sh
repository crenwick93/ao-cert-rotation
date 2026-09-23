#!/usr/bin/env bash
set -eo pipefail

# Simulate a Splunk cert expiry alert via the EDA event stream.
# Posts to the EDA event stream webhook, which the rulebook matches
# and forwards to AO to trigger the cert rotation workflow.
#
# Usage:
#   ./scripts/test-trigger.sh                    # PEM cert (nginx)
#   ./scripts/test-trigger.sh keystore           # Java keystore (Tomcat)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

if [[ -z "${EDA_WEBHOOK_URL:-}" || -z "${EDA_EVENT_STREAM_TOKEN:-}" ]]; then
  echo "ERROR: EDA event stream credentials not set in .env"
  echo "Required: EDA_WEBHOOK_URL, EDA_EVENT_STREAM_TOKEN"
  exit 1
fi

CERT_DOMAIN="${CERT_DOMAIN:-certdemo.demoredhat.com}"
CERT_TYPE="${1:-pem}"

if [[ "${CERT_TYPE}" == "keystore" || "${CERT_TYPE}" == "java_keystore" ]]; then
  SERVICE="api-server"
  CERT_TYPE="java_keystore"
  PORT=8443
else
  SERVICE="nginx"
  CERT_TYPE="pem"
  PORT=443
fi

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)

# Wrap in {"payload": {...}} — EDA event streams deliver as event.payload.payload
PAYLOAD='{
  "payload": {
    "host": "'"${CERT_DOMAIN}"'",
    "service": "'"${SERVICE}"'",
    "cert_type": "'"${CERT_TYPE}"'",
    "port": '"${PORT}"',
    "status": "critical",
    "days_remaining": 5,
    "expiry_date": "'"${TIMESTAMP}"'",
    "issuer": "Demo Certificate Authority"
  }
}'

echo "============================================================"
echo "  SIMULATED SPLUNK CERT EXPIRY ALERT"
echo "============================================================"
echo ""
echo "  Host:     ${CERT_DOMAIN}"
echo "  Service:  ${SERVICE}"
echo "  Port:     ${PORT}"
echo "  Cert:     ${CERT_TYPE}"
echo "  Days:     5"
echo ""
echo "  Target:   EDA Event Stream → Rulebook → AO Workflow"
echo "------------------------------------------------------------"
echo ""

echo "  Sending event to EDA event stream..."
echo ""

HTTP_CODE=$(curl -sS -k -o /tmp/eda-response.txt -w "%{http_code}" -X POST "${EDA_WEBHOOK_URL}" \
  -H "Authorization: ${EDA_EVENT_STREAM_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}")

BODY=$(cat /tmp/eda-response.txt 2>/dev/null)

if [[ "${HTTP_CODE}" == "200" || "${HTTP_CODE}" == "202" ]]; then
  echo "  Event accepted by EDA (HTTP ${HTTP_CODE})"
  echo ""
  echo "============================================================"
  echo "  EDA will match the rulebook and trigger AO:"
  echo "    1. Rulebook matches cert_type=${CERT_TYPE}"
  echo "    2. AO workflow triggers → ${CERT_TYPE} path"
  echo "    3. Standard Change → Renew → Validate → Close"
  echo ""
  echo "  Monitor progress:"
  echo "    EDA:  Check rulebook activation history"
  echo "    AAP:  ${AAP_HOSTNAME:-https://your-aap} > Jobs"
  echo "    AO:   Check workflow executions"
  echo "    SNOW: Check for new change request"
  echo "============================================================"
else
  echo "  ERROR: Event rejected (HTTP ${HTTP_CODE})"
  echo "  Response: ${BODY}"
  exit 1
fi
