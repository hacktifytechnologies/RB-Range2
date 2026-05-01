#!/usr/bin/env bash
# =============================================================================
# M2 — itops-git | setup.sh  (v4 — definitive)
# Challenge: Secret Credential Committed to Git History (Gitea)
# Range: RNG-IT-02 | OPERATION GRIDFALL
# Ubuntu 22.04 LTS | No internet required — run deps.sh first.
#
# Root-cause fix:
#   Previous versions tried sqlite3 INSERT into Gitea's repository table.
#   Gitea 1.21 has 50+ required columns — a partial INSERT creates a corrupt
#   record that Gitea ignores at query time, so the repo never appears.
#
#   Correct approach:
#     1. Build the seeded git repo locally (mktemp dir)
#     2. Create the Gitea repo via REST API with auto_init=true
#        → Gitea writes a complete, valid DB record with all columns
#     3. Force-push our seeded commits via HTTP
#        → overwrites the auto-init commit; all 4 commits land in Gitea
#     4. Verify via API and git clone
#   No sqlite3 manipulation at all.
# =============================================================================
set -euo pipefail

GITEA_USER="git"
GITEA_HOME="/opt/gitea"
GITEA_DATA="${GITEA_HOME}/data"
GITEA_REPOS="${GITEA_DATA}/repositories"
GITEA_PORT=3000
GITEA_URL="http://127.0.0.1:${GITEA_PORT}"
LOG_DIR="/var/log/pul-git"
SERVICE_NAME="pul-gitea"

# Credentials — URL-encoded versions needed for git remote URLs
SVC_USER="svc-cicd"
SVC_PASS="CICD@Deploy!2024"
SVC_PASS_ENC="CICD%40Deploy%212024"   # @ → %40, ! → %21
ADMIN_USER="gitadmin"
ADMIN_PASS="GitAdmin@PUL2024!"

echo "============================================================"
echo "  RNG-IT-02 | M2-itops-git | Challenge Setup (v4)"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"

if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
command -v gitea >/dev/null 2>&1 || { echo "[!] gitea not found. Run deps.sh first." >&2; exit 1; }
command -v git   >/dev/null 2>&1 || { echo "[!] git not found. Run deps.sh first." >&2; exit 1; }

# ── Directories ───────────────────────────────────────────────────────────────
mkdir -p "${GITEA_DATA}"/{repositories,custom,log,tmp} "${LOG_DIR}"

# ── Create git system user ────────────────────────────────────────────────────
if ! id -u "${GITEA_USER}" &>/dev/null; then
    useradd --system --home-dir "${GITEA_HOME}" --shell /bin/bash \
            --comment "Gitea Service" "${GITEA_USER}"
    echo "[+] Created system user: ${GITEA_USER}"
fi

# ── Gitea app.ini ─────────────────────────────────────────────────────────────
HOST_IP=$(hostname -I | awk '{print $1}')
mkdir -p "${GITEA_HOME}/custom/conf"

cat > "${GITEA_HOME}/custom/conf/app.ini" << EOF
APP_NAME = Prabal Urja Limited — Internal DevOps Portal
RUN_USER = ${GITEA_USER}
RUN_MODE = prod

[server]
DOMAIN           = ${HOST_IP}
HTTP_PORT        = ${GITEA_PORT}
ROOT_URL         = http://${HOST_IP}:${GITEA_PORT}/
DISABLE_SSH      = true
START_SSH_SERVER = false
OFFLINE_MODE     = true

[database]
DB_TYPE  = sqlite3
PATH     = ${GITEA_DATA}/gitea.db

[repository]
ROOT = ${GITEA_REPOS}

[security]
INSTALL_LOCK       = true
SECRET_KEY         = gridfall-pul-secret-$(openssl rand -hex 16)
INTERNAL_TOKEN     = $(openssl rand -hex 32)

[service]
DISABLE_REGISTRATION = false
REQUIRE_SIGNIN_VIEW  = false
ENABLE_NOTIFY_MAIL   = false

[log]
MODE      = file
LEVEL     = info
ROOT_PATH = ${GITEA_HOME}/log

[admin]
DISABLE_REGULAR_ORG_CREATION = false
EOF

chown -R "${GITEA_USER}:${GITEA_USER}" "${GITEA_HOME}"
chmod -R 750 "${GITEA_HOME}"

# ── Systemd service ───────────────────────────────────────────────────────────
cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Prabal Urja Limited — Internal Git Service (Gitea)
After=network.target

[Service]
Type=simple
User=${GITEA_USER}
Group=${GITEA_USER}
WorkingDirectory=${GITEA_HOME}
ExecStart=/usr/local/bin/gitea web --config ${GITEA_HOME}/custom/conf/app.ini
Restart=on-failure
RestartSec=5
Environment=HOME=${GITEA_HOME}
Environment=GITEA_WORK_DIR=${GITEA_HOME}
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}" --quiet
systemctl restart "${SERVICE_NAME}"

# ── Wait for Gitea HTTP to be ready ──────────────────────────────────────────
echo "[*] Waiting for Gitea to become ready..."
for i in $(seq 1 40); do
    if curl -sf "${GITEA_URL}/api/v1/version" -o /dev/null 2>/dev/null; then
        echo "[+] Gitea ready after ${i}s."; break
    fi
    [[ $i -eq 40 ]] && { echo "[!] Gitea not ready after 40s." >&2; journalctl -u "${SERVICE_NAME}" -n 20 --no-pager >&2; exit 1; }
    sleep 1
done

# ── Helper: run gitea CLI as git user with correct env ───────────────────────
gitea_cli() {
    GITEA_WORK_DIR="${GITEA_HOME}" HOME="${GITEA_HOME}" \
    su -s /bin/bash "${GITEA_USER}" -c \
        "GITEA_WORK_DIR=${GITEA_HOME} HOME=${GITEA_HOME} \
         gitea admin user create \
           --config ${GITEA_HOME}/custom/conf/app.ini \
           $* 2>&1" || true
}

# ── Create Gitea users ────────────────────────────────────────────────────────
echo "[*] Creating Gitea users..."
gitea_cli --username "${ADMIN_USER}" --password "${ADMIN_PASS}" \
          --email gitadmin@prabalurja.in --admin --must-change-password=false

gitea_cli --username "${SVC_USER}" --password "${SVC_PASS}" \
          --email svc-cicd@prabalurja.in --must-change-password=false

# Confirm svc-cicd is in Gitea
SVC_CHECK=$(curl -sf -u "${SVC_USER}:${SVC_PASS}" \
    "${GITEA_URL}/api/v1/user" 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('login','FAIL'))" \
    2>/dev/null || echo "FAIL")
[[ "${SVC_CHECK}" == "${SVC_USER}" ]] || {
    echo "[!] svc-cicd not responding to API auth — cannot continue." >&2; exit 1
}
echo "[+] svc-cicd confirmed."

# ── Build the seeded git repo in a temp dir ───────────────────────────────────
echo "[*] Building seeded repository commits..."
REPO_DIR=$(mktemp -d)
cd "${REPO_DIR}"
git init -q -b master 2>/dev/null || { git init -q; git checkout -b master 2>/dev/null || true; }
git config user.email "svc-deploy@prabalurja.in"
git config user.name  "PUL Deployment Automation"

# ── COMMIT 1 — Initial infrastructure files ───────────────────────────────────
mkdir -p ansible vault/policies scripts

cat > README.md << 'EOF'
# PUL Infrastructure Configuration Repository
Managed by: IT Infrastructure Team, Prabal Urja Limited
Reference: PUL-DEVOPS-0021

This repository contains Ansible playbooks, Vault policies,
and deployment scripts for the PUL NEXUS-IT platform.

## Structure
- `ansible/`  — Playbooks and inventory
- `vault/`    — HashiCorp Vault policy definitions
- `scripts/`  — Utility and maintenance scripts
EOF

cat > ansible/inventory.ini << 'EOF'
[webservers]
203.0.2.10 ansible_user=deploy
203.0.2.20 ansible_user=deploy

[monitoring]
203.0.2.40 ansible_user=monitor

[vault]
203.0.2.30 ansible_user=deploy
EOF

cat > ansible/deploy-base.yml << 'EOF'
---
- name: PUL Base Infrastructure Deployment
  hosts: all
  become: yes
  roles:
    - common
    - security-hardening
    - monitoring-agent
EOF

cat > vault/policies/svc-cicd-policy.hcl << 'EOF'
# CI/CD Pipeline Vault Policy
path "secret/pul/cicd/*" {
  capabilities = ["read"]
}
path "secret/pul/deploy/*" {
  capabilities = ["read", "list"]
}
EOF

cat > scripts/health-check.sh << 'EOF'
#!/bin/bash
# PUL Infrastructure Health Check
for host in 203.0.2.10 203.0.2.20 203.0.2.30 203.0.2.40; do
    ping -c1 -W1 "$host" &>/dev/null && echo "[OK] $host" || echo "[FAIL] $host"
done
EOF

git add -A
git commit -q -m "Initial commit: base infrastructure configuration"

# ── COMMIT 2 — THE VULNERABILITY: Vault AppRole creds committed in .env ───────
cat > .env << 'EOF'
# PUL Infrastructure Environment Configuration
# GENERATED BY: svc-deploy automation script
# DATE: 2024-09-12

# Application settings
APP_ENV=production
APP_PORT=8080
APP_LOG_LEVEL=info

# HashiCorp Vault — AppRole credentials
# Used by CI/CD pipeline to fetch secrets at deploy time
VAULT_ADDR=http://203.0.2.30:8200
VAULT_ROLE_ID=pul-cicd-role-7a3f9b2c1d4e
VAULT_SECRET_ID=3b8f2a1c-9d4e-7f6a-2b1c-8d3f9a7e4b2c

# Database (read-only replica for reporting)
DB_HOST=203.0.2.15
DB_PORT=5432
DB_NAME=pul_operations
DB_USER=pul_readonly
DB_PASS=ReadOnly@PUL!2024

# Monitoring
PROMETHEUS_ENDPOINT=http://203.0.2.40:9090
GRAFANA_API_KEY=glsa_PULgrafana2024AdminKey_a3b7c9d2
EOF

git add .env
git commit -q -m "Add deployment environment configuration with Vault AppRole credentials"

# ── COMMIT 3 — "Delete" the .env (too late — it lives in git history forever) ─
echo "# ENV vars moved to Vault secrets — do not commit .env" > .env
git add .env
git commit -q -m "Remove .env from tracking — credentials migrated to Vault"

# ── COMMIT 4 — Normal work continues ─────────────────────────────────────────
cat > ansible/vault-integration.yml << 'EOF'
---
- name: Configure Vault Integration
  hosts: all
  become: yes
  vars:
    vault_addr: "http://203.0.2.30:8200"
  tasks:
    - name: Install Vault agent
      apt:
        name: vault
        state: present
EOF

git add -A
git commit -q -m "Add Vault integration playbook for secret management"

echo "[+] Seeded repo: $(git log --oneline | wc -l) commits in temp dir."

# ── Create Gitea repo via API ─────────────────────────────────────────────────
# Strategy:
#   - If repo already exists in Gitea → delete it first (clean slate)
#   - Create with auto_init=true → Gitea writes a complete, valid DB record
#   - Force-push our 4 seeded commits → overwrites the auto-init empty commit
# This avoids ALL sqlite3 manipulation.
echo "[*] Setting up Gitea repository via API..."

# Delete existing repo if present (idempotent)
EXISTING_ID=$(curl -sf \
    -u "${SVC_USER}:${SVC_PASS}" \
    "${GITEA_URL}/api/v1/repos/${SVC_USER}/pul-infra-config" 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" \
    2>/dev/null || true)

if [[ -n "${EXISTING_ID}" && "${EXISTING_ID}" != "null" ]]; then
    echo "[~] Existing repo found (id=${EXISTING_ID}) — deleting for clean re-create..."
    curl -sf -X DELETE \
        -u "${SVC_USER}:${SVC_PASS}" \
        "${GITEA_URL}/api/v1/repos/${SVC_USER}/pul-infra-config" 2>/dev/null || true
    sleep 1
fi

# Also remove any leftover bare repo on disk so Gitea can create fresh
BARE_PATH="${GITEA_REPOS}/${SVC_USER}/pul-infra-config.git"
if [[ -d "${BARE_PATH}" ]]; then
    echo "[~] Removing stale bare repo on disk..."
    rm -rf "${BARE_PATH}"
fi

# Create repo via API — auto_init=true so Gitea populates ALL DB columns correctly
echo "[*] Creating repository via Gitea API (auto_init=true)..."
CREATE_RESP=$(curl -sf -X POST \
    -u "${SVC_USER}:${SVC_PASS}" \
    "${GITEA_URL}/api/v1/user/repos" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"pul-infra-config\",
        \"description\": \"PUL Infrastructure Configuration — INTERNAL\",
        \"private\": true,
        \"auto_init\": true,
        \"default_branch\": \"master\"
    }" 2>/dev/null || true)

REPO_ID=$(echo "${CREATE_RESP}" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" \
    2>/dev/null || true)

if [[ -z "${REPO_ID}" || "${REPO_ID}" == "null" ]]; then
    echo "[!] Repository creation via API failed." >&2
    echo "    Response: ${CREATE_RESP}" >&2
    exit 1
fi
echo "[+] Repository created in Gitea (id=${REPO_ID})."
sleep 1   # give Gitea a moment to finish writing

# ── Force-push our seeded commits ────────────────────────────────────────────
# The auto_init created an empty commit on master. We force-push to replace it
# with our 4 seeded commits including the vulnerability commit.
echo "[*] Pushing seeded commits to Gitea..."
cd "${REPO_DIR}"
git remote add origin \
    "http://${SVC_USER}:${SVC_PASS_ENC}@127.0.0.1:${GITEA_PORT}/${SVC_USER}/pul-infra-config.git"

# Force push — replaces the auto-init commit with our 4 commits
git push -f origin master 2>&1 | sed 's/^/    /'

echo "[+] Push complete."

# Clean up temp dir
cd /
rm -rf "${REPO_DIR}"

# ── Firewall ──────────────────────────────────────────────────────────────────
if command -v ufw &>/dev/null; then
    ufw allow "${GITEA_PORT}/tcp" comment "Gitea M2 challenge" >/dev/null 2>&1 || true
fi

# ── Verification ──────────────────────────────────────────────────────────────
echo ""
echo "[*] Running post-setup verification..."
sleep 2

# 1. Service
if systemctl is-active --quiet "${SERVICE_NAME}"; then
    echo "[✓] Gitea service: running"
else
    echo "[✗] Gitea service: NOT running" >&2
fi

# 2. Auth
AUTH_OK=$(curl -sf -u "${SVC_USER}:${SVC_PASS}" \
    "${GITEA_URL}/api/v1/user" 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('login','FAIL'))" \
    2>/dev/null || echo "FAIL")
[[ "${AUTH_OK}" == "${SVC_USER}" ]] && echo "[✓] svc-cicd auth: OK" \
                                    || echo "[✗] svc-cicd auth: FAILED" >&2

# 3. Repo visible via API
REPO_FULL=$(curl -sf \
    -u "${SVC_USER}:${SVC_PASS}" \
    "${GITEA_URL}/api/v1/repos/${SVC_USER}/pul-infra-config" 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('full_name','FAIL'))" \
    2>/dev/null || echo "FAIL")
[[ "${REPO_FULL}" == "${SVC_USER}/pul-infra-config" ]] \
    && echo "[✓] Repository visible: ${REPO_FULL}" \
    || echo "[✗] Repository NOT visible via API" >&2

# 4. Commit count via API
COMMIT_COUNT=$(curl -sf \
    -u "${SVC_USER}:${SVC_PASS}" \
    "${GITEA_URL}/api/v1/repos/${SVC_USER}/pul-infra-config/commits?limit=10" 2>/dev/null \
    | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" \
    2>/dev/null || echo "0")
[[ "${COMMIT_COUNT}" -ge 4 ]] \
    && echo "[✓] Git history: ${COMMIT_COUNT} commits found" \
    || echo "[✗] Git history: only ${COMMIT_COUNT} commits (expected 4)" >&2

# 5. Vulnerability commit contains VAULT_ROLE_ID
SECRET_COMMIT=$(curl -sf \
    -u "${SVC_USER}:${SVC_PASS}" \
    "${GITEA_URL}/api/v1/repos/${SVC_USER}/pul-infra-config/commits?limit=10" 2>/dev/null \
    | python3 -c "
import sys, json
commits = json.load(sys.stdin)
for c in commits:
    if 'deployment environment' in c.get('commit',{}).get('message','').lower():
        print(c['sha'][:8])
        break
" 2>/dev/null || true)

if [[ -n "${SECRET_COMMIT}" ]]; then
    # Check raw file content at that commit
    HAS_CRED=$(curl -sf \
        -u "${SVC_USER}:${SVC_PASS}" \
        "${GITEA_URL}/api/v1/repos/${SVC_USER}/pul-infra-config/raw/.env?ref=${SECRET_COMMIT}" \
        2>/dev/null | grep -c "VAULT_ROLE_ID" || echo "0")
    [[ "${HAS_CRED}" -ge 1 ]] \
        && echo "[✓] Vulnerability commit verified: ${SECRET_COMMIT} contains VAULT_ROLE_ID" \
        || echo "[✗] Commit ${SECRET_COMMIT} found but .env missing VAULT_ROLE_ID" >&2
else
    echo "[✗] Could not locate vulnerability commit in history" >&2
fi

echo ""
echo "============================================================"
echo "  M2 Setup Complete (v4)"
echo "  Gitea URL     : http://${HOST_IP}:${GITEA_PORT}"
echo "  Player login  : ${SVC_USER} / ${SVC_PASS}"
echo "  Admin login   : ${ADMIN_USER} / ${ADMIN_PASS}"
echo "  Target repo   : ${SVC_USER}/pul-infra-config (private)"
echo ""
echo "  EXPLOIT:"
echo "  git clone http://${SVC_USER}:${SVC_PASS_ENC}@${HOST_IP}:${GITEA_PORT}/${SVC_USER}/pul-infra-config.git"
echo "  git log --oneline"
echo "  git show <second-commit-hash>:.env"
echo ""
echo "  PIVOT ARTIFACT:"
echo "  VAULT_ROLE_ID=pul-cicd-role-7a3f9b2c1d4e"
echo "  VAULT_SECRET_ID=3b8f2a1c-9d4e-7f6a-2b1c-8d3f9a7e4b2c"
echo "  → http://203.0.2.30:8200 (Vault — M3)"
echo "============================================================"
