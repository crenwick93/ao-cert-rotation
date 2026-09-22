#!/usr/bin/env bash
set -eo pipefail

# Fire a test cert expiry event to the AO workflow trigger endpoint.
# Simulates a Splunk alert for a certificate with 5 days remaining.
#
# Usage:
#   ./scripts/test-trigger.sh
#   ./scripts/test-trigger.sh '{"host":"certdemo.demoredhat.com","service":"api-server","cert_type":"java_keystore","port":8443,"status":"critical","days_remaining":5}'
#
# Prerequisites:
#   .env must have AO_WEBHOOK_BASE_URL, AO_WEBHOOK_PATH,
#   AO_WEBHOOK_CLIENT_ID, and AO_WEBHOOK_CLIENT_SECRET set.

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

PAYLOAD="${1:-{\"host\":\"${CERT_DOMAIN}\",\"service\":\"nginx\",\"cert_type\":\"pem\",\"port\":443,\"status\":\"critical\",\"days_remaining\":5,\"expiry_date\":\"$(date -d '+5 days' '+%b %d %H:%M:%S %Y GMT' 2>/dev/null || date -v+5d '+%b %d %H:%M:%S %Y GMT')\",\"issuer\":\"Demo Certificate Authority\"}}"

echo "Authenticating with AO..."
TOKEN=$(curl -sk -X POST "${AO_WEBHOOK_BASE_URL}/api/v1/auth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=${AO_WEBHOOK_CLIENT_ID}&client_secret=${AO_WEBHOOK_CLIENT_SECRET}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo "Posting test cert alert to ${AO_WEBHOOK_BASE_URL}/api/v1/webhooks/eda/${AO_WEBHOOK_PATH}..."
echo "Payload: ${PAYLOAD}" | python3 -m json.tool 2>/dev/null || echo "Payload: ${PAYLOAD}"
echo ""

RESPONSE=$(curl -sk -X POST "${AO_WEBHOOK_BASE_URL}/api/v1/webhooks/eda/${AO_WEBHOOK_PATH}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}" \
  -w "\n%{http_code}")

HTTP_CODE=$(echo "${RESPONSE}" | tail -1)
BODY=$(echo "${RESPONSE}" | head -n -1)

if [[ "${HTTP_CODE}" == "202" ]]; then
  echo "✅ Cert rotation workflow triggered successfully"
  echo "${BODY}" | python3 -m json.tool 2>/dev/null || echo "${BODY}"
else
  echo "❌ Failed (HTTP ${HTTP_CODE})"
  echo "${BODY}"
  exit 1
fi
