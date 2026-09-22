#!/bin/bash
# push_cert_to_splunk.sh — Run cert checks and push results to Splunk HEC.
#
# Reads SPLUNK_HEC_TOKEN and CERT_DOMAIN from environment or /etc/sysconfig/cert-monitor.
# Designed to run via cron every minute.
#
# Usage:
#   /usr/local/bin/push_cert_to_splunk.sh
#   SPLUNK_HEC_TOKEN=xxx CERT_DOMAIN=myhost.example.com /usr/local/bin/push_cert_to_splunk.sh

SPLUNK_HEC_URL="${SPLUNK_HEC_URL:-https://localhost:8088}"
SPLUNK_HEC_TOKEN="${SPLUNK_HEC_TOKEN:-}"
CERT_DOMAIN="${CERT_DOMAIN:-localhost}"

if [ -z "${SPLUNK_HEC_TOKEN}" ]; then
  echo "ERROR: SPLUNK_HEC_TOKEN not set" >&2
  exit 1
fi

export CERT_DOMAIN

/usr/local/bin/check_cert.sh | while read -r RESULT; do
  curl -sk "${SPLUNK_HEC_URL}/services/collector/event" \
    -H "Authorization: Splunk ${SPLUNK_HEC_TOKEN}" \
    -d "{\"event\": ${RESULT}, \"sourcetype\": \"cert_monitor\", \"index\": \"main\"}" \
    > /dev/null 2>&1
done
