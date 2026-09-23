#!/usr/bin/env bash
set -eo pipefail

# Simulate a Splunk cert expiry alert via the EDA event stream.
# Authenticates with AO, then posts to the EDA trigger endpoint.
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

if [[ -z "${AO_WEBHOOK_BASE_URL:-}" || -z "${AO_WEBHOOK_PATH:-}" || -z "${AO_WEBHOOK_CLIENT_ID:-}" || -z "${AO_WEBHOOK_CLIENT_SECRET:-}" ]]; then
  echo "ERROR: AO webhook credentials not set in .env"
  echo "Required: AO_WEBHOOK_BASE_URL, AO_WEBHOOK_PATH, AO_WEBHOOK_CLIENT_ID, AO_WEBHOOK_CLIENT_SECRET"
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
  "host": "'"${CERT_DOMAIN}"'",
  "service": "'"${SERVICE}"'",
  "cert_type": "'"${CERT_TYPE}"'",
  "port": '"${PORT}"',
  "status": "critical",
  "days_remaining": 5,
  "expiry_date": "'"${TIMESTAMP}"'",
  "issuer": "Demo Certificate Authority"
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
echo "  Target:   AO EDA Trigger"
echo "------------------------------------------------------------"
echo ""

# Step 1: Get OAuth token
echo "  Authenticating with AO..."
TOKEN=$(curl -sS -k -X POST "${AO_WEBHOOK_BASE_URL}/api/v1/auth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=${AO_WEBHOOK_CLIENT_ID}&client_secret=${AO_WEBHOOK_CLIENT_SECRET}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Step 2: Post to AO EDA trigger
echo "  Sending event to AO..."
echo ""

HTTP_CODE=$(curl -sS -k -o /tmp/ao-response.txt -w "%{http_code}" -X POST "${AO_WEBHOOK_BASE_URL}/api/v1/webhooks/eda/${AO_WEBHOOK_PATH}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}")

BODY=$(cat /tmp/ao-response.txt 2>/dev/null)

if [[ "${HTTP_CODE}" == "200" || "${HTTP_CODE}" == "202" ]]; then
  echo "  Event accepted (HTTP ${HTTP_CODE})"
  echo ""
  echo "============================================================"
  echo "  AO workflow triggered:"
  echo "    1. Switch → ${CERT_TYPE} path"
  echo "    2. Standard Change → Renew → Validate → Close"
  echo ""
  echo "  Monitor progress:"
  echo "    AAP:  ${AAP_HOSTNAME:-https://your-aap} > Jobs"
  echo "    AO:   Check workflow executions"
  echo "    SNOW: Check for new change request"
  echo "============================================================"
else
  echo "  ERROR: Event rejected (HTTP ${HTTP_CODE})"
  echo "  Response: ${BODY}"
  exit 1
fi
