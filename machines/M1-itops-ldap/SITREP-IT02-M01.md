# Situation Report (SITREP)
**Classification:** RESTRICTED — Internal Use Only
**Report ID:** SITREP-IT02-M01
**Version:** 1.0
**Incident ID:** GRIDFALL-RNG-IT02-M01

---

## 1. Incident Overview
- LDAP directory enumeration on `203.x.x.x:389` by adversary pivoting from RNG-IT-01.
- Anonymous bind + authenticated bind using `svc-deploy` credential performed full subtree SEARCH.
- `userPassword-plain: CICD@Deploy!2024` retrieved from `cn=svc-cicd` — CI/CD pivot credential compromised.
- Pivot to M2 (Gitea, `203.x.x.x:3000`) in progress.

**Severity:** `HIGH` | **Impact:** `SEVERE`

| Machine | IP | Service | Impact |
|---|---|---|---|
| M1 — itops-ldap | `203.x.x.x` | slapd (port 389) | Full directory enumerated; svc-cicd credential exfiltrated |

---

## 2. Incident Details
**Attack Sequence:**
1. Attacker connects to `203.x.x.x:389` — anonymous bind succeeds, OU structure returned.
2. Authenticated bind as `svc-deploy` (pivoted from RNG-IT-01 M5).
3. `ldapsearch` with `scope=2` over `ou=service` — all service account attributes retrieved.
4. `userPassword-plain: CICD@Deploy!2024` extracted from `cn=svc-cicd` entry.
5. Bind verified with `svc-cicd` — credential confirmed valid.
6. Pivot to Gitea `203.x.x.x:3000` initiated.

---

## 3. Response Actions

**Containment:**
- `userPassword-plain` attribute deleted from all LDAP accounts.
- Anonymous bind disabled via `cn=config` modification.
- ACL updated: password attributes restricted to `self` + `cn=admin` only.
- Attacker source IP blocked: `ufw deny from <IP> to any port 389`.

**Eradication:**
- LDAP ACL rewritten to principle of least privilege.
- LDAPS (port 636) enabled with self-signed certificate.
- All accounts audited for non-standard attribute usage.
- `svc-cicd` credential rotated in LDAP and all downstream systems.

**Recovery:**
- Monitoring rule deployed: alert on `SRCH scope=2` from non-admin bind DNs.
- LDAP access restricted via firewall to internal management VLAN only.

**Lessons Learned:**
- Non-standard custom attributes must be reviewed before production deployment — provisioning scripts should never store plaintext credentials in directory attributes.
- ACL design must explicitly deny attribute-level access rather than relying on implicit inheritance.
- LDAP without TLS on an internal segment is still susceptible to passive capture from a compromised adjacent host.
- The multi-stage chain (RNG-IT-01 → M1) demonstrates how a single initial access credential can cascade through a directory service into the CI/CD plane.

---

## 4. Technical Analysis

**TTPs:**

**Account Discovery: Domain Account (T1087.002)**
Adversary performed a full subtree LDAP search to enumerate all accounts, groups, and attributes across the organisational directory — a standard pre-credential-harvest reconnaissance step.

**Unsecured Credentials: Credentials in Files (T1552.001)**
The `userPassword-plain` attribute — a non-standard schema extension used during provisioning — retained a cleartext copy of the service account password, making it trivially readable by any authenticated LDAP user with read access to that entry.

**Mitigations:**
- LDAP ACLs must restrict password attribute reads to `self` and `cn=admin` only.
- Schema extensions storing credential data must be prohibited by change management policy.
- Enable audit logging at `olcLogLevel: stats` minimum; forward to SIEM.

---

## 5. Communication
- **SOC Lead:** Immediate — LDAP directory breach; credential chain progressing into CI/CD zone.
- **DevOps/CI-CD Team:** Urgent — `svc-cicd` credential compromised; Gitea access at risk.
- **CERT-In:** Notification pending — CII adjacent directory service compromised.

---

## 6. POC
> **[Attach: ldapsearch output — userPassword-plain attribute visible on svc-cicd]**
> **[Attach: syslog — full subtree search log entries]**
> **[Attach: Anonymous bind confirmation — ldapsearch with no -D/-w returning OU tree]**

---

## 7. Submission
**Prepared By:** Blue Team — [Team Name]
**Incident Reference:** GRIDFALL-RNG-IT02-M01
