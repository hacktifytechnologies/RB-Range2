#!/usr/bin/env bash
# M3 — itops-vault | deps.sh
set -euo pipefail
echo "============================================================"
echo "  RNG-IT-02 | M3-itops-vault | Dependency Installer"
echo "============================================================"
apt-get update -qq
apt-get install -y --no-install-recommends curl wget python3 python3-pip net-tools procps unzip
VAULT_VERSION="1.15.4"
echo "[*] Downloading HashiCorp Vault ${VAULT_VERSION}..."
wget -q "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" -O /tmp/vault.zip
unzip -q /tmp/vault.zip -d /usr/local/bin/
rm /tmp/vault.zip
chmod +x /usr/local/bin/vault
pip3 install --quiet flask==2.3.3 werkzeug==2.3.7
echo "[+] Vault: $(vault version)"
echo "[!] Run setup.sh to configure."
