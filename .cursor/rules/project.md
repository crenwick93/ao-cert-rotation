# Intelligent Cert Rotation — Project Rules

## What This Project Is

An AO (Automation Orchestrator) demo for intelligent certificate rotation. Splunk detects near-expiry certs, ServiceNow tracks the incident/CR lifecycle, an AI agent picks the correct renewal strategy (PEM vs Java keystore), an operator approves via SNOW, and AAP renews and validates TLS automatically.

## Workflow Overview

Splunk Cert Alert → Create SNOW Incident → AI Plan Renewal → Update Incident → Create CR → Authorize CR → Approval Gate (EDA bridges from SNOW) → Route by Cert Type → Run Renewal Job → Validate → Resolve Incident + Close CR

## Capabilities

| Playbook | Job Template | Actions | What It Does |
|---|---|---|---|
| `renew_certificate.yml` | Renew Certificate | n/a (single purpose) | PEM cert renewal via Vault CA, install for nginx, reload |
| `renew_keystore_certificate.yml` | Renew Keystore Certificate | n/a (single purpose) | Java keystore renewal via Vault, restart Tomcat |
| `validate_certificate.yml` | Validate Cert Renewal | n/a (single purpose) | OpenSSL TLS handshake check, report cert details |
| `manage_snow_incident.yml` | Manage SNOW Incident | `create`, `update`, `resolve` | Full incident lifecycle in ServiceNow |
| `manage_snow_change_request.yml` | Manage SNOW Change Request | `create`, `authorize`, `update`, `review`, `close` | Full CR lifecycle in ServiceNow |
| `bridge_ao_approval.yml` | Bridge AO Approval | n/a (single purpose) | Bridges SNOW CR approval to AO approval gate |
| `trigger_ao_workflow.yml` | AO Workflow Bridge | n/a (single purpose) | EDA-to-AO bridge for webhook triggers |
| `manage_git_repo.yml` | Manage Git Repo | `commit_file`, `create_pr` | Commit files and raise PRs via GitHub API |

## Key Technical Decisions

### Certificate Infrastructure
- **Vault PKI** runs in dev mode on the demo VM (token: `demo-root-token`). The PKI role is `cert-demo` under the `pki` mount.
- **nginx** uses PEM files at `/etc/pki/tls/certs/server.crt` and `/etc/pki/tls/private/server.key`. Reload with `systemctl reload nginx`.
- **Tomcat** uses a Java keystore at `/opt/tomcat/conf/keystore.jks` (password: `changeit`). Restart with `systemctl restart tomcat`. Keystore is rebuilt from PKCS12 → JKS on each renewal.
- **Cert TTL**: normal certs = `2160h` (90 days), near-expiry demo reset = `120h` (5 days)

### Monitoring Chain
- **Cron script** (`check_cert.sh`) runs every minute, uses `openssl s_client` to probe `:443` and `:8443`
- **Push script** (`push_cert_to_splunk.sh`) sends JSON events to Splunk HEC
- **Splunk saved search** fires every 4 minutes when `days_remaining <= 7`, sends webhook to AO
- Splunk is a log aggregator/alerter, NOT a monitoring tool — the cron script does the actual monitoring

### Environment Variables
- `CERT_DOMAIN` is the hostname for demo certs (must resolve to VM IP)
- `VAULT_TOKEN` is the Vault dev-mode root token
- `SPLUNK_PASSWORD` and `SPLUNK_HEC_TOKEN` are for Splunk container setup
- ServiceNow vars support both `SERVICENOW_*` and `SN_*` naming
- AO webhook credentials come from AO after publishing the workflow
- AO API service account credentials are for the approval bridge (separate from webhook creds)

### ServiceNow PDI Gotchas
- `close_code` must be `"Solution provided"` (not `"Solved (Permanently)"`)
- Resolving an incident is a two-step operation: add work notes first, then resolve
- Work notes must be wrapped in `[code]...[/code]` tags for proper HTML rendering
- AI output uses HTML formatting (`<h3>`, `<p>`, `<ul>`, `<code>`)

### AO Workflow JSON Format
- Uses `schema_version: "2.0.0"`, `triggers` array, `edges` array, `${var}` syntax
- Node types: `aap_job_template`, `agentic`, `switch`, `approval`
- AAP job nodes use `parameters.job_template_name` and `parameters.extra_vars`
- Agentic nodes use `parameters.prompt`, `parameters.model`, and `parameters.response_schema`
- AI output accessed at `${node.result.content.field}` when using response schema
- Switch conditions: `${node.result.content.field} == 'value'`
- Approval nodes use `from_port: "approved"` / `from_port: "rejected"` on outgoing edges

### EDA Gotchas
- EDA activations must NOT have event streams attached if using `servicenow.itsm.records` source
- The EDA controller credential needs host URL with `/api/controller/` path suffix (AAP 2.5+)
- CR approval bridge: `event.state == '-1'` is the Implement state in ServiceNow
- Splunk webhook goes directly to AO — EDA only handles the CR approval bridge

### CaC Gotchas
- CaC cannot overwrite encrypted credential fields — delete the credential first or edit in AAP UI
- The controller project must be synced before CaC can create job templates
- Two-pass CaC: first run creates objects with placeholders, second run (after AO publish) updates real creds
- Uses `set -a; source .env; set +a` pattern for loading env vars

### Infrastructure
- Terraform provisions EC2 + VPC + Elastic IP in eu-west-1
- Security group opens: 22 (SSH), 80 (HTTP), 443 (nginx TLS), 8443 (Tomcat TLS), 8200 (Vault), 8000/8088/8089 (Splunk)
- All services (nginx, Tomcat, Vault container, Splunk container) run on a single demo VM

## Deployment Order

1. Build DE + EE images (`./dependencies/build-images.sh --push`)
2. `terraform apply` (provisions EC2)
3. `setup-apply.sh` (installs nginx + Vault + Tomcat + Splunk)
4. `cac-apply.sh` (creates AAP objects — needs project synced first)
5. Import AO workflow in AO UI, configure agentic node AI credential + MCP, publish
6. Update `.env` with AO webhook creds, re-run `cac-apply.sh`
7. Restart EDA activation in AAP UI
8. `generate_expired_cert.yml` (reset certs to trigger demo)
9. `./scripts/test-trigger.sh` (verify the pipeline)
