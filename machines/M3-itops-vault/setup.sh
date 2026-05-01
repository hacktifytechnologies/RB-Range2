#!/usr/bin/env bash
# =============================================================================
# M3 — itops-vault | setup.sh
# Challenge: Vault Dev Mode — Root Token Leaked via systemd journal
#            AppRole login → read secret/pul/ad → AD pivot credential
# Range: RNG-IT-02 | OPERATION GRIDFALL
# Ubuntu 22.04 LTS
# =============================================================================
set -euo pipefail

VAULT_USER="vault"
VAULT_HOME="/opt/vault"
VAULT_LOG="/var/log/pul-vault"
VAULT_PORT=8200
VAULT_ROOT_TOKEN="pul-vault-root-s3cr3t-2024-gridfall"
SERVICE_NAME="pul-vault"

echo "============================================================"
echo "  RNG-IT-02 | M3-itops-vault | Challenge Setup"
echo "============================================================"

if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
command -v vault >/dev/null 2>&1 || { echo "[!] vault not found. Run deps.sh first." >&2; exit 1; }

# System user
if ! id -u "${VAULT_USER}" &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin \
            --comment "HashiCorp Vault" "${VAULT_USER}"
fi
mkdir -p "${VAULT_HOME}" "${VAULT_LOG}"
chown "${VAULT_USER}:${VAULT_USER}" "${VAULT_HOME}" "${VAULT_LOG}"

# Vault configuration
cat > "${VAULT_HOME}/vault.hcl" << EOF
storage "inmem" {}

listener "tcp" {
  address     = "0.0.0.0:${VAULT_PORT}"
  tls_disable = "true"
}

ui            = true
api_addr      = "http://0.0.0.0:${VAULT_PORT}"
cluster_addr  = "http://127.0.0.1:8201"
log_level     = "info"
EOF

# ── Systemd service — VULNERABILITY: root token in env (leaks to journal) ────
cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Prabal Urja Limited — HashiCorp Vault Secret Management
After=network.target

[Service]
Type=simple
User=${VAULT_USER}
Group=${VAULT_USER}
WorkingDirectory=${VAULT_HOME}
ExecStart=/usr/local/bin/vault server -config=${VAULT_HOME}/vault.hcl -dev -dev-root-token-id=${VAULT_ROOT_TOKEN}
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}
Environment=VAULT_DEV_ROOT_TOKEN_ID=${VAULT_ROOT_TOKEN}
Environment=VAULT_ADDR=http://127.0.0.1:${VAULT_PORT}
Environment=HOME=${VAULT_HOME}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}" --quiet
systemctl restart "${SERVICE_NAME}"
sleep 4

# Verify Vault is up
export VAULT_ADDR="http://127.0.0.1:${VAULT_PORT}"
export VAULT_TOKEN="${VAULT_ROOT_TOKEN}"

vault status >/dev/null 2>&1 || { echo "[!] Vault not responding." >&2; exit 1; }
echo "[+] Vault running."

# ── Enable AppRole auth ───────────────────────────────────────────────────────
vault auth enable approle 2>/dev/null || true

# ── Create policies ───────────────────────────────────────────────────────────
vault policy write pul-cicd-policy - << 'POLICY'
path "secret/pul/cicd/*" { capabilities = ["read","list"] }
path "secret/pul/deploy/*" { capabilities = ["read","list"] }
POLICY

vault policy write pul-monitor-policy - << 'POLICY'
path "secret/pul/monitoring/*" { capabilities = ["read"] }
POLICY

# ── Create AppRole for svc-cicd (matches git-history credentials) ─────────────
vault write auth/approle/role/pul-cicd \
    policies="pul-cicd-policy" \
    secret_id_ttl=0 \
    token_ttl=1h \
    token_max_ttl=4h

# Force specific role-id and secret-id to match planted git artifact
vault write auth/approle/role/pul-cicd/role-id \
    role_id="pul-cicd-role-7a3f9b2c1d4e" 2>/dev/null || true

vault write -f auth/approle/role/pul-cicd/secret-id \
    secret_id="3b8f2a1c-9d4e-7f6a-2b1c-8d3f9a7e4b2c" 2>/dev/null || true

# ── Seed secrets — THE CHALLENGE OBJECTIVE ───────────────────────────────────
vault kv put secret/pul/ad \
    domain="corp.prabalurja.in" \
    dc_host="203.x.x.x" \
    dc_port="389" \
    bind_dn="CN=svc-monitor,CN=Users,DC=corp,DC=prabalurja,DC=in" \
    bind_pass="M0n!tor@PUL24" \
    description="IT Operations AD service account — monitoring and reporting access" \
    pivot_note="Prometheus metrics portal: 203.x.x.x:9090"

vault kv put secret/pul/cicd/pipeline \
    gitea_url="http://203.x.x.x:3000" \
    deploy_user="svc-deploy" \
    deploy_key_fingerprint="SHA256:pul-deploy-2024-ed25519" \
    registry_url="registry.prabalurja.in:5000"

vault kv put secret/pul/monitoring/grafana \
    admin_pass="Grafana@PUL2024!" \
    grafana_url="http://203.x.x.x:3000" \
    api_key="glsa_PULgrafana2024AdminKey_a3b7c9d2"

vault kv put secret/pul/deploy/ansible \
    vault_pass_path="/etc/ansible/.vault_pass" \
    awx_url="http://203.x.x.x:8080" \
    awx_token="awx-pul-token-a3b7c9d2e1f4a5b6"

# ── Firewall ──────────────────────────────────────────────────────────────────
if command -v ufw &>/dev/null; then
    ufw allow "${VAULT_PORT}/tcp" comment "Vault M3 challenge" >/dev/null 2>&1 || true
fi

echo ""
echo "============================================================"
echo "  M3 Setup Complete"
echo "  Vault URL    : http://$(hostname -I | awk '{print $1}'):${VAULT_PORT}"
echo "  Root Token   : ${VAULT_ROOT_TOKEN} (LEAKED via journal)"
echo "  AppRole      : role=pul-cicd-role-7a3f9b2c1d4e"
echo "  Key Secret   : secret/pul/ad → svc-monitor AD cred"
echo "  Journal leak : journalctl -u ${SERVICE_NAME} | grep root-token"
echo "  Service      : systemctl status ${SERVICE_NAME}"
echo "============================================================"
