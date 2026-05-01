#!/usr/bin/env bash
# =============================================================================
# M5 — itops-ansible | setup.sh
# Challenge: Ansible Vault Password + SSH Private Key Leaked in AWX Job Output
# Range: RNG-IT-02 | OPERATION GRIDFALL
# Ubuntu 22.04 LTS | No internet required — run deps.sh first.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_USER="pulawx"
APP_DIR="/opt/pul-awx"
LOG_DIR="/var/log/pul-ansible"
APP_PORT=8080
SERVICE_NAME="pul-awx"

echo "============================================================"
echo "  RNG-IT-02 | M5-itops-ansible | Challenge Setup"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"

if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
command -v python3 >/dev/null 2>&1 || { echo "[!] python3 not found. Run deps.sh first." >&2; exit 1; }

# ── System user ───────────────────────────────────────────────────────────────
if ! id -u "${APP_USER}" &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin \
            --comment "PUL AWX Service" "${APP_USER}"
fi

# ── Directory structure ───────────────────────────────────────────────────────
mkdir -p "${APP_DIR}/app/templates" "${LOG_DIR}"
cp -r "${SCRIPT_DIR}/app/"* "${APP_DIR}/app/"
chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}" "${LOG_DIR}"
chmod -R 750 "${APP_DIR}"
chmod 770 "${LOG_DIR}"
touch "${LOG_DIR}/awx.log"
chown "${APP_USER}:${APP_USER}" "${LOG_DIR}/awx.log"

# ── Plant vault password file (referenced in job output) ──────────────────────
mkdir -p /etc/ansible
echo "Ansibl3Vault@PUL!GridFall2024" > /etc/ansible/.vault_pass
chmod 600 /etc/ansible/.vault_pass
chown root:root /etc/ansible/.vault_pass

# ── Plant encrypted vault.yml (group_vars) — matches file browser ─────────────
mkdir -p /opt/pul-infra-config/group_vars/all
# Simulate ansible-vault encrypted file (real encryption, readable format)
cat > /opt/pul-infra-config/group_vars/all/vault.yml << 'VAULTEOF'
$ANSIBLE_VAULT;1.1;AES256
62613661353736373835386665623630353962303933363661353264343835636433363337326166
6663373030386463373536666562383533306263363561620a376535393734376561333362633034
33303634646338626262393039353363303361343565383264383231326466363635306461336464
6339343562653036360a623265666539373765623864383565393534623233353832363530313864
[ EXERCISE PLACEHOLDER — Replace with real ansible-vault encrypt output in production ]
VAULTEOF
chmod 640 /opt/pul-infra-config/group_vars/all/vault.yml

# ── Systemd service ───────────────────────────────────────────────────────────
cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Prabal Urja Limited — Ansible Job Runner Portal (M5)
After=network.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/python3 ${APP_DIR}/app/app.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=${LOG_DIR}
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}" --quiet
systemctl restart "${SERVICE_NAME}"
sleep 2

if systemctl is-active --quiet "${SERVICE_NAME}"; then
    echo "[+] AWX portal running on port ${APP_PORT}."
else
    echo "[!] Service failed. Check: journalctl -u ${SERVICE_NAME} -n 20" >&2; exit 1
fi

# ── Firewall ──────────────────────────────────────────────────────────────────
if command -v ufw &>/dev/null; then
    ufw allow "${APP_PORT}/tcp" comment "AWX M5 challenge" >/dev/null 2>&1 || true
fi

echo ""
echo "============================================================"
echo "  M5 Setup Complete"
echo "  AWX URL      : http://$(hostname -I | awk '{print $1}'):${APP_PORT}"
echo "  Login        : devops-admin / DevOps@PUL!24"
echo "  Vuln Job     : JOB-20241115-018 (deploy-dev-infra)"
echo "  Vault Pass   : Ansibl3Vault@PUL!GridFall2024 (in job output)"
echo "  SSH Key      : In job output + file browser vault.yml"
echo "  Pivot Target : devops@dev-jump.prabalurja.in (11.x.x.x)"
echo "  Service      : systemctl status ${SERVICE_NAME}"
echo "============================================================"
