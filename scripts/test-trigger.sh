#!/usr/bin/env bash
set -eo pipefail

# Simulate a Splunk cert expiry alert to the EDA event stream.
#
# Payload must be wrapped in {"payload": {...}} to match the event stream format.
# Auth header uses the token directly (no "Bearer" prefix).
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

if [[ -z "${EDA_WEBHOOK_URL:-}" ]]; then
  echo "ERROR: EDA_WEBHOOK_URL not set in .env"
  exit 1
fi
if [[ -z "${EDA_EVENT_STREAM_TOKEN:-}" ]]; then
  echo "ERROR: EDA_EVENT_STREAM_TOKEN not set in .env"
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
echo "  Target:   EDA Event Stream"
echo "------------------------------------------------------------"
echo ""
echo "  Sending event to EDA..."
echo ""

HTTP_CODE=$(curl -sS -k -o /tmp/eda-response.txt -w "%{http_code}" -X POST "${EDA_WEBHOOK_URL}" \
  -H "Authorization: ${EDA_EVENT_STREAM_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}")

BODY=$(cat /tmp/eda-response.txt 2>/dev/null)

if [[ "${HTTP_CODE}" == "200" || "${HTTP_CODE}" == "202" ]]; then
  echo "  Event accepted (HTTP ${HTTP_CODE})"
  echo ""
  echo "============================================================"
  echo "  EDA rulebook will now trigger:"
  echo "    1. Bridge: AO Workflow Bridge"
  echo "    2. AO: Switch → ${CERT_TYPE} path"
  echo "    3. AAP: Standard Change → Renew → Validate → Close"
  echo ""
  echo "  Monitor progress:"
  echo "    AAP Jobs:  ${AAP_HOSTNAME:-https://your-aap} > Jobs"
  echo "    AO:        Check workflow executions"
  echo "    SNOW:      Check for new change request"
  echo "============================================================"
else
  echo "  ERROR: Event rejected (HTTP ${HTTP_CODE})"
  echo "  Response: ${BODY}"
  exit 1
fi
