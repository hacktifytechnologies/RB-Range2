#!/usr/bin/env bash
# =============================================================================
# M3 — itops-vault | setup.sh
# Challenge: Vault Dev Mode — Root Token Leaked via systemd journal
#            AppRole login → read SSH creds → SSH as vault user
#            → journal/proc root token leak → read secret/pul/ad → AD pivot credential
# Range: RNG-IT-02 | OPERATION GRIDFALL
# Ubuntu 22.04 LTS
# =============================================================================

set -euo pipefail

VAULT_USER="vault"
VAULT_HOME="/opt/vault"
VAULT_LOG="/var/log/pul-vault"
VAULT_PORT=8600
VAULT_ROOT_TOKEN="pul-vault-root-s3cr3t-2024-gridfall"
SERVICE_NAME="pul-vault"

# SSH credential intentionally planted in Vault for challenge progression
VAULT_SSH_PASS='V@ult-ITOps!Gf24#9qZ'

echo "============================================================"
echo "  RNG-IT-02 | M3-itops-vault | Challenge Setup"
echo "============================================================"

if [[ "${EUID}" -ne 0 ]]; then
    echo "[!] Must be run as root." >&2
    exit 1
fi

if ! command -v vault >/dev/null 2>&1; then
    echo "[!] vault not found. Run deps.sh first." >&2
    exit 1
fi

# =============================================================================
# SSH SETUP — Ubuntu 22.04 uses service name: ssh
# =============================================================================

echo "[*] Checking SSH server package..."

if ! dpkg -s openssh-server >/dev/null 2>&1; then
    echo "[*] openssh-server not found. Installing..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server
else
    echo "[+] openssh-server already installed."
fi

echo "[*] Enabling password-based SSH login..."

mkdir -p /etc/ssh/sshd_config.d

# Make sure Ubuntu's SSH config loads drop-in files.
# On Ubuntu 22.04 this is usually already present, but we enforce it safely.
if ! grep -qE '^\s*Include\s+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
    sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
fi

cat > /etc/ssh/sshd_config.d/99-pul-vault-password-auth.conf << 'EOF'
PasswordAuthentication yes
KbdInteractiveAuthentication yes
UsePAM yes
EOF

# Also update direct values if the main config has them explicitly disabled.
sed -i 's/^[#[:space:]]*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config || true
sed -i 's/^[#[:space:]]*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/g' /etc/ssh/sshd_config || true
sed -i 's/^[#[:space:]]*UsePAM.*/UsePAM yes/g' /etc/ssh/sshd_config || true

systemctl enable ssh --quiet
systemctl restart ssh

if ! systemctl is-active --quiet ssh; then
    echo "[!] SSH service failed to start." >&2
    systemctl status ssh --no-pager
    exit 1
fi

echo "[+] SSH password authentication enabled using Ubuntu service: ssh"

# =============================================================================
# VAULT USER SETUP
# =============================================================================

echo "[*] Creating/configuring local SSH user: ${VAULT_USER}"

if ! getent group "${VAULT_USER}" >/dev/null 2>&1; then
    groupadd "${VAULT_USER}"
fi

if ! id -u "${VAULT_USER}" >/dev/null 2>&1; then
    useradd \
        --create-home \
        --home-dir "/home/${VAULT_USER}" \
        --shell /bin/bash \
        --gid "${VAULT_USER}" \
        --comment "HashiCorp Vault / IT Ops Operator" \
        "${VAULT_USER}"
else
    usermod \
        --home "/home/${VAULT_USER}" \
        --shell /bin/bash \
        --gid "${VAULT_USER}" \
        "${VAULT_USER}"

    mkdir -p "/home/${VAULT_USER}"
    chown "${VAULT_USER}:${VAULT_USER}" "/home/${VAULT_USER}"
fi

echo "${VAULT_USER}:${VAULT_SSH_PASS}" | chpasswd

# Make sure the account is not locked.
passwd -u "${VAULT_USER}" >/dev/null 2>&1 || true
usermod -U "${VAULT_USER}" >/dev/null 2>&1 || true

# Give the vault user journal access so the participant can read the service leak.
usermod -aG systemd-journal "${VAULT_USER}" 2>/dev/null || true
usermod -aG adm "${VAULT_USER}" 2>/dev/null || true

mkdir -p "${VAULT_HOME}" "${VAULT_LOG}"
chown "${VAULT_USER}:${VAULT_USER}" "${VAULT_HOME}" "${VAULT_LOG}"

echo "[+] User '${VAULT_USER}' configured with SSH password login."

# =============================================================================
# VAULT CONFIGURATION
# =============================================================================

echo "[*] Writing Vault configuration..."

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

chown "${VAULT_USER}:${VAULT_USER}" "${VAULT_HOME}/vault.hcl"

# =============================================================================
# SYSTEMD SERVICE — INTENTIONAL VULNERABILITY
# Root token is exposed through the service command/environment.
# =============================================================================

echo "[*] Creating vulnerable Vault service: ${SERVICE_NAME}"

cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
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

sleep 5

export VAULT_ADDR="http://127.0.0.1:${VAULT_PORT}"
export VAULT_TOKEN="${VAULT_ROOT_TOKEN}"

if ! vault status >/dev/null 2>&1; then
    echo "[!] Vault not responding." >&2
    systemctl status "${SERVICE_NAME}" --no-pager
    exit 1
fi

echo "[+] Vault is running."

# =============================================================================
# VAULT AUTH + POLICIES
# =============================================================================

echo "[*] Enabling AppRole auth..."

vault auth enable approle >/dev/null 2>&1 || true

echo "[*] Writing Vault policies..."

vault policy write pul-cicd-policy - << 'POLICY'
# KV v2 list permissions
path "secret/metadata" {
  capabilities = ["list"]
}

path "secret/metadata/pul" {
  capabilities = ["list"]
}

path "secret/metadata/pul/*" {
  capabilities = ["list"]
}

# Allow AppRole to read only selected paths.
path "secret/data/pul/cicd/*" {
  capabilities = ["read"]
}

path "secret/data/pul/deploy/*" {
  capabilities = ["read"]
}

path "secret/data/pul/creds/*" {
  capabilities = ["read"]
}

# KV v1 compatibility rules.
path "secret/pul/cicd/*" {
  capabilities = ["read", "list"]
}

path "secret/pul/deploy/*" {
  capabilities = ["read", "list"]
}

path "secret/pul/creds/*" {
  capabilities = ["read", "list"]
}
POLICY

vault policy write pul-monitor-policy - << 'POLICY'
path "secret/data/pul/monitoring/*" {
  capabilities = ["read"]
}

path "secret/metadata/pul/monitoring/*" {
  capabilities = ["list"]
}

path "secret/pul/monitoring/*" {
  capabilities = ["read", "list"]
}
POLICY

# =============================================================================
# APPROLE SETUP
# =============================================================================

echo "[*] Creating AppRole: pul-cicd"

vault write auth/approle/role/pul-cicd \
    policies="pul-cicd-policy" \
    secret_id_ttl=0 \
    token_ttl=1h \
    token_max_ttl=4h >/dev/null

vault write auth/approle/role/pul-cicd/role-id \
    role_id="pul-cicd-role-7a3f9b2c1d4e" >/dev/null

vault write auth/approle/role/pul-cicd/custom-secret-id \
    secret_id="3b8f2a1c-9d4e-7f6a-2b1c-8d3f9a7e4b2c" >/dev/null

echo "[+] AppRole configured."

# =============================================================================
# SEED VAULT SECRETS
# =============================================================================

HOST_IP="$(hostname -I | awk '{print $1}')"

echo "[*] Seeding Vault secrets..."

# New path requested:
# Participants use AppRole to read this, then SSH into the machine as vault.
vault kv put secret/pul/creds/vault-ssh \
    username="${VAULT_USER}" \
    password="${VAULT_SSH_PASS}" \
    host="${HOST_IP}" \
    port="22" \
    description="IT Ops Vault service account SSH credential" \
    note="Use this SSH access to inspect local Vault service logs and process environment" >/dev/null

# Main objective secret. AppRole should NOT be able to read this directly.
vault kv put secret/pul/ad \
    domain="corp.prabalurja.in" \
    dc_host="203.x.x.x" \
    dc_port="389" \
    bind_dn="CN=svc-monitor,CN=Users,DC=corp,DC=prabalurja,DC=in" \
    bind_pass="M0n!tor@PUL24" \
    description="IT Operations AD service account — monitoring and reporting access" \
    pivot_note="Prometheus metrics portal: 203.x.x.x:9090" >/dev/null

vault kv put secret/pul/cicd/pipeline \
    gitea_url="http://203.x.x.x:3000" \
    deploy_user="svc-deploy" \
    deploy_key_fingerprint="SHA256:pul-deploy-2024-ed25519" \
    registry_url="registry.prabalurja.in:5000" >/dev/null

vault kv put secret/pul/monitoring/grafana \
    admin_pass="Grafana@PUL2024!" \
    grafana_url="http://203.x.x.x:3000" \
    api_key="glsa_PULgrafana2024AdminKey_a3b7c9d2" >/dev/null

vault kv put secret/pul/deploy/ansible \
    vault_pass_path="/etc/ansible/.vault_pass" \
    awx_url="http://203.x.x.x:8080" \
    awx_token="awx-pul-token-a3b7c9d2e1f4a5b6" >/dev/null

echo "[+] Vault secrets seeded."

# =============================================================================
# FIREWALL
# =============================================================================

if command -v ufw >/dev/null 2>&1; then
    echo "[*] Updating UFW rules if UFW is enabled..."
    ufw allow "${VAULT_PORT}/tcp" comment "Vault M3 challenge" >/dev/null 2>&1 || true
    ufw allow "22/tcp" comment "SSH M3 challenge" >/dev/null 2>&1 || true
fi

# =============================================================================
# QUICK VALIDATION
# =============================================================================

echo "[*] Running quick validation..."

if systemctl is-active --quiet ssh; then
    echo "[+] SSH service active."
else
    echo "[!] SSH service is not active." >&2
    exit 1
fi

if systemctl is-active --quiet "${SERVICE_NAME}"; then
    echo "[+] Vault service active."
else
    echo "[!] Vault service is not active." >&2
    systemctl status "${SERVICE_NAME}" --no-pager
    exit 1
fi

if vault kv get secret/pul/creds/vault-ssh >/dev/null 2>&1; then
    echo "[+] SSH credential secret exists: secret/pul/creds/vault-ssh"
else
    echo "[!] SSH credential secret missing." >&2
    exit 1
fi

if vault kv get secret/pul/ad >/dev/null 2>&1; then
    echo "[+] AD objective secret exists: secret/pul/ad"
else
    echo "[!] AD objective secret missing." >&2
    exit 1
fi

echo ""
echo "============================================================"
echo "  M3 Setup Complete"
echo "============================================================"
echo "  Vault URL        : http://${HOST_IP}:${VAULT_PORT}"
echo "  SSH Service      : ssh"
echo "  SSH User         : ${VAULT_USER}"
echo "  SSH Cred Path    : secret/pul/creds/vault-ssh"
echo "  AppRole role_id  : pul-cicd-role-7a3f9b2c1d4e"
echo "  AppRole secret   : 3b8f2a1c-9d4e-7f6a-2b1c-8d3f9a7e4b2c"
echo "  Root Token Leak  : journal/proc environment"
echo "  Objective Secret : secret/pul/ad"
echo "  Pivot Target     : 203.x.x.x:9090"
echo "============================================================"
