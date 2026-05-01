#!/usr/bin/env bash
# M4 — itops-monitor | setup.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_USER="pulmonitor"; APP_DIR="/opt/pul-monitor"; LOG_DIR="/var/log/pul-monitor"; APP_PORT=9090; SERVICE_NAME="pul-monitor"
echo "============================================================"
echo "  RNG-IT-02 | M4-itops-monitor | Challenge Setup"
echo "============================================================"
if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
command -v python3 >/dev/null 2>&1 || { echo "[!] python3 not found. Run deps.sh first." >&2; exit 1; }

if ! id -u "${APP_USER}" &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "${APP_USER}"
fi

mkdir -p "${APP_DIR}/app/templates" "${LOG_DIR}"
cp -r "${SCRIPT_DIR}/app/"* "${APP_DIR}/app/"
chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}" "${LOG_DIR}"
chmod -R 750 "${APP_DIR}"; chmod 770 "${LOG_DIR}"
chmod +x "${APP_DIR}/app/app.py"
touch "${LOG_DIR}/monitor.log"
chown "${APP_USER}:${APP_USER}" "${LOG_DIR}/monitor.log"
chmod 640 "${LOG_DIR}/monitor.log"

cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Prabal Urja Limited — Internal Monitoring Portal (M4)
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
    echo "[+] Monitoring portal running on port ${APP_PORT}."
else
    echo "[!] Service failed. Check: journalctl -u ${SERVICE_NAME} -n 20" >&2; exit 1
fi

if command -v ufw &>/dev/null; then
    ufw allow "${APP_PORT}/tcp" comment "Monitor M4 challenge" >/dev/null 2>&1 || true
fi

echo ""
echo "============================================================"
echo "  M4 Setup Complete"
echo "  Portal URL   : http://$(hostname -I | awk '{print $1}'):${APP_PORT}"
echo "  Login        : svc-monitor / M0n!tor@PUL24"
echo "  Vuln Endpoint: http://<IP>:${APP_PORT}/metrics (no auth)"
echo "  Credential   : devops-admin:DevOps@PUL!24 (in /metrics labels)"
echo "  Pivot Target : 203.x.x.x:8080 (Ansible AWX — M5)"
echo "  Service      : systemctl status ${SERVICE_NAME}"
echo "============================================================"
