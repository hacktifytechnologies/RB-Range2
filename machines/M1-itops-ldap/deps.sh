#!/usr/bin/env bash
# =============================================================================
# M1 — itops-ldap | deps.sh
# Dependency installer — run ONCE manually on the VM before taking snapshot.
# Ubuntu 22.04 LTS | Requires internet access.
# =============================================================================
set -euo pipefail

echo "============================================================"
echo "  RNG-IT-02 | M1-itops-ldap | Dependency Installer"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"

export DEBIAN_FRONTEND=noninteractive

echo "[*] Updating apt package index..."
apt-get update -qq

echo "[*] Installing OpenLDAP and utilities..."
# Pre-answer debconf for slapd
echo "slapd slapd/internal/generated_adminpw password PULAdmin@2024" | debconf-set-selections
echo "slapd slapd/internal/adminpw password PULAdmin@2024"           | debconf-set-selections
echo "slapd slapd/password2 password PULAdmin@2024"                  | debconf-set-selections
echo "slapd slapd/password1 password PULAdmin@2024"                  | debconf-set-selections
echo "slapd slapd/domain string prabalurja.in"                       | debconf-set-selections
echo "slapd shared/organization string 'Prabal Urja Limited'"        | debconf-set-selections
echo "slapd slapd/backend select MDB"                                | debconf-set-selections
echo "slapd slapd/purge_database boolean false"                      | debconf-set-selections
echo "slapd slapd/move_old_database boolean true"                    | debconf-set-selections

apt-get install -y --no-install-recommends \
    slapd \
    ldap-utils \
    python3 \
    python3-pip \
    net-tools \
    procps \
    curl

pip3 install --quiet flask==2.3.3 werkzeug==2.3.7

echo ""
echo "[+] M1 dependencies installed."
echo "    slapd   : $(slapd -V 2>&1 | head -1 || echo installed)"
echo "    Python  : $(python3 --version)"
echo "[!] Run setup.sh to configure the challenge."
