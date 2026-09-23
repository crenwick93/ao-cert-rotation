#!/usr/bin/env bash
set -eo pipefail
# Expire the nginx PEM cert (5 days remaining) to trigger the Splunk alert.
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ansible-playbook -i setup/playbooks/inventory/hosts.yml \
  setup/playbooks/generate_expired_cert.yml \
  --tags pem
