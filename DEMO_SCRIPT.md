# Cert Rotation Demo — Live Narration Script

## Pre-Demo Setup

Run these commands **before** the audience arrives:

```bash
# 1. Full reset (renew certs to 90 days, clean Splunk index, clear SNOW CRs + incidents)
./scripts/demo-reset.sh

# 2. Expire the PEM cert (nginx) — ~5 days remaining
./scripts/expire-pem.sh

# 3. Wait ~2 minutes for the cron to push data and the Splunk alert to fire
# Verify at http://63.32.42.56:8000 → Alerts → Certificate Expiry Alert → Triggered Alerts
```

## Pre-Demo Checklist

- [ ] Demo VM running (nginx :443, Tomcat :8443, Vault :8200, Splunk :8000)
- [ ] AAP Controller accessible, all job templates synced
- [ ] AO workflow published
- [ ] EDA activation running (cert-rotation — CR bridge)
- [ ] ServiceNow instance clean, CMDB populated, change templates created
- [ ] PEM cert expired (~5 days), Splunk alert visible
- [ ] Browser open to citizen portal (`https://63.32.42.56`)
- [ ] SSH session ready to the demo VM

## Opening (1 min)

> "Today I'm showing certificate rotation powered by Ansible Automation Platform and Automation Orchestrator.
>
> We have two production services — a citizen-facing web portal using a PEM certificate, and a Java API server using a keystore certificate. The PEM cert is approaching expiry.
>
> What's interesting is how differently each cert type is handled. PEM renewals are zero-downtime — fully automated. Java keystore renewals require a restart, so they need human approval in ServiceNow."

## Act 1: Show the Cert Is Expiring (2 min)

**Browser:** Visit `https://63.32.42.56` → click padlock → show cert expiry (~5 days)

> "Here's the citizen portal. The padlock shows the cert expires in 5 days."

**SSH into demo VM:**
```bash
ssh -i setup/terraform/demo-key.pem ec2-user@63.32.42.56
echo | openssl s_client -connect localhost:443 -servername certdemo.demoredhat.com 2>/dev/null | openssl x509 -noout -subject -enddate
```

> "The server confirms it — 5 days to expiry."

**Splunk:** Show `http://63.32.42.56:8000` → Alerts → Certificate Expiry Alert → Triggered Alerts

> "Our monitoring pushes cert data into Splunk every minute. When days remaining drops below 7, the alert fires."

**Splunk search (optional):** Show what Splunk is ingesting:
```
index=main sourcetype=cert_monitor | table _time service cert_type days_remaining status
```

## Act 2: Fire the PEM Workflow (3 min)

> "The Splunk alert would normally trigger the workflow directly. Let me fire it now."

**Run from your laptop:**
```bash
./scripts/test-trigger.sh
```

> "The alert hits EDA, which triggers the Automation Orchestrator workflow. Watch — the PEM path runs completely hands-free."

**Show AO workflow:** The PEM path lights up:
1. Standard Change created from template
2. Cert renewed by AAP
3. Validation passes
4. Change tasks closed
5. CR auto-closed

**Show SNOW:** Open the CR
- Type: Standard, Configuration Item: citizen-portal-web
- Change tasks: Closed with job links
- Closure Information: validation results

> "Zero downtime, full audit trail, no human involvement."

**Browser:** Refresh → click padlock → cert now shows ~90 days

> "The cert is renewed. 90 days to go."

## Act 3: Expire the Keystore Cert (1 min)

> "Now let's expire the API server's keystore certificate."

```bash
./scripts/expire-keystore.sh
```

**SSH:**
```bash
echo | openssl s_client -connect localhost:8443 -servername certdemo.demoredhat.com 2>/dev/null | openssl x509 -noout -subject -enddate
```

> "5 days remaining on the keystore cert."

## Act 4: Fire the Keystore Workflow (3 min)

```bash
./scripts/test-trigger.sh keystore
```

> "This one takes a different path — it requires a Tomcat restart, so the workflow pauses for human approval."

**Show AO workflow:** Keystore path lights up, pauses at approval gate

> "The standard change is created. Let's review it in ServiceNow."

**Show SNOW:** Open the CR
- Type: Standard, CI: citizen-portal-api
- Click CI → show dependency map (web depends on api)
- Short description says RESTART REQUIRED

> "The operator reviews the change, sees the dependency map — the web frontend depends on this API. They decide when to proceed."

**In SNOW:** Move CR from New → Scheduled → Implement

> "The operator moves the change to Implement. EDA detects this and automatically resumes the workflow."

**Show AO workflow:** Gate approves, renewal runs:
1. Keystore renewed (Vault → PKCS12 → JKS → Tomcat restart)
2. Validation passes
3. CR auto-closed

> "The restart happened, cert validated, everything closed automatically."

## Closing (1 min)

> "To recap: two certificate types, two different operational impacts, one workflow.
>
> PEM renewals are fully automated — zero downtime. Keystore renewals pause for approval because they require a restart. The operator reviews in ServiceNow and decides when to proceed.
>
> Every step has a full audit trail: standard change from a template, linked to a CMDB CI, validation results, and direct links to the AAP job output. This is ITIL-correct certificate lifecycle management at scale.
>
> With cert lifetimes dropping to 47 days by 2029, this kind of automation isn't optional — it's mandatory."

## Quick Reference Commands

```bash
# Full reset (certs, Splunk, SNOW)
./scripts/demo-reset.sh

# Expire certs
./scripts/expire-pem.sh
./scripts/expire-keystore.sh

# Trigger workflows via EDA
./scripts/test-trigger.sh            # PEM
./scripts/test-trigger.sh keystore   # Keystore

# SSH to demo VM
ssh -i setup/terraform/demo-key.pem ec2-user@63.32.42.56

# Check certs from the VM
echo | openssl s_client -connect localhost:443 -servername certdemo.demoredhat.com 2>/dev/null | openssl x509 -noout -subject -enddate
echo | openssl s_client -connect localhost:8443 -servername certdemo.demoredhat.com 2>/dev/null | openssl x509 -noout -subject -enddate

# Splunk search
index=main sourcetype=cert_monitor | table _time service cert_type days_remaining status
```
