# Cert Rotation Demo — Live Narration Script

## Pre-Demo Checklist

- [ ] Demo VM running (nginx :443, Tomcat :8443, Vault :8200, Splunk :8000)
- [ ] AAP Controller accessible with all job templates synced
- [ ] AO workflow published and running
- [ ] EDA activation running (CR approval bridge)
- [ ] ServiceNow instance accessible
- [ ] Certs reset to near-expiry (`generate_expired_cert.yml`)

## Opening (1 min)

> "Today I'm going to show you an intelligent certificate rotation workflow powered by Ansible Automation Platform and Automation Orchestrator.
>
> The scenario: we have two production services — an nginx web server using a standard PEM certificate, and a Java API server using a Java keystore certificate. Both certificates are approaching expiry.
>
> What makes this demo interesting is that **one workflow intelligently handles both certificate types**. An AI agent analyzes each certificate, discovers the available AAP job templates, and selects the correct renewal strategy — without any hardcoded routing."

## Act 1: The Alert (2 min)

> "Let's start by looking at what's happening. Our monitoring setup uses a simple cron script that checks certificate expiry every minute using OpenSSL. It pushes the results into Splunk as structured JSON events."

**Show:** Splunk UI → Search `index=main sourcetype=cert_monitor` → Show the events with `days_remaining: 5` and `status: critical`.

> "Splunk has a saved search that fires every 4 minutes: if any cert has 7 days or fewer remaining, it sends a webhook alert to Automation Orchestrator. This gives us a realistic window — a week before expiry — to get the renewal approved and completed."

## Act 2: ServiceNow Incident (1 min)

> "The first thing the workflow does is create a ServiceNow incident to track this cert expiry event."

**Show:** ServiceNow → Incident list → New incident created with cert details.

## Act 3: AI Analysis (3 min)

> "Now here's where it gets intelligent. The AI agent receives the cert alert details and uses AAP's MCP tools to discover what job templates are available. It finds 'Renew Certificate' for PEM certs and 'Renew Keystore Certificate' for Java keystores.
>
> Based on the cert type in the alert — in this case, 'pem' for nginx — it recommends the correct job template with a confidence score."

**Show:** AO workflow UI → Task agent node → Show the AI analysis output with recommended template and confidence.

> "The analysis is then written back to the ServiceNow incident as a work note, so operators have full visibility."

**Show:** ServiceNow → Incident → Work notes → AI analysis with confidence score.

## Act 4: Change Request & Approval (2 min)

> "Before making any changes, the workflow creates an emergency Change Request in ServiceNow with full justification, implementation plan, backout plan, and test plan — all auto-populated from the AI analysis."

**Show:** ServiceNow → Change Request → Show the CR with all fields populated.

> "The workflow is now paused at an approval gate. In a production environment, the CAB or an on-call operator would review this CR. Let me approve it now."

**Action:** In ServiceNow, move the CR to the Implement state.

> "EDA is polling ServiceNow for CR state changes. It detects the approval and bridges it to the AO workflow gate."

**Show:** AO workflow UI → Approval node transitions to approved.

## Act 5: Renewal & Validation (2 min)

> "The switch node routes to the correct renewal job based on the AI's analysis. For a PEM cert, it runs the 'Renew Certificate' template, which requests a new cert from Vault, installs it, and reloads nginx."

**Show:** AAP → Jobs → Renew Certificate job running → Show the output.

> "After renewal, an automated validation step runs an OpenSSL TLS handshake check to verify the new certificate is live and has the expected expiry — well over 7 days now."

**Show:** AAP → Jobs → Validate Cert Renewal → Show the validation report.

## Act 6: Closure (1 min)

> "Finally, the workflow resolves the ServiceNow incident with the validation results and closes the Change Request. The entire lifecycle — from alert to closure — is tracked and auditable."

**Show:** ServiceNow → Incident → Resolved with validation details. CR → Closed.

## Closing (1 min)

> "To recap: one workflow intelligently handled two different certificate types using AI-driven routing. The operator only had to approve a Change Request — everything else was automated.
>
> In production, this same pattern scales to dozens of certificate types and hundreds of services, with the AI agent adapting to whatever renewal strategies are available in AAP."

## Key Talking Points

- **AI-driven routing** — No hardcoded logic for cert types; the AI discovers templates via MCP
- **7-day pre-expiry window** — Realistic operational timeline for approval
- **Full ITSM lifecycle** — Incident tracking + CR approval + closure
- **Validation built-in** — Automated TLS verification after renewal
- **Human-in-the-loop** — Operator approves via ServiceNow before any changes
