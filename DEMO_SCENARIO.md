# Demo Scenario — Cert Rotation

## The Setup

Two production services run on the same host — an nginx web server (PEM certificate on :443) and a Java API server (Java keystore certificate on :8443). Both certificates are approaching expiry, with 5 days remaining.

A cron-based monitoring script checks both certs every minute via `openssl s_client`, pushes structured JSON events to Splunk, and Splunk fires a webhook alert to EDA when `days_remaining <= 7`.

## Why This Matters — The 47-Day Cert Era

As of March 2026, public TLS certificate validity is capped at 200 days (down from 398). By March 2029, it drops to 47 days — roughly 8x more renewals per year. Manual cert management is no longer viable at any meaningful scale.

## The Two Certificate Types

| | PEM (nginx) | Java Keystore (Tomcat) |
|---|---|---|
| **Format** | Plain text files (.crt + .key) | Binary encrypted container (.jks) |
| **Renewal** | 2 steps — write files, reload | 5 steps — convert, import, restart |
| **Downtime** | Zero (reload) | Brief (restart required) |
| **Approval** | None needed | Human approval in ServiceNow |
| **Change Type** | Standard (auto-close) | Standard (operator moves to Implement) |

## The Workflow

```
Splunk Cert Alert → EDA → AO Workflow
  │
  ├─ Switch by cert_type
  │
  ├─── PEM (fully automated) ───────────────────────────
  │    Standard Change (from template, linked to CI)
  │    → Renew PEM cert (Vault → nginx reload)
  │    → Validate (OpenSSL TLS check)
  │    → Close Change (tasks + CR with audit trail)
  │
  └─── Java Keystore (human approval) ──────────────────
       Standard Change (from template, linked to CI)
       → Approval Gate (pauses workflow)
       → Operator reviews CR in SNOW, checks CI + deps
       → Operator moves CR: New → Scheduled → Implement
       → EDA detects Implement → bridges to AO
       → Renew keystore cert (Vault → PKCS12 → JKS → restart)
       → Validate (OpenSSL TLS check)
       → Close Change (tasks + CR with audit trail)
```

## What the Operator Sees in ServiceNow

- **Standard change** from a pre-approved template (Certificate Renewal - PEM or Java Keystore)
- **Configuration Item** linked (citizen-portal-web or citizen-portal-api)
- **Dependency map** showing what depends on this service
- **Implementation plan** from the template, mentioning AAP
- **Change tasks** (Implementation + Testing) closed with:
  - Description: what was done + AAP job link
  - Close notes: validation result summary
- **CR closure notes**: validation pass/fail, new expiry, days remaining, AAP job links

## Why Not AI?

This workflow is **pure deterministic automation**. The cert type is known from the alert, the renewal procedure is defined per type, and the routing is a simple switch. AI adds cost and latency for something a lookup handles.

AI is used where it genuinely adds value — like ticket enrichment (parsing unstructured text) or CVE triage (reasoning across multiple data sources). For cert rotation, proven automation is faster, cheaper, and more reliable.

> "We use AI where it genuinely adds value. For deterministic processes like cert rotation, pure automation is the right tool. Automation Orchestrator gives you both on the same canvas."

## Demo Reset

```bash
ansible-playbook -i setup/playbooks/inventory/hosts.yml \
  setup/playbooks/generate_expired_cert.yml
```

Creates certs with ~5 days remaining. Splunk detects within minutes and fires the alert.
