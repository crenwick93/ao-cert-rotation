#!/usr/bin/env python3
"""Create the cert rotation demo business service, component CIs, and
relationships in a ServiceNow instance.

Reads ci_definitions.yml for the graph structure. Idempotent — running twice
does not create duplicates (uses the [cert-demo] description prefix to detect
existing records).

Usage:
    export SERVICENOW_INSTANCE_URL=https://devXXXXXX.service-now.com
    export SERVICENOW_USERNAME=admin
    export SERVICENOW_PASSWORD=...
    python3 setup_cmdb.py [--demo-host-ip 1.2.3.4]
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import requests
import yaml

DEMO_TAG = "[cert-demo]"
SCRIPT_DIR = Path(__file__).resolve().parent
CI_DEFS_PATH = SCRIPT_DIR / "ci_definitions.yml"

session = requests.Session()


def snow_url(path: str) -> str:
    base = os.environ["SERVICENOW_INSTANCE_URL"].rstrip("/")
    return f"{base}{path}"


def configure_session() -> None:
    session.auth = (os.environ["SERVICENOW_USERNAME"], os.environ["SERVICENOW_PASSWORD"])
    session.headers.update({"Accept": "application/json", "Content-Type": "application/json"})


def find_existing(table: str, query: str) -> dict | None:
    """Return the first record matching `query`, or None."""
    url = snow_url(f"/api/now/table/{table}?sysparm_query={query}&sysparm_limit=1")
    r = session.get(url)
    if r.status_code == 400 and table != "cmdb_ci":
        url = snow_url(f"/api/now/table/cmdb_ci?sysparm_query={query}&sysparm_limit=1")
        r = session.get(url)
    r.raise_for_status()
    results = r.json().get("result", [])
    return results[0] if results else None


def create_or_update(table: str, name: str, ci_class: str, data: dict) -> str:
    """Create a CI or return its sys_id if it already exists.
    Falls back to cmdb_ci if the class-specific table doesn't exist."""
    query = f"name={name}^descriptionLIKE{DEMO_TAG}"
    existing = find_existing(table, query)
    if existing:
        sys_id = existing["sys_id"]
        print(f"  EXISTS  {ci_class}/{name}  sys_id={sys_id}")
        patch_url = snow_url(f"/api/now/table/cmdb_ci/{sys_id}")
        r = session.patch(patch_url, json=data)
        r.raise_for_status()
        return sys_id

    r = session.post(snow_url(f"/api/now/table/{table}"), json=data)
    if r.status_code == 400 and table != "cmdb_ci":
        r = session.post(snow_url("/api/now/table/cmdb_ci"), json=data)
    r.raise_for_status()
    sys_id = r.json()["result"]["sys_id"]
    print(f"  CREATED {ci_class}/{name}  sys_id={sys_id}")
    return sys_id


def create_relationship(parent_id: str, child_id: str, rel_type: str) -> str:
    """Create a CMDB relationship, skipping if one already exists."""
    rel_type_id = resolve_rel_type(rel_type)
    query = f"parent={parent_id}^child={child_id}^type={rel_type_id}"
    existing = find_existing("cmdb_rel_ci", query)
    if existing:
        print(f"  EXISTS  relationship {rel_type} (sys_id={existing['sys_id']})")
        return existing["sys_id"]

    data = {"parent": parent_id, "child": child_id, "type": rel_type_id}
    r = session.post(snow_url("/api/now/table/cmdb_rel_ci"), json=data)
    r.raise_for_status()
    sys_id = r.json()["result"]["sys_id"]
    print(f"  CREATED relationship {rel_type} (sys_id={sys_id})")
    return sys_id


def resolve_rel_type(name: str) -> str:
    """Look up a relationship type sys_id by its name (e.g. 'Contains::Used by').
    Creates the relationship type if it doesn't exist."""
    parts = name.split("::")
    parent_descriptor = parts[0].strip()
    child_descriptor = parts[1].strip() if len(parts) > 1 else parent_descriptor

    query = f"parent_descriptor={parent_descriptor}"
    existing = find_existing("cmdb_rel_type", query)
    if existing:
        return existing["sys_id"]

    data = {"parent_descriptor": parent_descriptor, "child_descriptor": child_descriptor}
    r = session.post(snow_url("/api/now/table/cmdb_rel_type"), json=data)
    r.raise_for_status()
    sys_id = r.json()["result"]["sys_id"]
    print(f"  CREATED relationship type '{name}' (sys_id={sys_id})")
    return sys_id


ASSIGNMENT_GROUPS = [
    "Digital Services",
    "Platform Services",
    "Application Services",
    "Identity Services",
    "Security Operations",
]


def create_assignment_groups() -> None:
    """Create assignment groups (sys_user_group) if they don't exist."""
    print("\nAssignment groups:")
    for name in ASSIGNMENT_GROUPS:
        query = f"name={name}"
        existing = find_existing("sys_user_group", query)
        if existing:
            print(f"  EXISTS  {name}  sys_id={existing['sys_id']}")
            continue
        data = {
            "name": name,
            "description": f"{DEMO_TAG} {name} team",
            "type": "itil",
        }
        r = session.post(snow_url("/api/now/table/sys_user_group"), json=data)
        r.raise_for_status()
        sys_id = r.json()["result"]["sys_id"]
        print(f"  CREATED {name}  sys_id={sys_id}")


CHANGE_TEMPLATES = [
    {
        "name": "Certificate Renewal - PEM",
        "description": f"{DEMO_TAG} Standard change template for PEM certificate renewal (nginx, Apache, HAProxy). Non-invasive: service reload, zero downtime.",
        "attributes": {
            "type": "standard",
            "risk": "low",
            "impact": "3",
            "priority": "3",
            "category": "Software",
            "assignment_group": "Platform Services",
            "approval": "approved",
            "implementation_plan": (
                "1. Request new PEM certificate from Vault CA.\n"
                "2. Replace cert and key files on the target host.\n"
                "3. Reload the web server (zero downtime — no restart).\n"
                "4. Automated TLS validation verifies new cert is live."
            ),
            "backout_plan": (
                "Restore certificate backup files (.bak) and reload the web server.\n"
                "- Cert: /etc/pki/tls/certs/server.crt.bak\n"
                "- Key: /etc/pki/tls/private/server.key.bak"
            ),
            "test_plan": (
                "OpenSSL TLS handshake check verifying:\n"
                "- Correct subject (CN matches domain)\n"
                "- Correct issuer (Vault CA)\n"
                "- Expiry > 7 days\n"
                "- Service responding on expected port"
            ),
        },
    },
    {
        "name": "Certificate Renewal - Java Keystore",
        "description": f"{DEMO_TAG} Standard change template for Java keystore certificate renewal (Tomcat, JBoss, Kafka). Invasive: service restart required, brief downtime.",
        "attributes": {
            "type": "standard",
            "risk": "medium",
            "impact": "2",
            "priority": "2",
            "category": "Software",
            "assignment_group": "Application Services",
            "implementation_plan": (
                "1. Request new certificate from Vault CA.\n"
                "2. Convert PEM to PKCS12, import into Java keystore.\n"
                "3. RESTART the application server (brief downtime expected).\n"
                "4. Automated TLS validation verifies new cert is live.\n\n"
                "NOTE: This change requires a service restart. Dependent services\n"
                "will experience brief connectivity loss. Schedule during a\n"
                "maintenance window if possible."
            ),
            "backout_plan": (
                "Restore keystore backup and restart the application server.\n"
                "- Keystore: /opt/tomcat/conf/keystore.jks.bak\n"
                "- Restart: systemctl restart tomcat"
            ),
            "test_plan": (
                "OpenSSL TLS handshake check verifying:\n"
                "- Correct subject (CN matches domain)\n"
                "- Correct issuer (Vault CA)\n"
                "- Expiry > 7 days\n"
                "- Service responding on expected port after restart"
            ),
        },
    },
]


def create_change_templates() -> None:
    """Create standard change templates in ServiceNow."""
    print("\nStandard Change Templates:")
    for tmpl in CHANGE_TEMPLATES:
        query = f"short_description={tmpl['name']}"
        existing = find_existing("std_change_producer_version", query)
        if existing:
            print(f"  EXISTS  {tmpl['name']}  sys_id={existing['sys_id']}")
            continue

        # First create the std_change_record_producer
        producer_query = f"name={tmpl['name']}"
        producer = find_existing("std_change_record_producer", producer_query)
        if not producer:
            producer_data = {
                "name": tmpl["name"],
                "description": tmpl["description"],
                "short_description": tmpl["name"],
            }
            r = session.post(snow_url("/api/now/table/std_change_record_producer"), json=producer_data)
            if r.status_code in (200, 201):
                producer = r.json()["result"]
                print(f"  CREATED producer {tmpl['name']}  sys_id={producer['sys_id']}")
            else:
                # Fall back to creating just the change template version
                print(f"  SKIP    producer {tmpl['name']} (status {r.status_code} — may need manual creation)")
                continue
        else:
            print(f"  EXISTS  producer {tmpl['name']}  sys_id={producer['sys_id']}")

        # Create the template version with pre-populated fields
        version_data = {
            "std_change_producer": producer["sys_id"],
            "short_description": tmpl["name"],
            "description": tmpl["description"],
            **{k: v for k, v in tmpl["attributes"].items()},
        }
        r = session.post(snow_url("/api/now/table/std_change_producer_version"), json=version_data)
        if r.status_code in (200, 201):
            sys_id = r.json()["result"]["sys_id"]
            print(f"  CREATED template version {tmpl['name']}  sys_id={sys_id}")
        else:
            print(f"  SKIP    template version {tmpl['name']} (status {r.status_code})")


def main() -> int:
    parser = argparse.ArgumentParser(description="Set up cert rotation demo CMDB in ServiceNow")
    parser.add_argument(
        "--demo-host-ip",
        help="IP address of the demo VM (populates ip_address on cert-bearing CIs)",
        default=os.environ.get("DEMO_HOST_IP", ""),
    )
    args = parser.parse_args()

    for var in ("SERVICENOW_INSTANCE_URL", "SERVICENOW_USERNAME", "SERVICENOW_PASSWORD"):
        if not os.environ.get(var):
            print(f"ERROR: {var} environment variable is not set", file=sys.stderr)
            return 1

    configure_session()
    create_assignment_groups()

    with open(CI_DEFS_PATH) as f:
        defs = yaml.safe_load(f)

    # Populate IP addresses on cert-bearing CIs and Vault
    if args.demo_host_ip:
        for comp in defs["components"]:
            if comp["name"] in ("citizen-portal-web", "citizen-portal-api", "vault-pki"):
                comp.setdefault("attributes", {})["ip_address"] = args.demo_host_ip

    # --- Business service ---
    bs = defs["business_service"]
    print(f"\nBusiness service: {bs['name']}")
    bs_data = {
        "name": bs["name"],
        "sys_class_name": bs["ci_class"],
        "description": bs["description"],
        **bs.get("attributes", {}),
    }
    bs_sys_id = create_or_update(bs["ci_class"], bs["name"], bs["ci_class"], bs_data)

    # --- Component CIs ---
    ci_sys_ids = {"business_service": bs_sys_id}
    print(f"\nComponent CIs:")
    for comp in defs["components"]:
        attrs = dict(comp.get("attributes", {}))
        ci_data = {
            "name": comp["name"],
            "sys_class_name": comp["ci_class"],
            "description": comp["description"],
            **attrs,
        }
        sid = create_or_update(comp["ci_class"], comp["name"], comp["ci_class"], ci_data)
        ci_sys_ids[comp["name"]] = sid

    # --- Relationships ---
    print(f"\nRelationships:")
    for rel in defs["relationships"]:
        parent_id = ci_sys_ids.get(rel["parent"])
        child_id = ci_sys_ids.get(rel["child"])
        if not parent_id:
            print(f"  WARNING: parent '{rel['parent']}' not found, skipping")
            continue
        if not child_id:
            print(f"  WARNING: child '{rel['child']}' not found, skipping")
            continue
        create_relationship(parent_id, child_id, rel["type"])

    print(f"\nCMDB setup complete. {len(ci_sys_ids)} CIs created/verified.")
    print("\nSys IDs:")
    for name, sid in ci_sys_ids.items():
        print(f"  {name}: {sid}")

    print("\nCMDB dependency graph:")
    print(f"  {bs['name']} (business service)")
    for comp in defs["components"]:
        print(f"    ├── {comp['name']} ({comp['ci_class']})")

    # --- Standard Change Templates ---
    create_change_templates()

    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
