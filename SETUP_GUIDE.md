# Cert Rotation Demo — Full Setup Guide

## Infrastructure Required

| Component | Purpose | How to Provision |
|---|---|---|
| AAP 2.5+ with AO | Controller + EDA + Automation Orchestrator | Your AAP environment |
| Demo VM | nginx + Tomcat + Vault + Splunk | EC2 t3.small via Terraform |
| ServiceNow | Incident/CR lifecycle | PDI or production instance |
| LiteLLM | AI proxy for AO agentic nodes | Container on bastion |

## Step-by-Step Setup

### 1. Configure Environment

```bash
cp .env.example .env
# Fill in all required values — see comments in .env.example
```

### 2. Build Container Images

```bash
# Login to Red Hat registry first
podman login registry.redhat.io

# Build Decision Environment (for EDA CR polling) and Execution Environment
./dependencies/build-images.sh --push
```

### 3. Provision Demo VM (Terraform)

```bash
cd setup/terraform
terraform init
terraform apply
cd ../..

# Terraform outputs the VM IP and updates .env with DEMO_HOST_IP
```

### 4. Setup Demo Host

This runs all three provisioning playbooks in sequence:

```bash
./setup/scripts/setup-apply.sh
```

Or run them individually:

```bash
INVENTORY=setup/playbooks/inventory/hosts.yml

# Phase 1: nginx + Vault
ansible-playbook -i $INVENTORY setup/playbooks/provision_vm.yml

# Phase 2: Tomcat + Java keystore
ansible-playbook -i $INVENTORY setup/playbooks/provision_tomcat.yml

# Phase 3: Splunk + cert monitoring
ansible-playbook -i $INVENTORY setup/playbooks/provision_splunk.yml \
  -e ao_webhook_url='http://<AO_HOST>:8080/api/v1/webhooks/splunk-cert-alert'
```

After Splunk provisioning, copy the HEC token from the output to `.env`:
```
SPLUNK_HEC_TOKEN=<token from output>
```

### 5. Trust the Vault CA (Optional — for browser demo)

```bash
# Download CA cert from Vault
curl -s http://<VM_IP>:8200/v1/pki/ca/pem > /tmp/vault-ca.pem

# Trust it (macOS)
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain /tmp/vault-ca.pem
```

### 6. Setup LiteLLM (AI Proxy)

Run on your bastion or any host reachable by AO:

```bash
cat > /tmp/litellm_config.yaml << EOF
model_list:
  - model_name: claude-sonnet-4-6
    litellm_params:
      model: anthropic/claude-sonnet-4-6-20250514
      api_key: YOUR_ANTHROPIC_KEY
general_settings:
  master_key: sk-demo-key
EOF

podman run -d --name litellm --restart always \
  -p 4000:4000 \
  -v /tmp/litellm_config.yaml:/app/config.yaml:ro \
  ghcr.io/berriai/litellm:main-latest \
  --config /app/config.yaml --port 4000
```

### 7. Apply AAP Configuration as Code

```bash
# Install collections if not already present
ansible-galaxy collection install -r ansible_deployment/cac/requirements.yml

# Apply CaC (first pass — creates objects with placeholder creds)
./ansible_deployment/scripts/cac-apply.sh
```

### 8. Configure AO

1. **Create AI credential** in AO: base_url=`http://<bastion>:4000/v1`, api_key=`sk-demo-key`, model=`claude-sonnet-4-6`
2. **Create AAP credential** in AO: host=`https://<aap-host>`, token from AAP
3. **Import workflow JSON**: Use `ao/cert-demo-webhook.json` (or `cert-demo-manual.json` for live demos)
4. **Configure agentic node**: Select the AI credential and enable AAP MCP tools
5. **Publish the workflow**
6. **Update `.env`** with the AO webhook credentials from the published workflow
7. **Re-run CaC**: `./ansible_deployment/scripts/cac-apply.sh`

### 9. Configure Splunk Webhook Alert

If not already configured by the provisioning playbook, set the webhook URL in Splunk:

1. Splunk UI → Settings → Searches, Reports, and Alerts
2. Edit "Certificate Expiry Alert"
3. Set webhook URL to: `http://<AO_HOST>:8080/api/v1/webhooks/splunk-cert-alert`

### 10. Demo Reset (Generate Near-Expiry Certs)

```bash
ansible-playbook -i setup/playbooks/inventory/hosts.yml \
  setup/playbooks/generate_expired_cert.yml
```

This creates certs with ~5 days remaining, triggering the Splunk alert within minutes.

## Verification

```bash
# Check nginx cert (should show ~5 days remaining after reset)
echo | openssl s_client -connect <CERT_DOMAIN>:443 2>/dev/null | openssl x509 -noout -dates

# Check API server cert
echo | openssl s_client -connect <CERT_DOMAIN>:8443 2>/dev/null | openssl x509 -noout -dates

# After AO workflow runs: both should show ~90 days remaining
```

## Test the Trigger Manually

```bash
# Fire a test cert alert to verify the pipeline end-to-end
./scripts/test-trigger.sh
```
