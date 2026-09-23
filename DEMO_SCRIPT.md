# Cert Rotation Demo — Live Narration Script

## Pre-Demo Setup

Run these commands **before** the audience arrives:

```bash
# 1. Clear all ServiceNow CRs and incidents (clean slate)
# Use the SNOW API or do manually in SNOW UI

# 2. Reset Splunk alert (clears suppression + triggered alerts)
ssh -i setup/terraform/demo-key.pem ec2-user@63.32.42.56 '
sudo curl -sk -X DELETE "https://localhost:8089/servicesNS/admin/search/saved/searches/Certificate%20Expiry%20Alert" -u "admin:redhat123" -o /dev/null
sleep 2
sudo curl -sk -X POST "https://localhost:8089/servicesNS/admin/search/saved/searches" -u "admin:redhat123" \
  -d "name=Certificate Expiry Alert" \
  -d "search=index=main sourcetype=cert_monitor days_remaining<=7 earliest=-10m | head 1" \
  -d "is_scheduled=1&cron_schedule=* * * * *" \
  -d "alert_type=number of events&alert_comparator=greater than&alert_threshold=0" \
  -d "actions=webhook&action.webhook.param.url=https://webhook.site/test" \
  -d "alert.track=1&alert.suppress=1&alert.suppress.period=5m&alert.suppress.fields=service" \
  -d "dispatch.earliest_time=-10m&dispatch.latest_time=now" -o /dev/null
'

# 3. Expire the PEM cert (nginx) — ~5 days remaining
./scripts/expire-pem.sh

# 4. Wait 1-2 minutes for Splunk to show the alert
# Verify at http://63.32.42.56:8000 → Alerts → Certificate Expiry Alert → Triggered Alerts
```

## Pre-Demo Checklist

- [ ] Demo VM running (nginx :443, Tomcat :8443, Vault :8200, Splunk :8000)
- [ ] AAP Controller accessible, all job templates synced
- [ ] AO workflow published
- [ ] EDA activation running (cert-rotation — CR bridge)
- [ ] ServiceNow instance clean, CMDB populated, change templates created
- [ ] PEM cert expired (~5 days), Splunk alert visible
- [ ] Browser open to citizen portal (`https://63.32.42.56:443`)
- [ ] SSH session ready to the demo VM

## Opening (1 min)

> "Today I'm showing certificate rotation powered by Ansible Automation Platform and Automation Orchestrator.
>
> We have two production services — a citizen-facing web portal using a PEM certificate, and a Java API server using a keystore certificate. The PEM cert is approaching expiry.
>
> What's interesting is how differently each cert type is handled. PEM renewals are zero-downtime — fully automated. Java keystore renewals require a restart, so they need human approval in ServiceNow."

## Act 1: Show the Cert Is Expiring (2 min)

**Browser:** Visit `https://63.32.42.56:443` → click padlock → show cert expiry (~5 days)

> "Here's the citizen portal. The padlock shows the cert expires in 5 days."

**SSH into demo VM:**
```bash
echo | openssl s_client -connect localhost:443 -servername certdemo.demoredhat.com 2>/dev/null | openssl x509 -noout -subject -issuer -dates
```

> "The server confirms it — 5 days to expiry."

**Splunk:** Show `http://63.32.42.56:8000` → Alerts → Certificate Expiry Alert → Triggered Alerts

> "Our monitoring pushes cert data into Splunk every minute. When days remaining drops below 7, the alert fires."

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
echo | openssl s_client -connect localhost:8443 -servername certdemo.demoredhat.com 2>/dev/null | openssl x509 -noout -dates
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
# Expire PEM cert only
./scripts/expire-pem.sh

# Expire keystore cert only
./scripts/expire-keystore.sh

# Trigger PEM workflow
./scripts/test-trigger.sh

# Trigger keystore workflow
./scripts/test-trigger.sh keystore

# Check cert from server
echo | openssl s_client -connect localhost:443 2>/dev/null | openssl x509 -noout -dates
echo | openssl s_client -connect localhost:8443 2>/dev/null | openssl x509 -noout -dates
```
