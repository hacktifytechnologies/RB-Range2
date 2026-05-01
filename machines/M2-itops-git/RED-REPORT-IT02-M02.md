# Incident Notification Report (INREP)
**Report ID:** INREP-IT02-M02 | **Incident:** GRIDFALL-RNG-IT02-M02

## 1. Current Situation
Gitea internal repository (`203.x.x.x:3000`) — the `svc-cicd/pul-infra-config` repository contains a prior commit where a `.env` file with HashiCorp Vault AppRole credentials (`VAULT_ROLE_ID` + `VAULT_SECRET_ID`) was committed and later deleted. An adversary authenticated as `svc-cicd` cloned the repository and used `git log`/`git show` to recover the credentials from history. Vault AppRole login to `203.x.x.x:8200` is now enabled — pivot to M3 in progress.

**Threat Level:** `CRITICAL` | **Areas of Concern:** Vault access enables broad secrets retrieval including AD service account credentials.

## 2. IOCs
| Type | Value |
|---|---|
| Attacker IP | `203.0.2.X` |
| Gitea User | `svc-cicd` |
| Compromised | `VAULT_ROLE_ID=pul-cicd-role-7a3f9b2c1d4e` + `VAULT_SECRET_ID` |
| Pivot Target | Vault `203.x.x.x:8200` |

## 3. Vulnerability
Vault AppRole credentials committed in plain text in git commit `3c2b1a0`. File "deleted" in subsequent commit but persists in all historical snapshots. **CWE-312:** Cleartext Storage of Sensitive Information.

## 4. Prevention
- `.env` must be in `.gitignore` at repo creation. Enforce at org level via Gitea template.
- Pre-receive hook scanning for credential patterns.
- Vault AppRole secret_id must use `secret_id_num_uses=1`.

## POC
> **[Attach: `git log --oneline` output showing commit with .env]**
> **[Attach: `git show <hash>:.env` output with credentials visible]**
> **[Attach: Vault AppRole login response with client_token]**

**Prepared By:** Blue Team — [Team Name] | **Reference:** GRIDFALL-RNG-IT02-M02

---

# Situation Report (SITREP)
**Report ID:** SITREP-IT02-M02 | **Incident:** GRIDFALL-RNG-IT02-M02

## 1. Incident Overview
- Git history excavation on Gitea `203.x.x.x:3000` — `svc-cicd` account cloned `pul-infra-config` repo.
- Commit `3c2b1a0` excavated via `git show` — `.env` file with Vault AppRole credentials retrieved.
- AppRole login to Vault `203.x.x.x:8200` performed — client token issued.
- Pivot to M3 (HashiCorp Vault) in progress.

**Severity:** `CRITICAL` | **Impact:** `SEVERE` — Vault access grants read of all secrets in `secret/pul/*`

## 2. Attack Sequence
1. Login to Gitea as `svc-cicd:CICD@Deploy!2024` (credential from M1 LDAP).
2. `git clone` of `pul-infra-config` repository.
3. `git log --oneline` — identifies commit "Add deployment environment configuration".
4. `git show <hash>:.env` — retrieves deleted `.env` with `VAULT_ROLE_ID` + `VAULT_SECRET_ID`.
5. `curl POST /v1/auth/approle/login` to Vault — `client_token` issued.

## 3. Response Actions
**Containment:** Vault AppRole `secret_id` rotated; `svc-cicd` Gitea account suspended; attacker IP blocked.
**Eradication:** Git history rewritten via `git filter-branch`; pre-receive hook deployed for secret scanning; `.gitignore` template enforced org-wide.
**Recovery:** New Vault AppRole credentials provisioned with `secret_id_num_uses=1`; CI/CD pipeline updated.

## 4. TTPs
- **T1552.001** — Credentials in Files: `.env` file committed to git repository.
- **T1213.003** — Data from Code Repositories: git history excavation to recover deleted file.
- **T1078.004** — Valid Accounts: Cloud/Service Accounts — AppRole used for Vault authentication.

## 5. Communication
- **SOC Lead:** Immediate — Vault credentials compromised; secrets estate at risk.
- **Vault/Secrets Team:** Urgent — rotate all AppRole credentials; audit `secret/pul/*` access log.
- **CERT-In:** Notification pending — secrets management infrastructure breach.

## POC
> **[Attach: git log, git show, Vault login screenshots]**

**Prepared By:** Blue Team — [Team Name] | **Reference:** GRIDFALL-RNG-IT02-M02

---

# Red Team Engagement Report
**Report ID:** RED-REPORT-IT02-M02 | **Machine:** M2 — itops-git

| Field | Detail |
|---|---|
| Target | PUL Gitea `203.x.x.x:3000` |
| Outcome | **SUCCESSFUL** — Vault AppRole credentials extracted from git history |
| Pivot From | M1 LDAP `svc-cicd:CICD@Deploy!2024` |

## Commands Executed
```bash
git clone http://svc-cicd:CICD%40Deploy%212024@203.x.x.x:3000/svc-cicd/pul-infra-config.git
cd pul-infra-config
git log --oneline
git show 3c2b1a0:.env
curl -s -X POST http://203.x.x.x:8200/v1/auth/approle/login \
  -d '{"role_id":"pul-cicd-role-7a3f9b2c1d4e","secret_id":"3b8f2a1c-9d4e-7f6a-2b1c-8d3f9a7e4b2c"}'
```

## Pivot Artifact
| Artifact | Value |
|---|---|
| Vault Role ID | `pul-cicd-role-7a3f9b2c1d4e` |
| Vault Secret ID | `3b8f2a1c-9d4e-7f6a-2b1c-8d3f9a7e4b2c` |
| Vault Addr | `http://203.x.x.x:8200` |
| Next Target | M3 — itops-vault |

**Report Prepared By:** [Red Team Operator] | **Classification:** RESTRICTED
