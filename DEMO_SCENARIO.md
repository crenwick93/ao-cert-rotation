# Demo Scenario — Intelligent Cert Rotation

## The Setup

Two production services run on the same host — an nginx web server (PEM certificate on :443) and a Java API server (Java keystore certificate on :8443). Both certificates are approaching expiry, with 5 days remaining.

A cron-based monitoring script checks both certs every minute via `openssl s_client`, pushes structured JSON events to Splunk, and Splunk fires a webhook alert to Automation Orchestrator when `days_remaining <= 7`.

## Why This Matters — The 47-Day Cert Era

As of March 2026, public TLS certificate validity is capped at 200 days (down from 398). By March 2029, it drops to 47 days — roughly 8x more renewals per year. Manual cert management is no longer viable at any meaningful scale.

| Old world (398 days) | New world (47 days by 2029) |
|---|---|
| Renew once a year | Renew every 6 weeks |
| A human can follow a runbook | Automation is mandatory |
| A missed renewal is a yearly risk | A missed renewal is a monthly risk |
| Cert management is a task | Cert management is a system you operate |

The Home Office doesn't manage 2 certificates — it manages thousands across citizen-facing services, internal APIs, and infrastructure. This demo shows how Automation Orchestrator handles that at scale.

## The Two Certificate Types

| | PEM (nginx) | Java Keystore (Tomcat) |
|---|---|---|
| **Format** | Plain text files (.crt + .key) | Binary encrypted container (.jks) |
| **Tools** | `openssl` | `openssl` + `keytool` (2-step conversion) |
| **Renewal steps** | 2 — write files, reload nginx | 5 — convert PEM to PKCS12, import to keystore, restart |
| **Service impact** | Zero-downtime reload | Full restart required |
| **Complexity** | Low | High |

The same workflow handles both — the switch node routes to the correct renewal playbook based on `cert_type` from the Splunk alert. Each playbook knows how to handle its cert format.

## The Workflow

```
Splunk Cert Alert (webhook)
  │
  ├─ Create SNOW Incident
  │    Tracks the cert expiry event in ServiceNow
  │
  ├─ AI: Assess & Recommend
  │    Queries CMDB via ServiceNow MCP to understand:
  │      - What CI is this host? What business service does it support?
  │      - What other services depend on it? (blast radius)
  │      - Business criticality rating
  │      - Change freeze status
  │      - Historical incidents on this CI
  │    Writes a risk assessment into the SNOW incident
  │
  ├─ Update SNOW Incident (with AI risk assessment)
  │
  ├─ Create SNOW Change Request
  │    Auto-populated with justification, implementation plan,
  │    backout plan, and test plan
  │
  ├─ Authorize CR (request approval in ServiceNow)
  │
  ├─ Approval Gate
  │    Operator reads the AI risk brief in ServiceNow and
  │    makes an informed approval decision.
  │    EDA bridges the SNOW CR approval to AO automatically.
  │
  ├─ Switch: Route by cert_type
  │    ├─ pem → Renew PEM Certificate (nginx)
  │    └─ java_keystore → Renew Keystore Certificate (Tomcat)
  │
  ├─ Validate Renewal
  │    OpenSSL TLS handshake check — verifies the new cert
  │    is live with correct subject, issuer, and expiry > 7 days
  │
  ├─ Resolve SNOW Incident (with validation results)
  │
  └─ Close SNOW Change Request
```

## What Makes the AI Node Valuable

### Without CMDB context (just a switch)

> AI reads: `cert_type: pem, host: certdemo, days_remaining: 5`
> AI outputs: "It's a PEM cert, use the PEM renewal template."
>
> **A switch node does this for free, instantly, deterministically.**

### With ServiceNow CMDB context (via MCP)

> AI reads the Splunk alert, then queries CMDB via ServiceNow MCP:
>
> - Looks up the host → **citizen portal frontend** (CI0012847)
> - Pulls dependency map → **3 downstream services** depend on it (identity verification API, document upload service, notification gateway)
> - Checks business criticality → rated **Critical**
> - Checks change schedule → change freeze starts **Friday**
> - Checks incident history → last cert failure caused **INC0045231 (P1)** two months ago
>
> AI writes into the SNOW incident:
>
> *"This PEM certificate protects the citizen portal frontend (CI0012847, rated Critical). Three services depend on it: identity verification API, document upload service, and notification gateway. A certificate failure on this host caused P1 incident INC0045231 in July. A change freeze begins Friday — recommend immediate renewal in the current maintenance window. Confidence: High. Risk of NOT renewing: High."*
>
> **That's what a senior engineer would do. A switch node cannot do this.**

### The demo talking point

> "The AI isn't just routing to a playbook — it's doing what a senior engineer would do before recommending a change. It checks the CMDB, understands what depends on this service, looks at the incident history, and gives the approver a proper risk brief. The operator isn't rubber-stamping a Change Request — they're making an informed decision based on real operational context.
>
> The actual renewal is pure automation — deterministic, fast, cheap. But the DECISION to renew, and the CONFIDENCE in that decision, is where AI adds genuine value."

## Why Not Just Use AI Everywhere?

This demo deliberately uses AI only where it adds value:

| Step | Mode | Why |
|---|---|---|
| Cert monitoring | **Deterministic** (cron + openssl) | Known checks, known thresholds. No reasoning needed. |
| Splunk alerting | **Event-driven** (saved search + webhook) | Rule-based threshold. No reasoning needed. |
| SNOW incident creation | **Deterministic** (AAP job template) | Template fields from trigger data. No reasoning needed. |
| Risk assessment | **AI-driven** (agentic node + CMDB MCP) | Requires reasoning across multiple data sources — dependencies, history, blast radius. |
| Approval | **Human-in-the-loop** (SNOW CR + EDA bridge) | Operator reviews AI brief and makes the call. |
| Cert renewal | **Deterministic** (AAP job template) | Known procedure per cert type. No reasoning needed. |
| Validation | **Deterministic** (AAP job template) | OpenSSL check — pass/fail. No reasoning needed. |
| SNOW closure | **Deterministic** (AAP job template) | Template fields from validation results. No reasoning needed. |

> "We use AI where it genuinely adds value — reasoning across operational context to inform a decision. For everything else, proven deterministic automation is faster, cheaper, and more reliable. Automation Orchestrator gives you both on the same canvas, governed by the same RBAC, audit trail, and approval gates."

## MCP Servers Used

| MCP Server | Used By | Purpose |
|---|---|---|
| **AAP MCP** | AI agentic node | Discover available job templates, view inventory, check job history |
| **ServiceNow MCP** | AI agentic node | Query CMDB for CI details, dependency maps, business criticality, incident history |

## Prerequisites for the AI Node

1. **LiteLLM** (or direct model access) configured as an AI credential in AO
2. **AAP MCP server** deployed and accessible from AO
3. **ServiceNow MCP server** configured with CMDB read access
4. **CMDB data pre-populated** in your ServiceNow instance — the demo hosts registered as CIs with relationships, business criticality, and service maps

## Demo Reset

Run `generate_expired_cert.yml` to create certificates with ~5 days remaining:

```bash
ansible-playbook -i setup/playbooks/inventory/hosts.yml \
  setup/playbooks/generate_expired_cert.yml
```

Within minutes, the cron script detects the near-expiry certs, Splunk fires the alert, and the full workflow kicks off automatically.
