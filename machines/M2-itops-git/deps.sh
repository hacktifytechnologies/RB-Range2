#!/usr/bin/env bash
# =============================================================================
# M2 — itops-git | deps.sh
# Ubuntu 22.04 LTS | Requires internet access.
# =============================================================================
set -euo pipefail
echo "============================================================"
echo "  RNG-IT-02 | M2-itops-git | Dependency Installer"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"

apt-get update -qq
apt-get install -y --no-install-recommends git curl wget python3 python3-pip net-tools procps sqlite3

# Install Gitea binary
GITEA_VERSION="1.21.4"
echo "[*] Downloading Gitea ${GITEA_VERSION}..."
wget -q "https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-amd64" \
    -O /usr/local/bin/gitea
chmod +x /usr/local/bin/gitea

pip3 install --quiet flask==2.3.3 werkzeug==2.3.7

echo "[+] M2 dependencies installed."
echo "    Gitea : $(gitea --version 2>/dev/null | head -1 || echo installed)"
echo "[!] Run setup.sh to configure the challenge."
