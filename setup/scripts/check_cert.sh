#!/bin/bash
# check_cert.sh — Probe TLS certificates on local services and output JSON.
#
# Uses openssl s_client to check both nginx (:443) and api-server (:8443).
# Outputs one JSON line per service with host, service, cert_type, status,
# days_remaining, expiry_date, and issuer.
#
# Status thresholds:
#   expired  — days_remaining <= 0
#   critical — days_remaining <= 7
#   warning  — days_remaining <= 30
#   valid    — days_remaining > 30
#
# Usage:
#   /usr/local/bin/check_cert.sh
#   CERT_DOMAIN=myhost.example.com /usr/local/bin/check_cert.sh

CERT_DOMAIN="${CERT_DOMAIN:-localhost}"

for ENTRY in "${CERT_DOMAIN}:443:nginx:pem" "${CERT_DOMAIN}:8443:api-server:java_keystore"; do
  HOST=$(echo "$ENTRY" | cut -d: -f1)
  PORT=$(echo "$ENTRY" | cut -d: -f2)
  SVC=$(echo "$ENTRY" | cut -d: -f3)
  CTYPE=$(echo "$ENTRY" | cut -d: -f4)

  ENDDATE=$(echo | openssl s_client -connect "${HOST}:${PORT}" -servername "${HOST}" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)

  if [ -z "$ENDDATE" ]; then
    echo "{\"host\": \"${HOST}\", \"orig_host\": \"${HOST}\", \"cert_cn\": \"${HOST}\", \"service\": \"${SVC}\", \"port\": ${PORT}, \"cert_type\": \"${CTYPE}\", \"status\": \"unreachable\", \"days_remaining\": -999}"
    continue
  fi

  EXPIRY_EPOCH=$(date -d "${ENDDATE}" +%s 2>/dev/null)
  NOW_EPOCH=$(date +%s)
  DAYS_REMAINING=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

  if [ ${DAYS_REMAINING} -le 0 ]; then
    STATUS="expired"
  elif [ ${DAYS_REMAINING} -le 7 ]; then
    STATUS="critical"
  elif [ ${DAYS_REMAINING} -le 30 ]; then
    STATUS="warning"
  else
    STATUS="valid"
  fi

  ISSUER=$(echo | openssl s_client -connect "${HOST}:${PORT}" -servername "${HOST}" 2>/dev/null \
    | openssl x509 -noout -issuer 2>/dev/null | sed 's/issuer=//')

  echo "{\"host\": \"${HOST}\", \"orig_host\": \"${HOST}\", \"cert_cn\": \"${HOST}\", \"service\": \"${SVC}\", \"port\": ${PORT}, \"cert_type\": \"${CTYPE}\", \"status\": \"${STATUS}\", \"days_remaining\": ${DAYS_REMAINING}, \"expiry_date\": \"${ENDDATE}\", \"issuer\": \"${ISSUER}\"}"
done
