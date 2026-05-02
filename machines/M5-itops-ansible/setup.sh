#!/usr/bin/env bash
# =============================================================================
# setup.sh — M5 · itops-ansible · RNG-IT-02 | OPERATION GRIDFALL
# Challenge: Ansible Vault Password + SSH Private Key in AWX Job Output
# Ubuntu 22.04 LTS | Run deps.sh first | Run as root
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_USER="pulawx"
APP_DIR="/opt/pul-awx"
LOG_DIR="/var/log/pul-ansible"
KEY_DIR="/etc/pul-gridfall"
APP_PORT=8080
SERVICE_NAME="pul-awx"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${GREEN}[SETUP]${NC} $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
ask()  { echo -e "${BOLD}[INPUT]${NC} $*"; }

[[ $EUID -ne 0 ]] && fail "Run as root: sudo bash setup.sh"
command -v python3 >/dev/null 2>&1 || fail "python3 not found — run deps.sh first"
command -v ssh-keygen >/dev/null 2>&1 || { apt-get install -y -qq openssh-client; }
command -v sshpass >/dev/null 2>&1 || { apt-get install -y -qq sshpass; }

echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD}  RNG-IT-02 | M5-itops-ansible | Challenge Setup${NC}"
echo -e "${BOLD}  Prabal Urja Limited — Operation GRIDFALL${NC}"
echo -e "${BOLD}============================================================${NC}"
echo ""

# =============================================================================
# STEP 1 — Get Range 3 Jump Host IP
# =============================================================================
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  STEP 1 — Range 3 Jump Host Details${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
info "The SSH private key generated here must be installed on the Range 3"
info "jump host (dev-jump.prabalurja.in) before participants can pivot."
echo ""

# ── Get jump host IP ──────────────────────────────────────────────────────────
JUMP_HOST_IP=""
while [[ -z "$JUMP_HOST_IP" ]]; do
    ask "Enter the IP address of the Range 3 jump host (M1 of Range 3):"
    read -rp "  Jump host IP: " JUMP_HOST_IP
    if [[ ! "$JUMP_HOST_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        warn "Invalid IP. Please enter a valid IPv4 address."
        JUMP_HOST_IP=""
    fi
done
ok "Jump host IP: ${JUMP_HOST_IP}"

# ── Choose key delivery method ────────────────────────────────────────────────
echo ""
ask "How should this script install the public key on the jump host?"
echo "  [1] Auto via SSH using ubuntu:ubuntu (Range 3 VM default creds)"
echo "  [2] Auto via SSH using a custom username/password I'll enter"
echo "  [3] Print the public key — I'll install it manually"
echo "  [4] Skip for now"
read -rp "  Choice [1/2/3/4]: " KEY_MODE
KEY_MODE="${KEY_MODE:-1}"

# =============================================================================
# STEP 2 — Generate SSH Keypair
# =============================================================================
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  STEP 2 — Generating SSH Keypair${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

mkdir -p "${KEY_DIR}"
chmod 700 "${KEY_DIR}"

# Always regenerate to ensure a valid keypair
[[ -f "${KEY_DIR}/jump_ed25519" ]] && rm -f "${KEY_DIR}/jump_ed25519" "${KEY_DIR}/jump_ed25519.pub"

log "Generating Ed25519 keypair..."
ssh-keygen -t ed25519 \
    -C "devops@dev-jump.prabalurja.in GRIDFALL-2024" \
    -f "${KEY_DIR}/jump_ed25519" \
    -N "" -q

chmod 600 "${KEY_DIR}/jump_ed25519"
chmod 644 "${KEY_DIR}/jump_ed25519.pub"

PRIVATE_KEY="$(cat "${KEY_DIR}/jump_ed25519")"
PUBLIC_KEY="$(cat "${KEY_DIR}/jump_ed25519.pub")"

ok "Private key: ${KEY_DIR}/jump_ed25519"
ok "Public key:  ${KEY_DIR}/jump_ed25519.pub"

# =============================================================================
# STEP 3 — Install Public Key on Jump Host
# =============================================================================
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  STEP 3 — Installing Public Key on Jump Host${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=no"
SSH_KEY_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -o PasswordAuthentication=no"

install_key_via_ssh() {
    local USER="$1"
    local PASS="$2"
    local REMOTE_CMD="
        id devops &>/dev/null || useradd -m -s /bin/bash devops;
        mkdir -p /home/devops/.ssh;
        echo '${PUBLIC_KEY}' >> /home/devops/.ssh/authorized_keys;
        sort -u /home/devops/.ssh/authorized_keys -o /home/devops/.ssh/authorized_keys;
        chmod 700 /home/devops/.ssh;
        chmod 600 /home/devops/.ssh/authorized_keys;
        chown -R devops:devops /home/devops/.ssh;
        passwd -l devops 2>/dev/null || true;
        echo 'devops ALL=(ALL) NOPASSWD:/usr/bin/nmap,/usr/bin/curl,/usr/bin/wget' > /etc/sudoers.d/devops-tools;
        echo 'KEY_INSTALLED_OK'
    "
    sshpass -p "${PASS}" ssh ${SSH_OPTS} "${USER}@${JUMP_HOST_IP}" "${REMOTE_CMD}" 2>/dev/null
}

case "$KEY_MODE" in
  1)
    log "Installing public key via ubuntu:ubuntu on ${JUMP_HOST_IP}..."
    if RESULT=$(install_key_via_ssh "ubuntu" "ubuntu"); then
        if echo "$RESULT" | grep -q "KEY_INSTALLED_OK"; then
            ok "Public key installed on ${JUMP_HOST_IP} — devops user configured"
        else
            warn "SSH succeeded but key install output unclear. Check manually."
        fi
    else
        warn "SSH to ${JUMP_HOST_IP} with ubuntu:ubuntu failed."
        warn "Falling back — public key saved to: /root/gridfall_jump_pubkey.txt"
        echo "$PUBLIC_KEY" > /root/gridfall_jump_pubkey.txt
    fi
    ;;
  2)
    ask "Enter SSH username for ${JUMP_HOST_IP}:"
    read -rp "  Username: " SSH_USER
    ask "Enter SSH password:"
    read -rsp "  Password: " SSH_PASS
    echo ""
    log "Installing public key via ${SSH_USER}@${JUMP_HOST_IP}..."
    if RESULT=$(install_key_via_ssh "${SSH_USER}" "${SSH_PASS}"); then
        if echo "$RESULT" | grep -q "KEY_INSTALLED_OK"; then
            ok "Public key installed on ${JUMP_HOST_IP}"
        else
            warn "SSH succeeded but verify manually."
        fi
    else
        warn "SSH failed — public key saved to: /root/gridfall_jump_pubkey.txt"
        echo "$PUBLIC_KEY" > /root/gridfall_jump_pubkey.txt
    fi
    ;;
  3)
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  ACTION REQUIRED — Copy this to the jump host${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  On ${JUMP_HOST_IP} (as root):"
    echo ""
    echo -e "  ${CYAN}useradd -m -s /bin/bash devops 2>/dev/null || true${NC}"
    echo -e "  ${CYAN}mkdir -p /home/devops/.ssh${NC}"
    echo -e "  ${CYAN}echo '${PUBLIC_KEY}' >> /home/devops/.ssh/authorized_keys${NC}"
    echo -e "  ${CYAN}chmod 700 /home/devops/.ssh && chmod 600 /home/devops/.ssh/authorized_keys${NC}"
    echo -e "  ${CYAN}chown -R devops:devops /home/devops/.ssh${NC}"
    echo ""
    echo "$PUBLIC_KEY" > /root/gridfall_jump_pubkey.txt
    ok "Public key also saved to: /root/gridfall_jump_pubkey.txt"
    ;;
  4)
    warn "Skipping key delivery."
    echo "$PUBLIC_KEY" > /root/gridfall_jump_pubkey.txt
    ok "Public key saved to: /root/gridfall_jump_pubkey.txt"
    ;;
esac

# =============================================================================
# STEP 4 — Write job output file + config (read by app.py at request time)
# =============================================================================
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  STEP 4 — Embedding Key in AWX Job Output${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

mkdir -p "${APP_DIR}/app/data"

# Write the config JSON (jump host IP + key path)
cat > "${KEY_DIR}/job_config.json" << JSONEOF
{
  "jump_host_ip": "${JUMP_HOST_IP}",
  "key_comment": "devops@dev-jump.prabalurja.in GRIDFALL-2024",
  "priv_key_path": "${KEY_DIR}/jump_ed25519",
  "pub_key": "${PUBLIC_KEY}"
}
JSONEOF
chmod 640 "${KEY_DIR}/job_config.json"

# Write the AWX job output file with the real private key embedded
# This is what participants see when they browse to JOB-20241115-018
cat > "${APP_DIR}/app/data/job_output_018.txt" << JOBEOF
PLAY [PUL Dev Infrastructure Deployment] ************************************

TASK [Gathering Facts] ******************************************************
ok: [203.x.x.x]
ok: [203.x.x.x]

TASK [Load encrypted vault variables] ***************************************
Executing: ansible-vault decrypt group_vars/all/vault.yml --vault-password-file=/etc/ansible/.vault_pass --output=-
Vault password file: /etc/ansible/.vault_pass
Vault password (read from file): Ansibl3Vault@PUL!GridFall2024

TASK [Configure deployment SSH key] *****************************************
Changed: [${JUMP_HOST_IP}] => (item=authorized_keys)
Writing SSH private key to /home/deploy/.ssh/id_ed25519 on jump host

${PRIVATE_KEY}

TASK [Deploy application configuration] *************************************
Changed: [${JUMP_HOST_IP}] => {"changed":true,"dest":"/opt/pul-app/.env"}

TASK [Restart application services] *****************************************
Changed: [203.x.x.x, 203.x.x.x]

PLAY RECAP ******************************************************************
203.x.x.x  : ok=8  changed=3  unreachable=0  failed=0
203.x.x.x  : ok=6  changed=2  unreachable=0  failed=0

Deployment completed successfully. Jump host dev-jump.prabalurja.in (${JUMP_HOST_IP}) updated.
SSH access: ssh -i /home/deploy/.ssh/id_ed25519 devops@dev-jump.prabalurja.in
JOBEOF

chmod 640 "${APP_DIR}/app/data/job_output_018.txt"
ok "AWX job output written with live SSH key embedded"
info "  Output file: ${APP_DIR}/app/data/job_output_018.txt"

# =============================================================================
# STEP 5 — Install app, vault files, and systemd service
# =============================================================================
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  STEP 5 — Installing AWX Portal Application${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ── Create app user ───────────────────────────────────────────────────────────
if ! id -u "${APP_USER}" &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin \
            --comment "PUL AWX Service" "${APP_USER}"
fi

# ── Validate app.py is Python before copying ─────────────────────────────────
APP_PY="${SCRIPT_DIR}/app/app.py"
[[ -f "$APP_PY" ]] || fail "app/app.py not found in ${SCRIPT_DIR}/app/ — place M5-app-updated.py there first"
if ! python3 -c "import ast; ast.parse(open('${APP_PY}').read())" 2>/dev/null; then
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fail "app/app.py is NOT valid Python (contains bash or corrupt content).
       Fix: cp /path/to/M5-app-updated.py ${SCRIPT_DIR}/app/app.py
       Then re-run this setup script."
fi
log "app.py syntax validated OK"

# ── Copy app files ────────────────────────────────────────────────────────────
mkdir -p "${APP_DIR}/app/templates" "${APP_DIR}/app/data" "${LOG_DIR}"
cp -r "${SCRIPT_DIR}/app/"* "${APP_DIR}/app/"
# Preserve the data directory we just wrote
chmod 750 "${APP_DIR}/app/data"
chmod 640 "${APP_DIR}/app/data/job_output_018.txt"

chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}" "${LOG_DIR}"
chmod -R 750 "${APP_DIR}"
chmod 770 "${LOG_DIR}"
touch "${LOG_DIR}/awx.log"
chown "${APP_USER}:${APP_USER}" "${LOG_DIR}/awx.log"

# Grant app user access to key config
chown root:"${APP_USER}" "${KEY_DIR}/job_config.json"
chmod 640 "${KEY_DIR}/job_config.json"

# ── Vault password file ───────────────────────────────────────────────────────
mkdir -p /etc/ansible
echo "Ansibl3Vault@PUL!GridFall2024" > /etc/ansible/.vault_pass
chmod 600 /etc/ansible/.vault_pass
chown root:root /etc/ansible/.vault_pass

# ── Vault.yml (encrypted format) ─────────────────────────────────────────────
mkdir -p /opt/pul-infra-config/group_vars/all
cat > /opt/pul-infra-config/group_vars/all/vault.yml << 'VAULTEOF'
$ANSIBLE_VAULT;1.1;AES256
62613661353736373835386665623630353962303933363661353264343835636433363337326166
6663373030386463373536666562383533306263363561620a376535393734376561333362633034
33303634646338626262393039353363303361343565383264383231326466363635306461336464
6339343562653036360a623265666539373765623864383565393534623233353832363530313864
VAULTEOF
chmod 640 /opt/pul-infra-config/group_vars/all/vault.yml
log "Vault files planted"

# ── Systemd service ───────────────────────────────────────────────────────────
cat > /etc/systemd/system/${SERVICE_NAME}.service << SVCEOF
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
ReadWritePaths=${APP_DIR}/app/data
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}" --quiet
systemctl restart "${SERVICE_NAME}"
sleep 2

if systemctl is-active --quiet "${SERVICE_NAME}"; then
    ok "AWX portal running on port ${APP_PORT}"
else
    fail "Service failed — check: journalctl -u ${SERVICE_NAME} -n 30"
fi

# Firewall
if command -v ufw &>/dev/null; then
    ufw allow "${APP_PORT}/tcp" comment "AWX M5 challenge" >/dev/null 2>&1 || true
fi

# =============================================================================
# STEP 6 — Verify end-to-end chain
# =============================================================================
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  STEP 6 — Verification${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

MY_IP=$(hostname -I | awk '{print $1}')

# Check jump host reachability
if nc -z -w 5 "${JUMP_HOST_IP}" 22 2>/dev/null; then
    ok "Jump host ${JUMP_HOST_IP}:22 is reachable"
    # Test SSH key auth
    if ssh -i "${KEY_DIR}/jump_ed25519" \
            ${SSH_KEY_OPTS} \
            "devops@${JUMP_HOST_IP}" "echo SSH_AUTH_OK" 2>/dev/null | grep -q "SSH_AUTH_OK"; then
        echo ""
        echo -e "  ${GREEN}✓ END-TO-END CHAIN IS LIVE${NC}"
        ok "SSH key auth verified: devops@${JUMP_HOST_IP} accepts the key"
        echo ""
        echo -e "  Participants use: ${CYAN}ssh -i <extracted-key> devops@${JUMP_HOST_IP}${NC}"
    else
        warn "Jump host reachable but SSH key auth not working yet."
        warn "The key may not have been installed — try option [1] or [3] again."
        info "Test manually: ssh -i ${KEY_DIR}/jump_ed25519 devops@${JUMP_HOST_IP}"
    fi
else
    warn "Jump host ${JUMP_HOST_IP}:22 is not reachable from this machine."
    warn "Verify the VM is running and port 22 is open."
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  M5 Setup Complete${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
ok "AWX URL       : http://${MY_IP}:${APP_PORT}"
ok "Login         : devops-admin / DevOps@PUL!24"
ok "Vuln Job      : JOB-20241115-018 (deploy-dev-infra)"
ok "Vault Pass    : Ansibl3Vault@PUL!GridFall2024"
ok "Jump Host     : ${JUMP_HOST_IP}"
ok "Key path      : ${KEY_DIR}/jump_ed25519"
echo ""
echo -e "  ${CYAN}Logs:    journalctl -u ${SERVICE_NAME} -f${NC}"
echo -e "  ${CYAN}Service: systemctl status ${SERVICE_NAME}${NC}"
echo ""
