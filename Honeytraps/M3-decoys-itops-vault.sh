#!/usr/bin/env bash
# =============================================================================
# RNG-IT-02 | M3 — itops-vault | Honeytraps (7 decoys)
# Ports:
#   8022  — Vault SSH OTP banner (socket)
#   8500  — Secret Rotation Scheduler (web)
#   8501  — HSM Console (web)
#   8502  — Certificate Lifecycle Manager (web)
#   8503  — Key Escrow Portal (web)
#   8504  — Secrets Scanning Report (web)
#   8505  — Compliance Audit Trail (web)
# =============================================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
TRAP_DIR="/opt/pul-honeytrap/itops-m3"; LOG_DIR="/var/log/pul-honeytrap"
mkdir -p "${TRAP_DIR}" "${LOG_DIR}"

make_svc() {
  local name=$1 script=$2 port=$3
  cat > /etc/systemd/system/pul-decoy-${name}.service << EOF
[Unit]
Description=PUL Honeytrap — ${name} (port ${port})
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 ${script}
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "pul-decoy-${name}" --quiet
  systemctl restart "pul-decoy-${name}"
}

# D1: Vault SSH OTP Banner — port 8022 (socket)
cat > "${TRAP_DIR}/vault-ssh-otp.py" << 'PYEOF'
#!/usr/bin/env python3
import socket,threading,logging
LOG="/var/log/pul-honeytrap/itops-m3-vault-ssh.log"
logging.basicConfig(filename=LOG,level=logging.WARNING,format="%(asctime)s %(message)s")
BANNER=b"SSH-2.0-OpenSSH_8.9p1 Ubuntu (Vault SSH OTP Helper)\r\n"
def handle(conn,addr):
    logging.warning(f"VAULT_SSH_OTP|src={addr[0]}")
    try:
        conn.sendall(BANNER)
        data=conn.recv(256)
        if data: logging.warning(f"VAULT_SSH_DATA|src={addr[0]}|data={repr(data[:60])}")
        conn.sendall(b"\x00\x00\x00\x0c\x05\x00\x00\x00\x0e\x00\x00\x00\x00\x00")
    except: pass
    finally: conn.close()
srv=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
srv.bind(("0.0.0.0",8022));srv.listen(10)
while True:
    c,a=srv.accept()
    threading.Thread(target=handle,args=(c,a),daemon=True).start()
PYEOF
make_svc "itops-m3-vault-ssh-otp" "${TRAP_DIR}/vault-ssh-otp.py" 8022

make_web_decoy() {
  local subdir=$1 port=$2 svcname=$3 logname=$4
  mkdir -p "${TRAP_DIR}/${subdir}"
  cat > "${TRAP_DIR}/${subdir}/server.py" << PYEOF
#!/usr/bin/env python3
import http.server,logging,os
LOG="/var/log/pul-honeytrap/${logname}.log"
logging.basicConfig(filename=LOG,level=logging.WARNING,format="%(asctime)s %(message)s")
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self,f,*a): logging.warning(f"HIT|src={self.client_address[0]}|path={self.path}")
    def do_GET(self):
        self.send_response(200);self.send_header("Content-Type","text/html");self.end_headers()
        with open(os.path.join(os.path.dirname(__file__),"index.html"),"rb") as f: self.wfile.write(f.read())
    def do_POST(self):
        n=int(self.headers.get("Content-Length",0));b=self.rfile.read(n)
        logging.warning(f"POST|src={self.client_address[0]}|body={repr(b[:200])}")
        self.send_response(302);self.send_header("Location","/");self.end_headers()
http.server.HTTPServer(("0.0.0.0",${port}),H).serve_forever()
PYEOF
  make_svc "${svcname}" "${TRAP_DIR}/${subdir}/server.py" "${port}"
}

# D2: Secret Rotation Scheduler — port 8500
make_web_decoy "rotation" 8500 "itops-m3-rotation" "itops-m3-rotation"
cat > "${TRAP_DIR}/rotation/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Secret Rotation Scheduler</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Segoe UI',Arial,sans-serif;background:#0d1117;color:#c9d1d9;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#161b22;border-bottom:2px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#c4a53e;font-size:15px;font-weight:700}.hdr p{color:rgba(255,255,255,.35);font-size:11px}
.main{flex:1;padding:20px;max-width:950px;margin:0 auto;width:100%}
.panel{background:#161b22;border:1px solid #21262d;border-radius:7px;overflow:hidden;margin-bottom:14px}
.ph{background:#21262d;border-bottom:1px solid #30363d;padding:10px 14px;font-size:12.5px;font-weight:700;color:#c4a53e}
.rot-row{display:flex;align-items:center;gap:10px;padding:9px 14px;border-bottom:1px solid #21262d;font-size:12.5px}
.rot-row:last-child{border-bottom:none}.rname{width:200px;flex-shrink:0;font-family:monospace;font-size:11.5px;color:#58a6ff}
.rtype{width:100px;color:#8b949e}.rlast{width:120px;color:#8b949e;font-size:11px}
.rnext{flex:1;font-size:11px}.rstatus{width:100px;text-align:right}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700}
.b-ok{background:rgba(63,185,80,.15);color:#3fb950}.b-due{background:rgba(245,158,11,.15);color:#f59e0b}
.b-over{background:rgba(248,81,73,.15);color:#f85149}.b-sched{background:rgba(88,166,255,.15);color:#58a6ff}
.login{position:fixed;inset:0;background:rgba(0,0,0,.7);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#161b22;border:1px solid #30363d;border-radius:7px;width:360px;overflow:hidden}
.lh{background:#21262d;border-bottom:1px solid #30363d;padding:14px;color:#c4a53e;font-size:13px;font-weight:700}
.lbody{padding:16px}
.fg{margin-bottom:12px}.fg label{display:block;font-size:10px;color:#8b949e;text-transform:uppercase;letter-spacing:.07em;margin-bottom:4px}
.fg input{width:100%;padding:8px 10px;background:#0d1117;border:1px solid #30363d;border-radius:4px;color:#c9d1d9;font-size:12px;outline:none}
.btn{width:100%;padding:9px;background:#c4a53e;color:#0d1117;border:none;border-radius:4px;font-size:13px;font-weight:800;cursor:pointer}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">🔄 Secret Rotation — Admin Login</div>
<div class="lbody">
<div class="fg"><label>Username</label><input type="text" placeholder="rotation-admin or sre-lead"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Sign In</button>
</div></div></div>
<div class="hdr"><h1>🔄 PUL Secret Rotation Scheduler</h1><p>Automated credential lifecycle | vault.prabalurja.in</p></div>
<div class="main">
<div class="panel"><div class="ph">Rotation Schedule — All Secrets</div>
<div class="rot-row"><span class="rname">svc-monitor / AD</span><span class="rtype">AD Password</span><span class="rlast">2024-08-15</span><span class="rnext">⚠ OVERDUE — was due 2024-11-15</span><span class="rstatus"><span class="badge b-over">OVERDUE</span></span></div>
<div class="rot-row"><span class="rname">pul-cicd AppRole</span><span class="rtype">Vault AppRole</span><span class="rlast">2024-11-01</span><span class="rnext">Due: 2024-12-01</span><span class="rstatus"><span class="badge b-due">DUE SOON</span></span></div>
<div class="rot-row"><span class="rname">svc-deploy LDAP</span><span class="rtype">LDAP Password</span><span class="rlast">2024-10-15</span><span class="rnext">Scheduled: 2025-01-15</span><span class="rstatus"><span class="badge b-sched">SCHEDULED</span></span></div>
<div class="rot-row"><span class="rname">Vault Root Token</span><span class="rtype">Vault Token</span><span class="rlast">Never</span><span class="rnext" style="color:#f85149">⛔ Root token not rotated — CRITICAL</span><span class="rstatus"><span class="badge b-over">CRITICAL</span></span></div>
<div class="rot-row"><span class="rname">dev-jump SSH key</span><span class="rtype">SSH Keypair</span><span class="rlast">2024-09-12</span><span class="rnext">Due: 2025-03-12</span><span class="rstatus"><span class="badge b-ok">OK</span></span></div>
</div></div>
</body></html>
HTML

# D3: HSM Console — port 8501
make_web_decoy "hsm" 8501 "itops-m3-hsm" "itops-m3-hsm"
cat > "${TRAP_DIR}/hsm/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL HSM Console</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Segoe UI',Arial,monospace;background:#0c0c14;color:#e0e0e0;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#0a0a10;border-bottom:3px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#c4a53e;font-size:14px;font-weight:700;letter-spacing:.04em}.hdr p{color:rgba(255,255,255,.3);font-size:11px}
.main{flex:1;padding:20px;max-width:900px;margin:0 auto;width:100%}
.panel{background:#12121e;border:1px solid #1e1e30;border-radius:6px;overflow:hidden;margin-bottom:12px}
.ph{background:#0a0a10;border-bottom:2px solid #c4a53e;padding:9px 14px;color:#c4a53e;font-size:12px;font-weight:700}
.pb{padding:14px}
.info-row{display:flex;gap:12px;padding:8px 0;border-bottom:1px solid #1e1e30;font-size:12px}
.info-row:last-child{border-bottom:none}.ik{width:220px;flex-shrink:0;color:#8b8b9e;font-family:sans-serif}.iv{flex:1;color:#64ffda;font-family:'Courier New',monospace;font-size:11.5px}
.iv.warn{color:#f59e0b}.iv.ok{color:#3fb950}.iv.err{color:#f85149}
.badge{display:inline-block;padding:2px 8px;border-radius:3px;font-size:9.5px;font-weight:700;font-family:sans-serif}
.b-ok{background:rgba(63,185,80,.15);color:#3fb950}.b-tam{background:rgba(248,81,73,.15);color:#f85149}
.login{position:fixed;inset:0;background:rgba(0,0,0,.8);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#12121e;border:1px solid #1e1e30;border-radius:6px;width:380px;overflow:hidden}
.lh{background:#0a0a10;border-bottom:2px solid #c4a53e;padding:14px 18px;color:#c4a53e;font-size:13px;font-weight:700}
.lbody{padding:16px}
.warn-box{background:rgba(248,81,73,.08);border:1px solid rgba(248,81,73,.2);border-radius:4px;padding:9px;font-size:11.5px;color:#f87171;margin-bottom:14px;font-family:sans-serif}
.fg{margin-bottom:12px}.fg label{display:block;font-size:10px;color:#8b8b9e;text-transform:uppercase;letter-spacing:.07em;margin-bottom:4px;font-family:sans-serif}
.fg input{width:100%;padding:8px 10px;background:#0a0a10;border:1px solid #1e1e30;border-radius:3px;color:#e0e0e0;font-size:12px;outline:none;font-family:'Courier New',monospace}
.btn{width:100%;padding:9px;background:#c4a53e;color:#0a0a10;border:none;border-radius:3px;font-size:13px;font-weight:800;cursor:pointer;font-family:sans-serif}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">🔐 HSM Management Console — Authentication</div>
<div class="lbody">
<div class="warn-box">⚠ HSM operator card authentication required. Insert smart card before entering PIN.</div>
<div class="fg"><label>Operator ID</label><input type="text" placeholder="HSM-OPR-001 or crypto-admin"></div>
<div class="fg"><label>Operator PIN</label><input type="password" placeholder="HSM operator PIN (4-8 digits)"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Authenticate</button>
</div></div></div>
<div class="hdr"><h1>🔐 PUL HARDWARE SECURITY MODULE CONSOLE</h1><p>Thales Luna 7 HSM | FIPS 140-3 Level 3 | PUL Key Management</p></div>
<div class="main">
<div class="panel"><div class="ph">HSM Device Status</div><div class="pb">
<div class="info-row"><span class="ik">Device Model</span><span class="iv">Thales Luna Network HSM 7 — PN 940-000254-001</span></div>
<div class="info-row"><span class="ik">Serial Number</span><span class="iv">HSM-PUL-NW7-20241003-42</span></div>
<div class="info-row"><span class="ik">Firmware</span><span class="iv ok">7.7.2 <span class="b-ok badge">CURRENT</span></span></div>
<div class="info-row"><span class="ik">Tamper Status</span><span class="iv ok">NO TAMPER DETECTED <span class="b-ok badge">SECURE</span></span></div>
<div class="info-row"><span class="ik">Partition Count</span><span class="iv">3 partitions (pul-tls, pul-codesign, pul-ot-crypt)</span></div>
<div class="info-row"><span class="ik">Battery Status</span><span class="iv warn">75% — estimated 18 months remaining</span></div>
</div></div>
<div class="panel"><div class="ph">Key Inventory — pul-tls Partition</div><div class="pb">
<div class="info-row"><span class="ik">prabalurja.in TLS Root</span><span class="iv">RSA-4096 | Created 2022-03-01 | Expires 2032-03-01</span></div>
<div class="info-row"><span class="ik">SAML Signing Key</span><span class="iv warn">RSA-2048 | Expires 2025-02-10 — ROTATION NEEDED</span></div>
<div class="info-row"><span class="ik">DKIM Signing Key</span><span class="iv ok">RSA-2048 | Expires 2025-01-15</span></div>
<div class="info-row"><span class="ik">Vault Seal Key</span><span class="iv err">Auto-unseal (dev mode) — HSM NOT IN USE ⛔</span></div>
</div></div></div>
</body></html>
HTML

# D4: Certificate Lifecycle Manager — port 8502
make_web_decoy "certmgr" 8502 "itops-m3-certmgr" "itops-m3-certmgr"
cat > "${TRAP_DIR}/certmgr/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Certificate Manager</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Segoe UI',Arial,sans-serif;background:#f0f7ff;color:#1e3a5f;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#1e3a5f;border-bottom:3px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#c4a53e;font-size:15px;font-weight:700}.hdr p{color:rgba(255,255,255,.35);font-size:11px}
.main{flex:1;padding:20px;max-width:1000px;margin:0 auto;width:100%}
.kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:16px}
.kpi{background:#fff;border:1px solid #bfdbfe;border-radius:6px;padding:12px;border-left:3px solid #1e3a5f}
.kpi .n{font-size:22px;font-weight:800;color:#1e3a5f}.kpi .l{font-size:10.5px;color:#6b7280;text-transform:uppercase;letter-spacing:.05em;margin-top:3px}
.kpi.warn .n{color:#d97706}.kpi.err .n{color:#dc2626}
.panel{background:#fff;border:1px solid #bfdbfe;border-radius:7px;overflow:hidden;margin-bottom:12px}
.ph{background:#1e3a5f;color:#c4a53e;padding:10px 14px;font-size:12.5px;font-weight:700;border-bottom:2px solid #c4a53e}
.table{width:100%;border-collapse:collapse;font-size:12px}
.table th{text-align:left;padding:7px 12px;background:#eff6ff;color:#6b7280;font-size:10.5px;text-transform:uppercase;letter-spacing:.05em;border-bottom:1px solid #bfdbfe}
.table td{padding:8px 12px;border-bottom:1px solid #eff6ff;font-family:'Courier New',monospace}
.table tr:hover td{background:#f0f7ff}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700;font-family:sans-serif}
.b-ok{background:rgba(5,150,105,.12);color:#047857}.b-exp{background:rgba(220,38,38,.12);color:#991b1b}
.b-soon{background:rgba(217,119,6,.12);color:#b45309}
.login{position:fixed;inset:0;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#fff;border-radius:7px;width:360px;overflow:hidden}
.lh{background:#1e3a5f;border-bottom:2px solid #c4a53e;padding:14px 18px;color:#c4a53e;font-size:13px;font-weight:700}
.lbody{padding:16px}
.fg{margin-bottom:12px}.fg label{display:block;font-size:10.5px;font-weight:700;color:#6b7280;margin-bottom:4px;text-transform:uppercase;letter-spacing:.07em}
.fg input{width:100%;padding:8px 10px;border:1px solid #bfdbfe;border-radius:4px;font-size:13px}
.btn{width:100%;padding:9px;background:#1e3a5f;color:#fff;border:none;border-radius:4px;font-size:13px;font-weight:700;cursor:pointer}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">📜 Certificate Manager — Login</div>
<div class="lbody">
<div class="fg"><label>Username</label><input type="text" placeholder="pki-admin or cert-manager"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Sign In</button>
</div></div></div>
<div class="hdr"><h1>📜 PUL Certificate Lifecycle Manager</h1><p>Internal PKI | Let's Encrypt + Vault PKI | pul-pki.prabalurja.in</p></div>
<div class="main">
<div class="kpis">
<div class="kpi"><div class="n">147</div><div class="l">Total Certs</div></div>
<div class="kpi err"><div class="n">3</div><div class="l">Expired</div></div>
<div class="kpi warn"><div class="n">8</div><div class="l">Expiring 30d</div></div>
<div class="kpi"><div class="n">136</div><div class="l">Valid</div></div>
</div>
<div class="panel"><div class="ph">Certificates Expiring Soon</div>
<table class="table">
<tr><th>Common Name</th><th>SAN</th><th>Issued By</th><th>Expires</th><th>Days Left</th><th>Status</th></tr>
<tr><td>sso.prabalurja.in</td><td>sso.prabalurja.in, idp.prabalurja.in</td><td>PUL Internal CA</td><td>2025-02-10</td><td style="font-family:sans-serif;color:#b45309">87 days</td><td><span class="badge b-soon">RENEW SOON</span></td></tr>
<tr><td>vault.prabalurja.in</td><td>vault.prabalurja.in</td><td>Let's Encrypt</td><td>2025-01-03</td><td style="font-family:sans-serif;color:#dc2626">49 days</td><td><span class="badge b-exp">URGENT</span></td></tr>
<tr><td>registry.prabalurja.in</td><td>registry.prabalurja.in</td><td>PUL Internal CA</td><td>2025-01-20</td><td style="font-family:sans-serif;color:#b45309">66 days</td><td><span class="badge b-soon">RENEW SOON</span></td></tr>
</table></div></div>
</body></html>
HTML

# D5: Key Escrow Portal — port 8503
make_web_decoy "keyescrow" 8503 "itops-m3-keyescrow" "itops-m3-keyescrow"
cat > "${TRAP_DIR}/keyescrow/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Key Escrow Portal</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Segoe UI',Arial,sans-serif;background:#1c1917;color:#e7e5e4;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#0c0a09;border-bottom:3px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#c4a53e;font-size:14px;font-weight:700;letter-spacing:.04em}.hdr p{color:rgba(255,255,255,.3);font-size:11px}
.warn-strip{background:rgba(220,38,38,.12);border-bottom:1px solid rgba(220,38,38,.25);padding:7px 20px;font-size:11.5px;color:#f87171;display:flex;align-items:center;gap:8px}
.main{flex:1;display:flex;align-items:center;justify-content:center;padding:30px;flex-direction:column}
.escrow-card{background:#292524;border:1px solid #44403c;border-radius:8px;width:480px;overflow:hidden;box-shadow:0 20px 50px rgba(0,0,0,.7)}
.ch{background:#0c0a09;border-bottom:2px solid #c4a53e;padding:24px;text-align:center}
.ch .icon{font-size:44px;margin-bottom:10px}.ch h2{color:#c4a53e;font-size:16px;font-weight:700}
.ch p{color:rgba(255,255,255,.35);font-size:11px;margin-top:5px;letter-spacing:.05em;text-transform:uppercase}
.cb{padding:24px}
.dual-note{background:rgba(196,165,62,.08);border:1px solid rgba(196,165,62,.2);border-radius:5px;padding:10px 14px;font-size:12px;color:#fbbf24;margin-bottom:18px}
.fg{margin-bottom:16px}.fg label{display:block;font-size:10.5px;font-weight:700;color:rgba(255,255,255,.4);margin-bottom:6px;text-transform:uppercase;letter-spacing:.08em}
.fg input{width:100%;padding:10px 14px;background:#1c1917;border:1.5px solid #44403c;border-radius:6px;color:#e7e5e4;font-size:13px;outline:none}
.fg input:focus{border-color:#c4a53e}
.btn-row{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.btn-retrieve{background:linear-gradient(135deg,#7c2d12,#991b1b);color:#fff;border:none;padding:10px;border-radius:6px;font-size:13px;font-weight:700;cursor:pointer}
.btn-escrow{background:#292524;border:1px solid #c4a53e;color:#c4a53e;padding:10px;border-radius:6px;font-size:13px;cursor:pointer}
.meta{text-align:center;font-size:10.5px;color:rgba(255,255,255,.2);margin-top:16px}
</style></head>
<body>
<div class="hdr"><h1>🗝 PUL KEY ESCROW PORTAL</h1><p>Emergency Key Recovery | Dual-Control Required | NEXUS-IT</p></div>
<div class="warn-strip">⚠ &nbsp;RESTRICTED — All key retrieval operations require dual control (two authorised officers). All access is audited and reported to CISO.</div>
<div class="main">
<div class="escrow-card">
<div class="ch"><div class="icon">🗝</div><h2>Emergency Key Escrow Access</h2><p>Two-Person Integrity Control — Prabal Urja Limited</p></div>
<div class="cb">
<div class="dual-note">🔐 Dual control required: Two senior security officers must independently authenticate to retrieve any escrowed key material.</div>
<div class="fg"><label>Officer 1 — Username</label><input type="text" placeholder="CISO or senior security officer ID"></div>
<div class="fg"><label>Officer 1 — Password + TOTP</label><input type="password" placeholder="Password + 6-digit OTP"></div>
<div class="fg"><label>Officer 2 — Username</label><input type="text" placeholder="Second authorised officer ID"></div>
<div class="fg"><label>Officer 2 — Password + TOTP</label><input type="password" placeholder="Password + 6-digit OTP"></div>
<div class="btn-row">
<button class="btn-retrieve" onclick="alert('Dual-control authentication failed. Incident logged.')">Retrieve Key</button>
<button class="btn-escrow" onclick="alert('Key escrow deposit requires HSM admin authentication.')">Deposit Key</button>
</div>
<div class="meta">PUL Key Escrow v3 | All operations subject to mandatory audit | Unauthorised access is a criminal offence</div>
</div></div>
</div>
</body></html>
HTML

# D6: Secrets Scanning Report — port 8504
make_web_decoy "secretscan" 8504 "itops-m3-secretscan" "itops-m3-secretscan"
cat > "${TRAP_DIR}/secretscan/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Secrets Scan Report</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Segoe UI',Arial,monospace;background:#0d1117;color:#c9d1d9;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#161b22;border-bottom:2px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#c4a53e;font-size:14px;font-weight:700}.hdr p{color:rgba(255,255,255,.35);font-size:11px}
.main{flex:1;padding:20px;max-width:950px;margin:0 auto;width:100%}
.kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:16px}
.kpi{background:#161b22;border:1px solid #21262d;border-radius:6px;padding:12px}
.kpi .n{font-size:22px;font-weight:800;color:#f85149}.kpi .l{font-size:10.5px;color:#8b949e;text-transform:uppercase;letter-spacing:.05em;margin-top:3px}
.kpi.ok .n{color:#3fb950}
.panel{background:#161b22;border:1px solid #21262d;border-radius:6px;overflow:hidden;margin-bottom:12px}
.ph{background:#21262d;border-bottom:1px solid #30363d;padding:9px 14px;font-size:12px;font-weight:600;color:#c4a53e}
.finding{padding:10px 14px;border-bottom:1px solid #21262d;font-size:11.5px}
.finding:last-child{border-bottom:none}.finding-hdr{display:flex;align-items:center;gap:8px;margin-bottom:5px}
.f-repo{font-family:'Courier New',monospace;color:#58a6ff;font-size:12px}
.f-file{color:#8b949e;font-size:11px;margin-left:6px}
.finding-body{font-family:'Courier New',monospace;font-size:11px;color:#f59e0b;background:#0d1117;padding:6px 8px;border-radius:3px;border-left:2px solid #f59e0b}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700;font-family:sans-serif}
.b-crit{background:rgba(248,81,73,.15);color:#f85149}.b-high{background:rgba(245,158,11,.15);color:#f59e0b}
.login{position:fixed;inset:0;background:rgba(0,0,0,.7);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#161b22;border:1px solid #30363d;border-radius:7px;width:360px;overflow:hidden}
.lh{background:#21262d;border-bottom:1px solid #30363d;padding:14px;color:#c4a53e;font-size:13px;font-weight:700}
.lbody{padding:16px}
.fg{margin-bottom:12px}.fg label{display:block;font-size:10px;color:#8b949e;text-transform:uppercase;letter-spacing:.07em;margin-bottom:4px}
.fg input{width:100%;padding:8px 10px;background:#0d1117;border:1px solid #30363d;border-radius:4px;color:#c9d1d9;font-size:12px;outline:none}
.btn{width:100%;padding:9px;background:#c4a53e;color:#0d1117;border:none;border-radius:4px;font-size:13px;font-weight:800;cursor:pointer}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">🔍 Secrets Scanner — Login</div>
<div class="lbody">
<div class="fg"><label>Username</label><input type="text" placeholder="sec-analyst or rajiv.menon"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Sign In</button>
</div></div></div>
<div class="hdr"><h1>🔍 PUL Secrets Scanning Report</h1><p>TruffleHog / Gitleaks | Repository Secret Detection | pul-secscan.prabalurja.in</p></div>
<div class="main">
<div class="kpis">
<div class="kpi"><div class="n">7</div><div class="l">Active Findings</div></div>
<div class="kpi"><div class="n">3</div><div class="l">Repos Affected</div></div>
<div class="kpi ok"><div class="n">14</div><div class="l">Repos Clean</div></div>
<div class="kpi"><div class="n">Nov 15</div><div class="l">Last Scan</div></div>
</div>
<div class="panel"><div class="ph">Active Secret Findings</div>
<div class="finding">
<div class="finding-hdr"><span class="badge b-crit">CRITICAL</span><span class="f-repo">svc-cicd/pul-infra-config</span><span class="f-file">commit 3c2b1a0 → .env (deleted)</span></div>
<div class="finding-body">VAULT_ROLE_ID=pul-cicd-role-7a3f9b2c1d4e<br>VAULT_SECRET_ID=3b8f2a1c-9d4e-7f6a-2b1c-8d3f9a7e4b2c</div>
</div>
<div class="finding">
<div class="finding-hdr"><span class="badge b-high">HIGH</span><span class="f-repo">devops-admin/ansible-playbooks</span><span class="f-file">group_vars/all/vault.yml (plaintext in verbose log)</span></div>
<div class="finding-body">vault_dev_jump_ssh_key: -----BEGIN OPENSSH PRIVATE KEY----- [DETECTED]</div>
</div>
<div class="finding">
<div class="finding-hdr"><span class="badge b-high">HIGH</span><span class="f-repo">arun.sharma/infra-notes</span><span class="f-file">README.md</span></div>
<div class="finding-body">Note: Vault dev root token = pul-vault-root-s3cr3t-2024-gridfall (temp)</div>
</div>
</div></div>
</body></html>
HTML

# D7: Compliance Audit Trail — port 8505
make_web_decoy "audittrail" 8505 "itops-m3-audittrail" "itops-m3-audittrail"
cat > "${TRAP_DIR}/audittrail/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Compliance Audit Trail</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Segoe UI',Arial,sans-serif;background:#f5f5f5;color:#1a202c;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#312e81;border-bottom:3px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#c7d2fe;font-size:15px;font-weight:700}.hdr p{color:rgba(255,255,255,.35);font-size:11px}
.main{flex:1;padding:20px;max-width:1000px;margin:0 auto;width:100%}
.panel{background:#fff;border:1px solid #e2e8f0;border-radius:7px;overflow:hidden;margin-bottom:14px;box-shadow:0 1px 3px rgba(0,0,0,.05)}
.ph{background:#312e81;color:#c7d2fe;padding:10px 14px;font-size:12.5px;font-weight:700;border-bottom:2px solid #c4a53e}
.audit-row{display:flex;align-items:flex-start;gap:10px;padding:10px 14px;border-bottom:1px solid #f0f0f0;font-size:12px}
.audit-row:last-child{border-bottom:none}
.audit-time{width:150px;flex-shrink:0;font-family:monospace;font-size:11px;color:#6b7280;padding-top:1px}
.audit-body{flex:1}.audit-who{font-weight:600;color:#312e81;margin-bottom:3px}.audit-what{color:#374151;line-height:1.5}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700}
.b-read{background:rgba(59,130,246,.12);color:#1d4ed8}.b-write{background:rgba(217,119,6,.12);color:#b45309}
.b-delete{background:rgba(220,38,38,.12);color:#991b1b}.b-auth{background:rgba(5,150,105,.12);color:#047857}
.b-fail{background:rgba(107,114,128,.12);color:#374151}
.login{position:fixed;inset:0;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#fff;border-radius:7px;width:360px;overflow:hidden}
.lh{background:#312e81;border-bottom:2px solid #c4a53e;padding:14px 18px;color:#c7d2fe;font-size:13px;font-weight:700}
.lbody{padding:18px}
.fg{margin-bottom:12px}.fg label{display:block;font-size:10.5px;font-weight:700;color:#6b7280;margin-bottom:4px;text-transform:uppercase;letter-spacing:.07em}
.fg input{width:100%;padding:8px 10px;border:1px solid #e2e8f0;border-radius:4px;font-size:13px}
.btn{width:100%;padding:9px;background:#312e81;color:#fff;border:none;border-radius:4px;font-size:13px;font-weight:700;cursor:pointer}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">📋 Audit Trail — Compliance Login</div>
<div class="lbody">
<div class="fg"><label>Username</label><input type="text" placeholder="auditor or compliance-officer"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Sign In</button>
</div></div></div>
<div class="hdr"><h1>📋 PUL Compliance Audit Trail</h1><p>Immutable Audit Log | CERT-In / ISO 27001 | Vault Audit | pul-audit.prabalurja.in</p></div>
<div class="main">
<div class="panel"><div class="ph">Vault Audit Log — Recent Events</div>
<div class="audit-row"><span class="audit-time">2024-11-15T10:44:55Z</span><div class="audit-body"><div class="audit-who">unknown / AppRole <span class="badge b-auth">AUTH</span></div><div class="audit-what">AppRole login: role=pul-cicd — from 203.0.2.X. Client token issued.</div></div></div>
<div class="audit-row"><span class="audit-time">2024-11-15T10:45:12Z</span><div class="audit-body"><div class="audit-who">AppRole client <span class="badge b-read">READ</span></div><div class="audit-what">secret/pul/cicd/pipeline read by AppRole token — from 203.0.2.X</div></div></div>
<div class="audit-row"><span class="audit-time">2024-11-15T10:45:44Z</span><div class="audit-body"><div class="audit-who">ROOT TOKEN <span class="badge b-read">READ</span></div><div class="audit-what">secret/pul/ad read — root token used from 203.0.2.X ← ANOMALY: root token should not be used operationally</div></div></div>
<div class="audit-row"><span class="audit-time">2024-11-15T10:46:01Z</span><div class="audit-body"><div class="audit-who">ROOT TOKEN <span class="badge b-read">READ</span></div><div class="audit-what">secret/pul/deploy/ansible read — root token — 203.0.2.X</div></div></div>
<div class="audit-row"><span class="audit-time">2024-11-14T22:00:00Z</span><div class="audit-body"><div class="audit-who">devops-admin <span class="badge b-fail">FAIL</span></div><div class="audit-what">AppRole rotation job failed — Vault connection refused (dev mode restart cleared state)</div></div></div>
</div></div>
</body></html>
HTML

echo ""
echo "============================================================"
echo "  RNG-IT-02 | M3 itops-vault — Honeytraps Active"
echo "  D1: Vault SSH OTP banner (socket) → port 8022"
echo "  D2: Secret Rotation Scheduler     → port 8500"
echo "  D3: HSM Console                   → port 8501"
echo "  D4: Certificate Lifecycle Manager → port 8502"
echo "  D5: Key Escrow Portal             → port 8503"
echo "  D6: Secrets Scanning Report       → port 8504"
echo "  D7: Compliance Audit Trail        → port 8505"
echo "  Logs: ${LOG_DIR}/itops-m3-*.log"
echo "============================================================"
