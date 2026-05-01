#!/usr/bin/env bash
# M4 — itops-monitor | deps.sh
set -euo pipefail
echo "============================================================"
echo "  RNG-IT-02 | M4-itops-monitor | Dependency Installer"
echo "============================================================"
apt-get update -qq
apt-get install -y --no-install-recommends python3 python3-pip net-tools procps curl
pip3 install --quiet flask==2.3.3 werkzeug==2.3.7
echo "[+] M4 dependencies installed."
echo "[!] Run setup.sh to configure."
