#!/usr/bin/env bash
set -eo pipefail

# Fire a test cert expiry event to the EDA webhook listener.
# Simulates a Splunk alert for a certificate with 5 days remaining.
#
# Usage:
#   ./scripts/test-trigger.sh
#   ./scripts/test-trigger.sh '{"host":"certdemo.demoredhat.com","service":"api-server","cert_type":"java_keystore","port":8443,"status":"critical","days_remaining":5}'
#
# Prerequisites:
#   EDA_WEBHOOK_URL must be set in .env (the EDA controller webhook endpoint)
#   OR pass it as an environment variable.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

# EDA webhook URL — the EDA controller endpoint for the webhook source
# This is the EDA activation's webhook listener, NOT the AO endpoint
EDA_WEBHOOK_URL="${EDA_WEBHOOK_URL:-}"

if [[ -z "${EDA_WEBHOOK_URL}" ]]; then
  echo "ERROR: EDA_WEBHOOK_URL not set in .env"
  echo "Set it to the EDA webhook listener URL, e.g.:"
  echo "  EDA_WEBHOOK_URL=https://<aap-host>/api/eda/v1/external_webhook/<activation-id>/"
  echo ""
  echo "Find it in AAP → EDA → Rulebook Activations → cert-rotation-cr-bridge → Webhook URL"
  exit 1
fi

CERT_DOMAIN="${CERT_DOMAIN:-certdemo.demoredhat.com}"

PAYLOAD="${1:-{\"host\":\"${CERT_DOMAIN}\",\"service\":\"nginx\",\"cert_type\":\"pem\",\"port\":443,\"status\":\"critical\",\"days_remaining\":5,\"expiry_date\":\"$(date -v+5d '+%b %d %H:%M:%S %Y GMT' 2>/dev/null || date -d '+5 days' '+%b %d %H:%M:%S %Y GMT' 2>/dev/null)\",\"issuer\":\"Demo Certificate Authority\"}}"

echo "Posting cert alert to EDA webhook: ${EDA_WEBHOOK_URL}"
echo "Payload:"
echo "${PAYLOAD}" | python3 -m json.tool 2>/dev/null || echo "${PAYLOAD}"
echo ""

RESPONSE=$(curl -sk -X POST "${EDA_WEBHOOK_URL}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${EDA_EVENT_STREAM_TOKEN}" \
  -d "${PAYLOAD}" \
  -w "\nHTTP_CODE:%{http_code}")

HTTP_CODE=$(echo "${RESPONSE}" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')
BODY=$(echo "${RESPONSE}" | grep -v "HTTP_CODE:")

if [[ "${HTTP_CODE}" == "200" || "${HTTP_CODE}" == "202" ]]; then
  echo "✅ Cert alert sent to EDA successfully (HTTP ${HTTP_CODE})"
  echo "${BODY}"
else
  echo "❌ Failed (HTTP ${HTTP_CODE})"
  echo "${BODY}"
  exit 1
fi
