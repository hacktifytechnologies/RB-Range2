#!/usr/bin/env bash
# =============================================================================
# RNG-IT-02 | M5 — itops-ansible | Honeytraps (7 decoys)
# Ports:
#   4505  — SaltStack ZMQ publisher banner (socket)
#   9400  — Terraform Cloud-style IaC Portal (web)
#   9401  — ITSM Change Management — ServiceNow-style (web)
#   9402  — Patch Management Console (web)
#   9403  — Config Drift Detector (web)
#   9404  — Release Pipeline Visualizer (web)
#   9405  — Rundeck Job Scheduler (web)
# =============================================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
TRAP_DIR="/opt/pul-honeytrap/itops-m5"; LOG_DIR="/var/log/pul-honeytrap"
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

make_web_svc() {
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

# ─── D1: SaltStack ZMQ Publisher — port 4505 ──────────────────────────────────
cat > "${TRAP_DIR}/salt-zmq.py" << 'PYEOF'
#!/usr/bin/env python3
import socket, threading, logging
LOG = "/var/log/pul-honeytrap/itops-m5-salt-zmq.log"
logging.basicConfig(filename=LOG, level=logging.WARNING, format="%(asctime)s %(message)s")
# ZMQ DEALER socket greeting — 10-byte ZMTP 3.x greeting
ZMTP_GREETING = (
    b"\xff\x00\x00\x00\x00\x00\x00\x00\x00\x7f"  # signature
    b"\x03"                                          # version major
    b"\x01"                                          # version minor
    b"NULL" + b"\x00" * 16                          # mechanism (NULL) padded to 20
    b"\x00"                                          # as-server
    b"\x00" * 31                                     # filler
)
def handle(conn, addr):
    logging.warning(f"SALT_ZMQ_CONNECT|src={addr[0]}")
    try:
        conn.sendall(ZMTP_GREETING)
        data = conn.recv(512)
        if data:
            logging.warning(f"SALT_ZMQ_DATA|src={addr[0]}|len={len(data)}|hex={data[:16].hex()}")
    except: pass
    finally: conn.close()
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("0.0.0.0", 4505)); srv.listen(20)
while True:
    c, a = srv.accept()
    threading.Thread(target=handle, args=(c, a), daemon=True).start()
PYEOF
make_svc "itops-m5-salt-zmq" "${TRAP_DIR}/salt-zmq.py" 4505

# ─── D2: Terraform Cloud-style IaC Portal — port 9400 ────────────────────────
make_web_svc "terraform" 9400 "itops-m5-terraform" "itops-m5-terraform"
cat > "${TRAP_DIR}/terraform/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Terraform Cloud</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',Arial,sans-serif;background:#0e0f19;color:#e8e8f0;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#1c1d2e;border-bottom:2px solid #c4a53e;padding:0 20px;height:56px;display:flex;align-items:center;justify-content:space-between}
.hdr .brand{display:flex;align-items:center;gap:10px}
.hdr .logo{font-size:24px}.hdr h1{color:#7b61ff;font-size:16px;font-weight:700}
.hdr p{color:rgba(255,255,255,.3);font-size:11px}
.main{flex:1;padding:20px;max-width:1050px;margin:0 auto;width:100%}
.ws-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:12px;margin-bottom:18px}
.ws-card{background:#1c1d2e;border:1px solid #2a2b3e;border-radius:8px;padding:16px}
.ws-card .ws-name{font-size:14px;font-weight:700;color:#7b61ff;margin-bottom:4px}
.ws-card .ws-source{font-size:11.5px;color:#8b8ba7;margin-bottom:12px;font-family:monospace}
.ws-card .run-row{display:flex;align-items:center;gap:8px;font-size:12px}
.run-status{padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700}
.rs-applied{background:rgba(63,185,80,.15);color:#3fb950}
.rs-planning{background:rgba(123,97,255,.15);color:#7b61ff}
.rs-failed{background:rgba(248,81,73,.15);color:#f85149}
.rs-pending{background:rgba(245,158,11,.15);color:#f59e0b}
.run-time{color:#8b8ba7;font-size:11px;margin-left:auto}
.resources{font-size:11.5px;color:#8b8ba7;margin-top:8px}
.panel{background:#1c1d2e;border:1px solid #2a2b3e;border-radius:7px;overflow:hidden;margin-bottom:14px}
.ph{background:#151626;border-bottom:1px solid #2a2b3e;padding:9px 14px;font-size:12.5px;font-weight:700;color:#7b61ff}
.run-log{background:#0a0b14;padding:12px 14px;font-family:'Courier New',monospace;font-size:11.5px;color:#c9d1d9;line-height:1.8;max-height:180px;overflow-y:auto}
.log-ok{color:#3fb950}.log-warn{color:#f59e0b}.log-err{color:#f85149}.log-info{color:#58a6ff}
.login{position:fixed;inset:0;background:rgba(0,0,0,.7);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#1c1d2e;border:1px solid #2a2b3e;border-radius:8px;width:380px;overflow:hidden}
.lh{background:#151626;border-bottom:2px solid #c4a53e;padding:16px 20px;color:#7b61ff;font-size:14px;font-weight:700}
.lbody{padding:20px}
.fg{margin-bottom:14px}.fg label{display:block;font-size:11px;font-weight:700;color:#8b8ba7;margin-bottom:4px;text-transform:uppercase;letter-spacing:.06em}
.fg input{width:100%;padding:9px 12px;background:#0e0f19;border:1px solid #2a2b3e;border-radius:4px;color:#e8e8f0;font-size:13px;outline:none}
.fg input:focus{border-color:#7b61ff}
.btn{width:100%;padding:10px;background:#7b61ff;color:#fff;border:none;border-radius:4px;font-size:14px;font-weight:700;cursor:pointer}
.footer{background:#151626;padding:8px 20px;text-align:center;font-size:10px;color:rgba(255,255,255,.2)}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">🏗 Terraform Cloud — Sign In</div>
<div class="lbody">
<div class="fg"><label>Username or Email</label><input type="text" placeholder="tf-admin@prabalurja.in or devops-admin"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Sign In</button>
</div></div></div>
<div class="hdr"><div class="brand"><span class="logo">🏗</span><h1>Terraform Cloud</h1></div><p>pul-tf.prabalurja.in | IaC Portal | NEXUS-IT DevOps</p></div>
<div class="main">
<div class="ws-grid">
<div class="ws-card">
<div class="ws-name">pul-nexus-infra</div>
<div class="ws-source">gitea: pul-infra-config/terraform/nexus</div>
<div class="run-row"><span class="run-status rs-applied">APPLIED</span><span>No changes — 14 resources</span><span class="run-time">2h ago</span></div>
<div class="resources">Managed: 14 resources | Workspace: pul-production</div>
</div>
<div class="ws-card">
<div class="ws-name">pul-monitoring-stack</div>
<div class="ws-source">gitea: pul-infra-config/terraform/monitoring</div>
<div class="run-row"><span class="run-status rs-planning">PLANNING</span><span>Plan in progress…</span><span class="run-time">4m ago</span></div>
<div class="resources">Managed: 22 resources | Workspace: pul-production</div>
</div>
<div class="ws-card">
<div class="ws-name">pul-vault-cluster</div>
<div class="ws-source">gitea: pul-infra-config/terraform/vault</div>
<div class="run-row"><span class="run-status rs-failed">FAILED</span><span>Error: Vault provider auth failed</span><span class="run-time">1d ago</span></div>
<div class="resources">Managed: 8 resources | Drift detected ⚠</div>
</div>
<div class="ws-card">
<div class="ws-name">pul-network-config</div>
<div class="ws-source">gitea: pul-infra-config/terraform/network</div>
<div class="run-row"><span class="run-status rs-applied">APPLIED</span><span>2 changes — ACL update</span><span class="run-time">6h ago</span></div>
<div class="resources">Managed: 31 resources | Workspace: pul-production</div>
</div>
</div>
<div class="panel"><div class="ph">Latest Run Output — pul-vault-cluster</div>
<div class="run-log">
<span class="log-info">Running plan in Terraform Cloud...</span><br>
<span class="log-info">Refreshing state... vault_mount.pul-kv: Refreshing...</span><br>
<span class="log-warn">Warning: Vault token expiry detected — root token age: 47 days</span><br>
<span class="log-err">Error: Failed to authenticate to Vault: invalid token</span><br>
<span class="log-err">Detail: The configured Vault token is likely expired or revoked.</span><br>
<span class="log-warn">Hint: Token found in .terraform/vault-token — consider using Vault AppRole instead</span><br>
<span class="log-err">╷ Error: Error making API request.</span><br>
<span class="log-err">│ URL: PUT https://vault.prabalurja.in:8200/v1/auth/token/renew-self</span><br>
<span class="log-err">╵ 403 Forbidden</span>
</div></div></div>
<div class="footer">Terraform Cloud | © 2024 Prabal Urja Limited | DevOps Division</div>
</body></html>
HTML

# ─── D3: ITSM Change Management — port 9401 ───────────────────────────────────
make_web_svc "itsm" 9401 "itops-m5-itsm" "itops-m5-itsm"
cat > "${TRAP_DIR}/itsm/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Change Management</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Segoe UI',Arial,sans-serif;background:#f0f4f8;color:#1e293b;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#0f3d6e;border-bottom:3px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#bae6fd;font-size:15px;font-weight:700}.hdr p{color:rgba(255,255,255,.35);font-size:11px}
.nav{background:#1e5799;border-bottom:1px solid #0f3d6e;display:flex;padding:0 20px}
.nav a{color:rgba(255,255,255,.5);font-size:12.5px;padding:9px 14px;border-bottom:2px solid transparent;text-decoration:none}
.nav a.active{color:#bae6fd;border-color:#c4a53e}
.main{flex:1;padding:20px;max-width:1000px;margin:0 auto;width:100%}
.kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:16px}
.kpi{background:#fff;border:1px solid #e2e8f0;border-radius:6px;padding:12px;border-left:3px solid #0f3d6e;box-shadow:0 1px 3px rgba(0,0,0,.04)}
.kpi .n{font-size:22px;font-weight:800;color:#0f3d6e}.kpi .l{font-size:10.5px;color:#94a3b8;text-transform:uppercase;letter-spacing:.05em;margin-top:3px}
.kpi.warn .n{color:#d97706}.kpi.err .n{color:#dc2626}.kpi.ok .n{color:#059669}
.panel{background:#fff;border:1px solid #e2e8f0;border-radius:7px;overflow:hidden;margin-bottom:14px;box-shadow:0 1px 3px rgba(0,0,0,.04)}
.ph{background:#0f3d6e;color:#bae6fd;padding:10px 14px;font-size:12.5px;font-weight:700;border-bottom:2px solid #c4a53e}
.table{width:100%;border-collapse:collapse;font-size:12.5px}
.table th{text-align:left;padding:8px 12px;background:#f0f9ff;color:#64748b;font-size:10.5px;text-transform:uppercase;letter-spacing:.05em;border-bottom:1px solid #e0f2fe}
.table td{padding:9px 12px;border-bottom:1px solid #f0f4f8;color:#1e293b}
.table tr:hover td{background:#f0f9ff}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700}
.b-approv{background:rgba(5,150,105,.12);color:#047857}.b-impl{background:rgba(59,130,246,.12);color:#1d4ed8}
.b-review{background:rgba(217,119,6,.12);color:#b45309}.b-emrg{background:rgba(220,38,38,.12);color:#991b1b}
.b-sched{background:rgba(107,114,128,.12);color:#374151}
.login{position:fixed;inset:0;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#fff;border-radius:7px;width:370px;overflow:hidden}
.lh{background:#0f3d6e;border-bottom:2px solid #c4a53e;padding:14px 18px;color:#bae6fd;font-size:13px;font-weight:700}
.lbody{padding:18px}
.fg{margin-bottom:12px}.fg label{display:block;font-size:10.5px;font-weight:700;color:#64748b;margin-bottom:4px;text-transform:uppercase;letter-spacing:.07em}
.fg input{width:100%;padding:8px 10px;border:1px solid #e2e8f0;border-radius:4px;font-size:13px}
.btn{width:100%;padding:9px;background:#0f3d6e;color:#fff;border:none;border-radius:4px;font-size:13px;font-weight:700;cursor:pointer}
.footer{background:#0f3d6e;padding:8px 20px;text-align:center;font-size:10px;color:rgba(255,255,255,.25)}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">📝 ITSM Change Management — Login</div>
<div class="lbody">
<div class="fg"><label>Username</label><input type="text" placeholder="change-manager or sre-lead"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Sign In</button>
</div></div></div>
<div class="hdr"><h1>📝 PUL ITSM — Change Management</h1><p>ServiceNow-compatible | Change Advisory Board | NEXUS-IT</p></div>
<nav class="nav"><a href="#" class="active">Change Requests</a><a href="#">CAB Schedule</a><a href="#">CMDB</a><a href="#">Reports</a></nav>
<div class="main">
<div class="kpis">
<div class="kpi"><div class="n">8</div><div class="l">Open CRs</div></div>
<div class="kpi warn"><div class="n">2</div><div class="l">Awaiting CAB</div></div>
<div class="kpi err"><div class="n">1</div><div class="l">Emergency CR</div></div>
<div class="kpi ok"><div class="n">124</div><div class="l">Closed (30d)</div></div>
</div>
<div class="panel"><div class="ph">Recent Change Requests</div>
<table class="table">
<tr><th>CR Number</th><th>Summary</th><th>Requestor</th><th>Type</th><th>Risk</th><th>Status</th></tr>
<tr><td style="font-family:monospace;font-size:11px">CR-2024-0847</td><td>Vault root token rotation — deferred from Oct maintenance window</td><td>arun.sharma</td><td><span class="badge b-emrg">EMERGENCY</span></td><td style="color:#dc2626">HIGH</td><td><span class="badge b-review">IN REVIEW</span></td></tr>
<tr><td style="font-family:monospace;font-size:11px">CR-2024-0844</td><td>NEXUS-IT LDAP ACL tightening — remove wildcard cn=* reads</td><td>priya.nair</td><td>Normal</td><td style="color:#d97706">MEDIUM</td><td><span class="badge b-approv">APPROVED</span></td></tr>
<tr><td style="font-family:monospace;font-size:11px">CR-2024-0841</td><td>Ansible AWX upgrade to 23.6 — security patches</td><td>devops-admin</td><td>Normal</td><td>LOW</td><td><span class="badge b-sched">SCHEDULED</span></td></tr>
<tr><td style="font-family:monospace;font-size:11px">CR-2024-0838</td><td>Network ACL update — restrict IT-01 to IT-02 lateral movement</td><td>rajiv.menon</td><td>Normal</td><td style="color:#d97706">MEDIUM</td><td><span class="badge b-review">CAB PENDING</span></td></tr>
<tr><td style="font-family:monospace;font-size:11px">CR-2024-0835</td><td>SAML signing cert rotation — expiry 10 Feb 2025</td><td>arun.sharma</td><td>Normal</td><td>LOW</td><td><span class="badge b-impl">IN PROGRESS</span></td></tr>
</table></div></div>
<div class="footer">© 2024 Prabal Urja Limited | ITSM Change Management | NEXUS-IT | Classification: INTERNAL</div>
</body></html>
HTML

# ─── D4: Patch Management Console — port 9402 ────────────────────────────────
make_web_svc "patchmgr" 9402 "itops-m5-patchmgr" "itops-m5-patchmgr"
cat > "${TRAP_DIR}/patchmgr/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Patch Management</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Segoe UI',Arial,sans-serif;background:#f5f5f5;color:#212121;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#1a237e;border-bottom:3px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#c5cae9;font-size:15px;font-weight:700}.hdr p{color:rgba(255,255,255,.35);font-size:11px}
.main{flex:1;padding:20px;max-width:1050px;margin:0 auto;width:100%}
.kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:20px}
.kpi{background:#fff;border:1px solid #e0e0e0;border-radius:6px;padding:14px;border-left:3px solid #1a237e;box-shadow:0 1px 2px rgba(0,0,0,.05)}
.kpi .n{font-size:24px;font-weight:800;color:#1a237e}.kpi .l{font-size:10.5px;color:#9e9e9e;text-transform:uppercase;letter-spacing:.05em;margin-top:3px}
.kpi.crit .n{color:#c62828}.kpi.high .n{color:#e65100}.kpi.ok .n{color:#2e7d32}
.panel{background:#fff;border:1px solid #e0e0e0;border-radius:7px;overflow:hidden;margin-bottom:14px;box-shadow:0 1px 2px rgba(0,0,0,.04)}
.ph{background:#1a237e;color:#c5cae9;padding:10px 14px;font-size:12.5px;font-weight:700;border-bottom:2px solid #c4a53e}
.table{width:100%;border-collapse:collapse;font-size:12.5px}
.table th{text-align:left;padding:8px 12px;background:#e8eaf6;color:#5c6bc0;font-size:10.5px;text-transform:uppercase;letter-spacing:.05em;border-bottom:1px solid #c5cae9}
.table td{padding:9px 12px;border-bottom:1px solid #f5f5f5;color:#212121}
.table tr:hover td{background:#e8eaf6}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700}
.b-crit{background:rgba(198,40,40,.12);color:#c62828}.b-high{background:rgba(230,101,0,.12);color:#e65100}
.b-med{background:rgba(245,158,11,.12);color:#b45309}.b-ok{background:rgba(46,125,50,.12);color:#2e7d32}
.b-pend{background:rgba(26,35,126,.12);color:#283593}
.login{position:fixed;inset:0;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#fff;border-radius:7px;width:360px;overflow:hidden}
.lh{background:#1a237e;border-bottom:2px solid #c4a53e;padding:14px 18px;color:#c5cae9;font-size:13px;font-weight:700}
.lbody{padding:18px}
.fg{margin-bottom:12px}.fg label{display:block;font-size:10.5px;font-weight:700;color:#9e9e9e;margin-bottom:4px;text-transform:uppercase;letter-spacing:.07em}
.fg input{width:100%;padding:8px 10px;border:1px solid #e0e0e0;border-radius:4px;font-size:13px}
.btn{width:100%;padding:9px;background:#1a237e;color:#fff;border:none;border-radius:4px;font-size:13px;font-weight:700;cursor:pointer}
.footer{background:#1a237e;padding:8px 20px;text-align:center;font-size:10px;color:rgba(255,255,255,.25)}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">🩹 Patch Management — Login</div>
<div class="lbody">
<div class="fg"><label>Username</label><input type="text" placeholder="patch-admin or sysops"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Sign In</button>
</div></div></div>
<div class="hdr"><h1>🩹 PUL Patch Management Console</h1><p>Ansible-driven | WSUS / yum-cron | NEXUS-IT Operations</p></div>
<div class="main">
<div class="kpis">
<div class="kpi crit"><div class="n">3</div><div class="l">Critical Unpatched</div></div>
<div class="kpi high"><div class="n">14</div><div class="l">High Unpatched</div></div>
<div class="kpi"><div class="n">47</div><div class="l">Hosts Managed</div></div>
<div class="kpi ok"><div class="n">39</div><div class="l">Compliant Hosts</div></div>
</div>
<div class="panel"><div class="ph">Hosts Requiring Attention</div>
<table class="table">
<tr><th>Hostname</th><th>OS</th><th>Missing Patches</th><th>Highest Severity</th><th>Last Scan</th><th>Status</th></tr>
<tr><td style="font-family:monospace;font-size:11px">itops-vault</td><td>Ubuntu 22.04</td><td>7</td><td><span class="badge b-crit">CRITICAL</span></td><td>Nov 15</td><td><span class="badge b-pend">PENDING</span></td></tr>
<tr><td style="font-family:monospace;font-size:11px">itops-git</td><td>Ubuntu 22.04</td><td>4</td><td><span class="badge b-high">HIGH</span></td><td>Nov 15</td><td><span class="badge b-pend">PENDING</span></td></tr>
<tr><td style="font-family:monospace;font-size:11px">itgw-mailrelay</td><td>Debian 12</td><td>2</td><td><span class="badge b-med">MEDIUM</span></td><td>Nov 15</td><td><span class="badge b-pend">APPROVED</span></td></tr>
<tr><td style="font-family:monospace;font-size:11px">dev-jump-host</td><td>Ubuntu 22.04</td><td>1</td><td><span class="badge b-crit">CRITICAL</span></td><td>Nov 14</td><td><span class="badge b-pend">PENDING</span></td></tr>
<tr><td style="font-family:monospace;font-size:11px">itgw-sso</td><td>Ubuntu 22.04</td><td>0</td><td>—</td><td>Nov 15</td><td><span class="badge b-ok">COMPLIANT</span></td></tr>
</table></div></div>
<div class="footer">© 2024 Prabal Urja Limited | Patch Management | NEXUS-IT Operations | Classification: INTERNAL</div>
</body></html>
HTML

# ─── D5: Config Drift Detector — port 9403 ────────────────────────────────────
make_web_svc "driftdetect" 9403 "itops-m5-driftdetect" "itops-m5-driftdetect"
cat > "${TRAP_DIR}/driftdetect/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Config Drift Detector</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Segoe UI',Arial,monospace;background:#0d1117;color:#c9d1d9;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#161b22;border-bottom:2px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#c4a53e;font-size:14px;font-weight:700}.hdr p{color:rgba(255,255,255,.35);font-size:11px}
.main{flex:1;padding:20px;max-width:1000px;margin:0 auto;width:100%}
.drift-card{background:#161b22;border:1px solid #21262d;border-radius:8px;margin-bottom:10px;overflow:hidden}
.dc-hdr{display:flex;align-items:center;gap:10px;padding:12px 14px;border-bottom:1px solid #21262d}
.dc-host{font-size:13px;font-weight:700;font-family:'Courier New',monospace;color:#58a6ff;flex:1}
.dc-time{font-size:11px;color:#8b949e}
.diff-block{background:#0d1117;padding:10px 14px;font-family:'Courier New',monospace;font-size:11px;line-height:1.7}
.diff-add{color:#3fb950;display:block}.diff-rem{color:#f85149;display:block}.diff-ctx{color:#8b949e;display:block}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700;font-family:sans-serif}
.b-crit{background:rgba(248,81,73,.15);color:#f85149}.b-warn{background:rgba(245,158,11,.15);color:#f59e0b}
.b-ok{background:rgba(63,185,80,.15);color:#3fb950}
.kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:16px}
.kpi{background:#161b22;border:1px solid #21262d;border-radius:6px;padding:12px}
.kpi .n{font-size:22px;font-weight:800}.kpi .l{font-size:10px;color:#8b949e;text-transform:uppercase;letter-spacing:.06em;margin-top:3px}
.kpi.crit .n{color:#f85149}.kpi.warn .n{color:#f59e0b}.kpi.ok .n{color:#3fb950}
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
<div class="lh">⚡ Config Drift Detector — Login</div>
<div class="lbody">
<div class="fg"><label>Username</label><input type="text" placeholder="sre-lead or devops-admin"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Sign In</button>
</div></div></div>
<div class="hdr"><h1>⚡ PUL Config Drift Detector</h1><p>Ansible idempotency checker | Git-diff vs live | NEXUS-IT</p></div>
<div class="main">
<div class="kpis">
<div class="kpi crit"><div class="n">3</div><div class="l">Critical Drift</div></div>
<div class="kpi warn"><div class="n">6</div><div class="l">Minor Drift</div></div>
<div class="kpi ok"><div class="n">38</div><div class="l">Compliant</div></div>
<div class="kpi"><div class="n">Nov 15 10:00</div><div class="l">Last Scan</div></div>
</div>
<div class="drift-card">
<div class="dc-hdr"><span class="dc-host">itops-vault (203.0.2.30)</span><span class="badge b-crit">CRITICAL DRIFT</span><span class="dc-time">Detected: 10:02 IST</span></div>
<div class="diff-block">
<span class="diff-ctx">--- expected: /etc/vault.d/vault.hcl (from git)</span>
<span class="diff-ctx">+++ live:     /etc/vault.d/vault.hcl</span>
<span class="diff-rem">- storage "raft" { path = "/opt/vault/data" }</span>
<span class="diff-add">+ storage "inmem" {}  # DEV MODE — data not persisted!</span>
<span class="diff-rem">- ui = false</span>
<span class="diff-add">+ ui = true</span>
<span class="diff-rem">- api_addr = "https://vault.prabalurja.in:8200"</span>
<span class="diff-add">+ # api_addr commented out — dev bind to 0.0.0.0</span>
</div></div>
<div class="drift-card">
<div class="dc-hdr"><span class="dc-host">itgw-netmgmt (203.0.1.40)</span><span class="badge b-warn">WARN DRIFT</span><span class="dc-time">Detected: 10:02 IST</span></div>
<div class="diff-block">
<span class="diff-ctx">--- expected: /etc/snmp/snmpd.conf</span>
<span class="diff-ctx">+++ live: /etc/snmp/snmpd.conf</span>
<span class="diff-rem">- rocommunity pul-snmp-r0-2024 203.0.2.40</span>
<span class="diff-add">+ rocommunity public</span>
</div></div>
</div>
</body></html>
HTML

# ─── D6: Release Pipeline Visualizer — port 9404 ──────────────────────────────
make_web_svc "releasepipe" 9404 "itops-m5-releasepipe" "itops-m5-releasepipe"
cat > "${TRAP_DIR}/releasepipe/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Release Pipeline</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Segoe UI',Arial,sans-serif;background:#0f0f23;color:#e2e8f0;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#1a1a3e;border-bottom:2px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#c4a53e;font-size:15px;font-weight:700}.hdr p{color:rgba(255,255,255,.3);font-size:11px}
.main{flex:1;padding:20px;max-width:1050px;margin:0 auto;width:100%}
.pipeline-card{background:#1a1a3e;border:1px solid #2d2d5e;border-radius:8px;margin-bottom:14px;padding:16px}
.pc-hdr{display:flex;align-items:center;gap:10px;margin-bottom:14px}
.pc-name{font-size:14px;font-weight:700;color:#a78bfa;flex:1}
.pc-meta{font-size:11px;color:#64748b}
.stages{display:flex;align-items:center;gap:0}
.stage{text-align:center;position:relative;flex:1}
.stage::after{content:'→';position:absolute;right:-8px;top:50%;transform:translateY(-50%);color:#4a4a6e;font-size:14px;z-index:1}
.stage:last-child::after{display:none}
.stage-box{display:inline-flex;flex-direction:column;align-items:center;gap:4px;padding:10px 8px;border-radius:6px;width:90%;cursor:pointer;transition:all .1s}
.stage-box.pass{background:rgba(63,185,80,.12);border:1px solid rgba(63,185,80,.25)}
.stage-box.fail{background:rgba(248,81,73,.12);border:1px solid rgba(248,81,73,.25)}
.stage-box.skip{background:rgba(107,114,128,.08);border:1px solid rgba(107,114,128,.2)}
.stage-box.run{background:rgba(167,139,250,.12);border:1px solid rgba(167,139,250,.25)}
.stage-icon{font-size:18px}.stage-name{font-size:10.5px;font-weight:600;color:#e2e8f0}
.stage-dur{font-size:9.5px;color:#64748b}
.pc-commit{font-size:11px;color:#64748b;margin-top:10px;font-family:monospace}
.login{position:fixed;inset:0;background:rgba(0,0,0,.7);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#1a1a3e;border:1px solid #2d2d5e;border-radius:7px;width:360px;overflow:hidden}
.lh{background:#0f0f23;border-bottom:2px solid #c4a53e;padding:14px;color:#c4a53e;font-size:13px;font-weight:700}
.lbody{padding:16px}
.fg{margin-bottom:12px}.fg label{display:block;font-size:10px;color:#64748b;text-transform:uppercase;letter-spacing:.07em;margin-bottom:4px}
.fg input{width:100%;padding:8px 10px;background:#0f0f23;border:1px solid #2d2d5e;border-radius:4px;color:#e2e8f0;font-size:12px;outline:none}
.fg input:focus{border-color:#a78bfa}
.btn{width:100%;padding:9px;background:#a78bfa;color:#0f0f23;border:none;border-radius:4px;font-size:13px;font-weight:800;cursor:pointer}
.footer{background:#1a1a3e;border-top:1px solid #2d2d5e;padding:8px 20px;text-align:center;font-size:10px;color:rgba(255,255,255,.2)}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">🚀 Release Pipeline — Login</div>
<div class="lbody">
<div class="fg"><label>Username</label><input type="text" placeholder="devops-admin or svc-cicd"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Sign In</button>
</div></div></div>
<div class="hdr"><h1>🚀 PUL Release Pipeline Visualizer</h1><p>AWX / CI-CD Orchestration | pul-cicd.prabalurja.in</p></div>
<div class="main">
<div class="pipeline-card">
<div class="pc-hdr"><span class="pc-name">pul-infra-config — main branch deploy</span><span class="pc-meta">Run #JOB-20241115-018 · triggered by: svc-cicd · Nov 15 10:12 IST</span></div>
<div class="stages">
<div class="stage"><div class="stage-box pass" onclick="alert('Checkout OK — commit 3c2b1a0')"><div class="stage-icon">✅</div><div class="stage-name">Checkout</div><div class="stage-dur">8s</div></div></div>
<div class="stage"><div class="stage-box pass" onclick="alert('Lint passed — 0 errors')"><div class="stage-icon">✅</div><div class="stage-name">Lint</div><div class="stage-dur">24s</div></div></div>
<div class="stage"><div class="stage-box pass" onclick="alert('Unit tests: 47/47 passed')"><div class="stage-icon">✅</div><div class="stage-name">Test</div><div class="stage-dur">1m 12s</div></div></div>
<div class="stage"><div class="stage-box pass" onclick="alert('Harbor push: pul-internal/nexus-portal:v1.4.2')"><div class="stage-icon">✅</div><div class="stage-name">Build &amp; Push</div><div class="stage-dur">3m 44s</div></div></div>
<div class="stage"><div class="stage-box fail" onclick="alert('FAIL: Ansible playbook deploy-vault.yml — Vault provider: 403 Forbidden. Root token expired. Job output exposed in AWX UI.')"><div class="stage-icon">❌</div><div class="stage-name">Deploy</div><div class="stage-dur">2m 01s</div></div></div>
<div class="stage"><div class="stage-box skip" onclick="alert('Skipped — deploy failed')"><div class="stage-icon">⏭</div><div class="stage-name">Smoke Test</div><div class="stage-dur">—</div></div></div>
</div>
<div class="pc-commit">commit 3c2b1a0 — "fix: update vault token rotation ansible vars" — arun.sharma · Vault token in job env: VAULT_TOKEN=pul-vault-root-s3cr3t-2024-gridfall</div>
</div>
<div class="pipeline-card">
<div class="pc-hdr"><span class="pc-name">pul-monitoring-stack — scheduled nightly</span><span class="pc-meta">Run #JOB-20241114-047 · triggered by: cron · Nov 14 23:00 IST</span></div>
<div class="stages">
<div class="stage"><div class="stage-box pass"><div class="stage-icon">✅</div><div class="stage-name">Checkout</div><div class="stage-dur">6s</div></div></div>
<div class="stage"><div class="stage-box pass"><div class="stage-icon">✅</div><div class="stage-name">Lint</div><div class="stage-dur">18s</div></div></div>
<div class="stage"><div class="stage-box pass"><div class="stage-icon">✅</div><div class="stage-name">Test</div><div class="stage-dur">44s</div></div></div>
<div class="stage"><div class="stage-box run"><div class="stage-icon">⏳</div><div class="stage-name">Deploy</div><div class="stage-dur">running</div></div></div>
<div class="stage"><div class="stage-box skip"><div class="stage-icon">⏭</div><div class="stage-name">Smoke Test</div><div class="stage-dur">—</div></div></div>
<div class="stage"><div class="stage-box skip"><div class="stage-icon">⏭</div><div class="stage-name">Notify</div><div class="stage-dur">—</div></div></div>
</div>
</div></div>
<div class="footer">© 2024 Prabal Urja Limited | Release Pipeline Visualizer | DevOps Division</div>
</body></html>
HTML

# ─── D7: Rundeck Job Scheduler — port 9405 ────────────────────────────────────
make_web_svc "rundeck" 9405 "itops-m5-rundeck" "itops-m5-rundeck"
cat > "${TRAP_DIR}/rundeck/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Rundeck</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',Arial,sans-serif;background:#f4f5f7;color:#172b4d;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#0f4c81;border-bottom:3px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr .brand{display:flex;align-items:center;gap:10px}
.hdr .logo{font-size:20px}.hdr h1{color:#e3f2fd;font-size:16px;font-weight:700}
.hdr p{color:rgba(255,255,255,.35);font-size:11px}
.nav{background:#1565c0;border-bottom:1px solid #0f4c81;display:flex;padding:0 20px}
.nav a{color:rgba(255,255,255,.5);font-size:12.5px;padding:9px 14px;border-bottom:2px solid transparent;text-decoration:none}
.nav a.active{color:#e3f2fd;border-color:#c4a53e}
.main{flex:1;padding:20px;max-width:1000px;margin:0 auto;width:100%}
.panel{background:#fff;border:1px solid #dfe1e6;border-radius:6px;overflow:hidden;margin-bottom:14px;box-shadow:0 1px 2px rgba(0,0,0,.05)}
.ph{background:#0f4c81;color:#e3f2fd;padding:10px 14px;font-size:12.5px;font-weight:600;border-bottom:2px solid #c4a53e;display:flex;justify-content:space-between;align-items:center}
.ph .count{font-size:10.5px;color:rgba(255,255,255,.4)}
.job-row{display:flex;align-items:center;gap:10px;padding:10px 14px;border-bottom:1px solid #f4f5f7;font-size:12.5px}
.job-row:last-child{border-bottom:none}.job-row:hover{background:#f4f5f7}
.job-name{flex:1;font-weight:600;color:#0f4c81}
.job-proj{font-size:11px;color:#6b778c;width:140px}
.job-last{font-size:11px;color:#6b778c;width:120px;text-align:right}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700}
.b-success{background:rgba(0,135,90,.12);color:#00603a}.b-fail{background:rgba(222,53,11,.12);color:#ae2a19}
.b-run{background:rgba(0,101,255,.12);color:#0052cc}.b-sched{background:rgba(107,114,128,.12);color:#374151}
.login{position:fixed;inset:0;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#fff;border-radius:6px;width:380px;overflow:hidden;box-shadow:0 8px 24px rgba(0,0,0,.15)}
.lh{background:#0f4c81;border-bottom:2px solid #c4a53e;padding:16px 20px;color:#e3f2fd;font-size:14px;font-weight:700}
.lbody{padding:20px}
.fg{margin-bottom:14px}.fg label{display:block;font-size:11px;font-weight:700;color:#6b778c;margin-bottom:4px;text-transform:uppercase;letter-spacing:.06em}
.fg input{width:100%;padding:9px 12px;border:1px solid #dfe1e6;border-radius:4px;font-size:13px}
.fg input:focus{outline:none;border-color:#0f4c81}
.btn{width:100%;padding:10px;background:#0f4c81;color:#fff;border:none;border-radius:4px;font-size:14px;font-weight:700;cursor:pointer}
.footer{background:#0f4c81;padding:8px 20px;text-align:center;font-size:10px;color:rgba(255,255,255,.25)}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">⚙ Rundeck — Sign In</div>
<div class="lbody">
<div class="fg"><label>Username</label><input type="text" placeholder="rundeck-admin or svc-automation"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Sign In</button>
</div></div></div>
<div class="hdr"><div class="brand"><span class="logo">⚙</span><h1>Rundeck</h1></div><p>pul-rundeck.prabalurja.in | IT Automation | NEXUS-IT DevOps</p></div>
<nav class="nav"><a href="#" class="active">Jobs</a><a href="#">Activity</a><a href="#">Projects</a><a href="#">System</a></nav>
<div class="main">
<div class="panel">
<div class="ph">Scheduled Jobs — pul-infrastructure <span class="count">12 jobs</span></div>
<div class="job-row"><span class="job-name">vault-token-renewal</span><span class="job-proj">pul-infra</span><span class="badge b-fail">FAILED</span><span class="job-last">Nov 14 22:00</span></div>
<div class="job-row"><span class="job-name">ldap-user-sync</span><span class="job-proj">pul-infra</span><span class="badge b-success">SUCCESS</span><span class="job-last">Nov 15 06:00</span></div>
<div class="job-row"><span class="job-name">ansible-playbook-network-acl-push</span><span class="job-proj">pul-network</span><span class="badge b-success">SUCCESS</span><span class="job-last">Nov 15 04:00</span></div>
<div class="job-row"><span class="job-name">backup-config-to-s3</span><span class="job-proj">pul-infra</span><span class="badge b-run">RUNNING</span><span class="job-last">Nov 15 11:00</span></div>
<div class="job-row"><span class="job-name">certificate-expiry-check</span><span class="job-proj">pul-pki</span><span class="badge b-success">SUCCESS</span><span class="job-last">Nov 15 08:00</span></div>
<div class="job-row"><span class="job-name">patch-compliance-report</span><span class="job-proj">pul-infra</span><span class="badge b-sched">SCHEDULED</span><span class="job-last">Nov 15 23:00</span></div>
<div class="job-row"><span class="job-name">snmp-community-rotation</span><span class="job-proj">pul-network</span><span class="badge b-fail">FAILED</span><span class="job-last">Nov 14 03:00</span></div>
</div></div>
<div class="footer">Rundeck 4.17.3 | © 2024 Prabal Urja Limited | IT Automation | NEXUS-IT DevOps</div>
</body></html>
HTML

echo ""
echo "============================================================"
echo "  RNG-IT-02 | M5 itops-ansible — Honeytraps Active"
echo "  D1: SaltStack ZMQ banner (socket) → port 4505"
echo "  D2: Terraform Cloud IaC Portal    → port 9400"
echo "  D3: ITSM Change Management        → port 9401"
echo "  D4: Patch Management Console      → port 9402"
echo "  D5: Config Drift Detector         → port 9403"
echo "  D6: Release Pipeline Visualizer   → port 9404"
echo "  D7: Rundeck Job Scheduler         → port 9405"
echo "  Logs: ${LOG_DIR}/itops-m5-*.log"
echo "============================================================"
