# solve_blue.md — M2 · itops-git
## Blue Team Solution Writeup

---

## Detection

### 1 — Gitea Audit Log
```bash
# Gitea writes access events to its log directory
grep -E "clone|raw|archive" /opt/gitea/log/gitea.log | tail -30
# OR via Gitea admin panel: /admin/repos → pul-infra-config → Git Hooks log
```

**Indicator:**
```
[I] Cloned repository: svc-cicd/pul-infra-config by svc-cicd from 203.0.2.X
[I] Raw file access: svc-cicd/pul-infra-config/raw/commit/3c2b1a0/.env
```

### 2 — Detect Secret in Git History
```bash
cd /opt/gitea/data/repositories/svc-cicd/pul-infra-config.git
# Search all commits for vault-like secrets
git log --all -p | grep -E "VAULT_ROLE_ID|VAULT_SECRET_ID|SECRET_ID"
```

---

## Containment
```bash
# 1. Rotate Vault AppRole credentials IMMEDIATELY
# (notify M3 Vault admin — old secret_id is fully compromised)

# 2. Disable svc-cicd Gitea account temporarily
curl -X PATCH http://203.x.x.x:3000/api/v1/admin/users/svc-cicd \
  -H "Authorization: basic $(echo -n 'gitadmin:GitAdmin@PUL2024!' | base64)" \
  -H "Content-Type: application/json" \
  -d '{"login_name":"svc-cicd","source_id":0,"active":false}'

# 3. Remove sensitive commit from git history (destructive — coordinate first)
cd /opt/gitea/data/repositories/svc-cicd/pul-infra-config.git
git filter-branch --force --index-filter \
  'git rm --cached --ignore-unmatch .env' \
  --prune-empty --tag-name-filter cat -- --all
```

## Eradication
- Never commit `.env` or secrets files — enforce `.gitignore` at repo template level.
- Enable Gitea secret scanning (or integrate with truffleHog pre-receive hook).
- Implement pre-commit hooks: `detect-secrets` or `git-secrets` to block credential commits.
- Vault AppRole `secret_id` must be single-use (`secret_id_num_uses=1`) and short-TTL.

## IOCs
| Type | Value |
|---|---|
| Attacker Source IP | `203.0.2.X` |
| Gitea Account Used | `svc-cicd` |
| Targeted Repo | `svc-cicd/pul-infra-config` |
| Targeted Commit | Commit containing `.env` with `VAULT_ROLE_ID` and `VAULT_SECRET_ID` |
| Compromised Secrets | Vault AppRole Role ID + Secret ID |
