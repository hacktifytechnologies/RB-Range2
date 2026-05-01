#!/usr/bin/env bash
# M5 — itops-ansible | deps.sh
set -euo pipefail
echo "============================================================"
echo "  RNG-IT-02 | M5-itops-ansible | Dependency Installer"
echo "============================================================"
apt-get update -qq
apt-get install -y --no-install-recommends python3 python3-pip net-tools procps curl ansible
pip3 install --quiet flask==2.3.3 werkzeug==2.3.7
echo "[+] M5 dependencies installed."
echo "[!] Run setup.sh to configure."
