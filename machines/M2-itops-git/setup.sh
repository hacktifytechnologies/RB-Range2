#!/usr/bin/env bash
# =============================================================================
# M2 — itops-git | setup.sh
# Challenge: Secret Credential Committed to Git History (Gitea)
# Range: RNG-IT-02 | OPERATION GRIDFALL
# Ubuntu 22.04 LTS | No internet required — run deps.sh first.
# =============================================================================
set -euo pipefail

GITEA_USER="git"
GITEA_HOME="/opt/gitea"
GITEA_DATA="${GITEA_HOME}/data"
GITEA_REPOS="${GITEA_DATA}/repositories"
GITEA_PORT=3000
LOG_DIR="/var/log/pul-git"
SERVICE_NAME="pul-gitea"

echo "============================================================"
echo "  RNG-IT-02 | M2-itops-git | Challenge Setup"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"

if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
command -v gitea >/dev/null 2>&1 || { echo "[!] gitea not found. Run deps.sh first." >&2; exit 1; }

mkdir -p "${GITEA_DATA}"/{repositories,custom,log,tmp} "${LOG_DIR}"

# ── Create git system user ────────────────────────────────────────────────────
if ! id -u "${GITEA_USER}" &>/dev/null; then
    useradd --system --home-dir "${GITEA_HOME}" --shell /bin/bash \
            --comment "Gitea Service" "${GITEA_USER}"
fi

# ── Gitea app.ini configuration ───────────────────────────────────────────────
mkdir -p "${GITEA_HOME}/custom/conf"
cat > "${GITEA_HOME}/custom/conf/app.ini" << EOF
APP_NAME = Prabal Urja Limited — Internal DevOps Portal
RUN_USER = ${GITEA_USER}
RUN_MODE = prod

[server]
DOMAIN           = 203.x.x.x
HTTP_PORT        = ${GITEA_PORT}
ROOT_URL         = http://203.x.x.x:${GITEA_PORT}/
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
Environment=HOME=${GITEA_HOME} GITEA_WORK_DIR=${GITEA_HOME}
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}" --quiet
systemctl start "${SERVICE_NAME}"
sleep 5

# ── Create admin and svc-cicd users via Gitea CLI ────────────────────────────
echo "[*] Creating Gitea admin user..."
su -s /bin/bash "${GITEA_USER}" -c "
    gitea admin user create \
        --config ${GITEA_HOME}/custom/conf/app.ini \
        --username gitadmin \
        --password 'GitAdmin@PUL2024!' \
        --email gitadmin@prabalurja.in \
        --admin \
        --must-change-password=false 2>/dev/null || true
"

echo "[*] Creating svc-cicd user..."
su -s /bin/bash "${GITEA_USER}" -c "
    gitea admin user create \
        --config ${GITEA_HOME}/custom/conf/app.ini \
        --username svc-cicd \
        --password 'CICD@Deploy!2024' \
        --email svc-cicd@prabalurja.in \
        --must-change-password=false 2>/dev/null || true
"

# ── Create and seed the pul-infra-config repository ──────────────────────────
echo "[*] Seeding pul-infra-config repository with challenge artefacts..."
REPO_DIR=$(mktemp -d)
cd "${REPO_DIR}"
git init
git config user.email "svc-deploy@prabalurja.in"
git config user.name  "PUL Deployment Automation"

# COMMIT 1 — Initial infrastructure files
mkdir -p ansible vault scripts
cat > README.md << 'README'
# PUL Infrastructure Configuration Repository
Managed by: IT Infrastructure Team, Prabal Urja Limited
Reference: PUL-DEVOPS-0021

This repository contains Ansible playbooks, Vault policies,
and deployment scripts for the PUL NEXUS-IT platform.

## Structure
- `ansible/`  — Playbooks and inventory
- `vault/`    — HashiCorp Vault policy definitions
- `scripts/`  — Utility and maintenance scripts
README

cat > ansible/inventory.ini << 'INI'
[webservers]
203.x.x.x ansible_user=deploy
203.x.x.x ansible_user=deploy

[monitoring]
203.x.x.x ansible_user=monitor

[vault]
203.x.x.x ansible_user=deploy
INI

cat > ansible/deploy-base.yml << 'YAML'
---
- name: PUL Base Infrastructure Deployment
  hosts: all
  become: yes
  roles:
    - common
    - security-hardening
    - monitoring-agent
YAML

cat > vault/policies/svc-cicd-policy.hcl << 'HCL'
# CI/CD Pipeline Vault Policy
path "secret/pul/cicd/*" {
  capabilities = ["read"]
}
path "secret/pul/deploy/*" {
  capabilities = ["read", "list"]
}
HCL

cat > scripts/health-check.sh << 'SH'
#!/bin/bash
# PUL Infrastructure Health Check
for host in 203.x.x.x 203.x.x.x 203.x.x.x 203.x.x.x; do
    ping -c1 -W1 "$host" &>/dev/null && echo "[OK] $host" || echo "[FAIL] $host"
done
SH

git add -A
git commit -m "Initial commit: base infrastructure configuration"

# COMMIT 2 — Add .env with secrets (THE VULNERABILITY COMMIT)
cat > .env << 'ENV'
# PUL Infrastructure Environment Configuration
# GENERATED BY: svc-deploy automation script
# DATE: 2024-09-12

# Application settings
APP_ENV=production
APP_PORT=8080
APP_LOG_LEVEL=info

# HashiCorp Vault — AppRole credentials
# Used by CI/CD pipeline to fetch secrets at deploy time
VAULT_ADDR=http://203.x.x.x:8200
VAULT_ROLE_ID=pul-cicd-role-7a3f9b2c1d4e
VAULT_SECRET_ID=3b8f2a1c-9d4e-7f6a-2b1c-8d3f9a7e4b2c

# Database (read-only replica for reporting)
DB_HOST=203.x.x.x
DB_PORT=5432
DB_NAME=pul_operations
DB_USER=pul_readonly
DB_PASS=ReadOnly@PUL!2024

# Monitoring
PROMETHEUS_ENDPOINT=http://203.x.x.x:9090
GRAFANA_API_KEY=glsa_PULgrafana2024AdminKey_a3b7c9d2
ENV

git add .env
git commit -m "Add deployment environment configuration with Vault AppRole credentials"

# COMMIT 3 — "Delete" the .env (too late — it's in history)
echo "# ENV vars moved to Vault secrets — do not commit .env" > .env
git add .env
git commit -m "Remove .env from tracking — credentials migrated to Vault"

# COMMIT 4 — More infrastructure work
cat > ansible/vault-integration.yml << 'YAML'
---
- name: Configure Vault Integration
  hosts: all
  become: yes
  vars:
    vault_addr: "http://203.x.x.x:8200"
  tasks:
    - name: Install Vault agent
      apt:
        name: vault
        state: present
YAML

git add -A
git commit -m "Add Vault integration playbook for secret management"

# ── Push repo to Gitea via filesystem (bypass API for reliability) ────────────
GITEA_REPO_PATH="${GITEA_REPOS}/svc-cicd/pul-infra-config.git"
mkdir -p "$(dirname "${GITEA_REPO_PATH}")"
git clone --bare "${REPO_DIR}" "${GITEA_REPO_PATH}"
chown -R "${GITEA_USER}:${GITEA_USER}" "${GITEA_REPO_PATH}"

# Register repo in Gitea DB (sqlite3)
sleep 2
GITEA_DB="${GITEA_DATA}/gitea.db"
if [[ -f "${GITEA_DB}" ]]; then
    # Get user ID for svc-cicd
    SVC_ID=$(sqlite3 "${GITEA_DB}" "SELECT id FROM user WHERE name='svc-cicd';" 2>/dev/null || echo "2")
    sqlite3 "${GITEA_DB}" << SQLEOF 2>/dev/null || true
INSERT OR IGNORE INTO repository
  (owner_id, owner_name, name, lower_name, description, is_private, num_commits, created_unix, updated_unix)
VALUES
  (${SVC_ID:-2}, 'svc-cicd', 'pul-infra-config', 'pul-infra-config',
   'PUL Infrastructure Configuration — INTERNAL', 1, 4,
   strftime('%s','now'), strftime('%s','now'));
SQLEOF
fi

# Clean up
rm -rf "${REPO_DIR}"

# ── Firewall ──────────────────────────────────────────────────────────────────
if command -v ufw &>/dev/null; then
    ufw allow "${GITEA_PORT}/tcp" comment "Gitea M2 challenge" >/dev/null 2>&1 || true
fi

echo ""
echo "============================================================"
echo "  M2 Setup Complete"
echo "  Gitea URL    : http://$(hostname -I | awk '{print $1}'):${GITEA_PORT}"
echo "  Credentials  : svc-cicd / CICD@Deploy!2024"
echo "  Target Repo  : pul-infra-config"
echo "  Secret       : .env committed in git history (commit 2)"
echo "  Vault AppRole: VAULT_ROLE_ID + VAULT_SECRET_ID in .env"
echo "  Service      : systemctl status ${SERVICE_NAME}"
echo "============================================================"
