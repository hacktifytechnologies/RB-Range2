#!/usr/bin/env bash
# =============================================================================
# RNG-IT-02 | M2 — itops-git | Honeytraps (7 decoys)
# Ports:
#   9418  — Git daemon banner (socket)
#   8929  — Gerrit Code Review (web)
#   7990  — Nexus Repository Manager (web)
#   3001  — SonarQube Code Analysis (web)
#   9000  — Dependency-Track SCA (web)
#   8888  — Harbor Container Registry (web)
#   8080  — Code Coverage Portal (web)  [using alt port since 3000 is gitea]
# =============================================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
TRAP_DIR="/opt/pul-honeytrap/itops-m2"; LOG_DIR="/var/log/pul-honeytrap"
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

# ─── D1: Git Daemon Banner — port 9418 ────────────────────────────────────────
cat > "${TRAP_DIR}/gitd-banner.py" << 'PYEOF'
#!/usr/bin/env python3
import socket, threading, logging
LOG = "/var/log/pul-honeytrap/itops-m2-gitd.log"
logging.basicConfig(filename=LOG, level=logging.WARNING, format="%(asctime)s %(message)s")
# Git protocol pkt-line: ERR message
def pkt_line(msg):
    raw = msg.encode()
    length = len(raw) + 4  # 4 bytes for the length hex itself
    return f"{length:04x}".encode() + raw
ERR_PKT = pkt_line("ERR access denied: not-authorized\n") + b"0000"
def handle(conn, addr):
    logging.warning(f"GIT_DAEMON_CONNECT|src={addr[0]}")
    try:
        data = conn.recv(512)
        if data:
            logging.warning(f"GIT_DAEMON_REQUEST|src={addr[0]}|data={repr(data[:80])}")
        conn.sendall(ERR_PKT)
    except: pass
    finally: conn.close()
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("0.0.0.0", 9418)); srv.listen(10)
while True:
    c, a = srv.accept()
    threading.Thread(target=handle, args=(c, a), daemon=True).start()
PYEOF
make_svc "itops-m2-gitd" "${TRAP_DIR}/gitd-banner.py" 9418

# ─── D2: Gerrit Code Review — port 8929 ───────────────────────────────────────
mkdir -p "${TRAP_DIR}/gerrit"
cat > "${TRAP_DIR}/gerrit/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Gerrit Code Review</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Roboto','Segoe UI',Arial,sans-serif;background:#fff;color:#212121;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#1565c0;border-bottom:3px solid #c4a53e;padding:0 20px;height:56px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#fff;font-size:16px;font-weight:500;letter-spacing:.02em}.hdr .meta{color:rgba(255,255,255,.5);font-size:11px}
.tabs{background:#1976d2;display:flex;padding:0 20px;border-bottom:1px solid #1565c0}
.tab{color:rgba(255,255,255,.6);font-size:13px;padding:10px 16px;cursor:pointer;border-bottom:2px solid transparent;letter-spacing:.03em}
.tab.active{color:#fff;border-color:#c4a53e}
.main{flex:1;padding:20px;max-width:1000px;margin:0 auto;width:100%}
.section{margin-bottom:20px}
.section-hdr{font-size:13px;font-weight:500;color:#1565c0;margin-bottom:10px;border-bottom:1px solid #e3f2fd;padding-bottom:6px;text-transform:uppercase;letter-spacing:.06em}
.change-row{display:flex;align-items:center;gap:10px;padding:10px 0;border-bottom:1px solid #f5f5f5;font-size:13px}
.change-row:last-child{border-bottom:none}.change-row:hover{background:#f8f9fa;margin:0 -10px;padding:10px}
.cr-num{font-family:monospace;font-size:11px;color:#1565c0;width:70px;flex-shrink:0}
.cr-title{flex:1;color:#212121;font-weight:500}
.cr-owner{color:#9e9e9e;font-size:12px;width:140px;text-align:right}
.cr-status{font-size:11px;font-weight:700;padding:2px 8px;border-radius:3px;margin-left:8px}
.s-review{background:#e3f2fd;color:#1565c0}.s-merge{background:#e8f5e9;color:#2e7d32}
.s-verify{background:#fff8e1;color:#f57f17}.s-conflict{background:#ffebee;color:#c62828}
.login{position:fixed;inset:0;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#fff;border-radius:4px;width:380px;overflow:hidden;box-shadow:0 8px 24px rgba(0,0,0,.2)}
.lh{background:#1565c0;border-bottom:3px solid #c4a53e;padding:16px 20px;color:#fff;font-size:14px;font-weight:500}
.lbody{padding:20px}
.fg{margin-bottom:14px}.fg label{display:block;font-size:11px;font-weight:500;color:#757575;margin-bottom:5px;text-transform:uppercase;letter-spacing:.06em}
.fg input{width:100%;padding:9px 12px;border:1px solid #ddd;border-radius:3px;font-size:13px}
.fg input:focus{outline:none;border-color:#1565c0;box-shadow:0 0 0 2px rgba(21,101,192,.12)}
.btn{width:100%;padding:10px;background:#1565c0;color:#fff;border:none;border-radius:3px;font-size:14px;font-weight:500;cursor:pointer;letter-spacing:.03em}
.footer{background:#1565c0;padding:8px 20px;text-align:center;font-size:10px;color:rgba(255,255,255,.3)}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">🔍 Gerrit Code Review — Sign In</div>
<div class="lbody">
<div class="fg"><label>Username</label><input type="text" placeholder="username or svc-cicd"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="HTTP password (not LDAP)"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">SIGN IN</button>
</div></div></div>
<div class="hdr"><h1>Gerrit Code Review</h1><div class="meta">Prabal Urja Limited — DevOps | pul-gerrit.prabalurja.in</div></div>
<div class="tabs"><div class="tab active">Changes</div><div class="tab">Repositories</div><div class="tab">Groups</div><div class="tab">Admin</div></div>
<div class="main">
<div class="section"><div class="section-hdr">Open Changes</div>
<div class="change-row"><span class="cr-num">CR-2847</span><span class="cr-title">feat: Add Vault dev-mode guard to systemd unit</span><span class="cr-status s-review">NEEDS REVIEW</span><span class="cr-owner">arun.sharma</span></div>
<div class="change-row"><span class="cr-num">CR-2846</span><span class="cr-title">fix: Remove .env from gitignore exclusion — enforce always</span><span class="cr-status s-verify">NEEDS VERIFY</span><span class="cr-owner">devops-bot</span></div>
<div class="change-row"><span class="cr-num">CR-2844</span><span class="cr-title">security: Rotate svc-cicd LDAP password — 90 day policy</span><span class="cr-status s-conflict">MERGE CONFLICT</span><span class="cr-owner">priya.nair</span></div>
<div class="change-row"><span class="cr-num">CR-2841</span><span class="cr-title">infra: Migrate Prometheus scrape auth to basic_auth file</span><span class="cr-status s-merge">MERGED</span><span class="cr-owner">svc-cicd</span></div>
</div></div>
<div class="footer">Gerrit 3.9.0 | © 2024 Prabal Urja Limited | DevOps Division</div>
</body></html>
HTML
cat > "${TRAP_DIR}/gerrit/server.py" << 'PYEOF'
#!/usr/bin/env python3
import http.server,logging,os
LOG="/var/log/pul-honeytrap/itops-m2-gerrit.log"
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
http.server.HTTPServer(("0.0.0.0",8929),H).serve_forever()
PYEOF
make_svc "itops-m2-gerrit" "${TRAP_DIR}/gerrit/server.py" 8929

# ─── D3: Nexus Repository Manager — port 7990 ─────────────────────────────────
mkdir -p "${TRAP_DIR}/nexus"
cat > "${TRAP_DIR}/nexus/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Nexus Repository Manager</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',Arial,sans-serif;background:#f4f4f4;color:#212529;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#1b2a38;border-bottom:3px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#62c8e5;font-size:16px;font-weight:700}.hdr .sub{color:rgba(255,255,255,.35);font-size:11px}
.nav{background:#243547;border-bottom:1px solid #1b2a38;display:flex;padding:0 20px}
.nav a{color:rgba(255,255,255,.5);font-size:12.5px;padding:9px 14px;border-bottom:2px solid transparent;text-decoration:none}
.nav a.active{color:#62c8e5;border-color:#c4a53e}
.main{flex:1;padding:20px;max-width:1000px;margin:0 auto;width:100%}
.repo-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-bottom:16px}
.repo-card{background:#fff;border:1px solid #dee2e6;border-radius:6px;padding:16px;box-shadow:0 1px 3px rgba(0,0,0,.05)}
.repo-card .rtype{font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.08em;color:#62c8e5;margin-bottom:6px}
.repo-card .rname{font-size:14px;font-weight:700;color:#1b2a38;margin-bottom:4px}
.repo-card .rformat{font-size:11.5px;color:#6c757d}
.repo-card .rsize{font-size:11px;color:#adb5bd;margin-top:8px;font-family:monospace}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700}
.b-hosted{background:rgba(98,200,229,.15);color:#0e7a99}.b-proxy{background:rgba(40,167,69,.12);color:#155724}
.b-group{background:rgba(108,117,125,.12);color:#343a40}
.login{position:fixed;inset:0;background:rgba(0,0,0,.6);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#fff;border-radius:6px;width:380px;overflow:hidden;box-shadow:0 8px 24px rgba(0,0,0,.2)}
.lh{background:#1b2a38;border-bottom:2px solid #c4a53e;padding:16px 20px;color:#62c8e5;font-size:14px;font-weight:700}
.lbody{padding:20px}
.fg{margin-bottom:14px}.fg label{display:block;font-size:11px;font-weight:700;color:#6c757d;margin-bottom:4px;text-transform:uppercase;letter-spacing:.06em}
.fg input{width:100%;padding:9px 12px;border:1px solid #dee2e6;border-radius:4px;font-size:13px}
.fg input:focus{outline:none;border-color:#62c8e5}
.btn{width:100%;padding:10px;background:#1b2a38;color:#62c8e5;border:none;border-radius:4px;font-size:13px;font-weight:700;cursor:pointer}
.footer{background:#1b2a38;padding:8px 20px;text-align:center;font-size:10px;color:rgba(255,255,255,.25)}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">📦 Nexus Repository — Sign In</div>
<div class="lbody">
<div class="fg"><label>Username</label><input type="text" placeholder="admin or svc-cicd"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Nexus password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Sign In</button>
</div></div></div>
<div class="hdr"><h1>Nexus Repository Manager</h1><div class="sub">Prabal Urja Limited — Artifact Registry | pul-nexus.prabalurja.in</div></div>
<nav class="nav"><a href="#" class="active">Browse</a><a href="#">Search</a><a href="#">Upload</a><a href="#">Administration</a></nav>
<div class="main">
<div class="repo-grid">
<div class="repo-card"><div class="rtype"><span class="badge b-hosted">HOSTED</span></div><div class="rname">pul-maven-releases</div><div class="rformat">Maven2 — Release artifacts</div><div class="rsize">Size: 4.2 GB | 1,241 components</div></div>
<div class="repo-card"><div class="rtype"><span class="badge b-proxy">PROXY</span></div><div class="rname">pul-pypi-proxy</div><div class="rformat">PyPI — Python packages mirror</div><div class="rsize">Size: 28.4 GB | 84,221 components</div></div>
<div class="repo-card"><div class="rtype"><span class="badge b-hosted">HOSTED</span></div><div class="rname">pul-docker-internal</div><div class="rformat">Docker — Internal images</div><div class="rsize">Size: 14.1 GB | 87 images</div></div>
<div class="repo-card"><div class="rtype"><span class="badge b-proxy">PROXY</span></div><div class="rname">pul-npm-proxy</div><div class="rformat">npm — Node.js packages</div><div class="rsize">Size: 11.2 GB | 42,881 components</div></div>
<div class="repo-card"><div class="rtype"><span class="badge b-hosted">HOSTED</span></div><div class="rname">pul-ansible-roles</div><div class="rformat">Raw — Ansible roles & playbooks</div><div class="rsize">Size: 240 MB | 34 components</div></div>
<div class="repo-card"><div class="rtype"><span class="badge b-group">GROUP</span></div><div class="rname">pul-all-maven</div><div class="rformat">Maven2 — Group (hosted + proxy)</div><div class="rsize">Virtual — 2 repositories</div></div>
</div></div>
<div class="footer">Nexus Repository Manager 3.62.0 | © 2024 Prabal Urja Limited | DevOps Division</div>
</body></html>
HTML
cat > "${TRAP_DIR}/nexus/server.py" << 'PYEOF'
#!/usr/bin/env python3
import http.server,logging,os
LOG="/var/log/pul-honeytrap/itops-m2-nexus.log"
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
http.server.HTTPServer(("0.0.0.0",7990),H).serve_forever()
PYEOF
make_svc "itops-m2-nexus" "${TRAP_DIR}/nexus/server.py" 7990

# ─── D4: SonarQube — port 3001 ────────────────────────────────────────────────
mkdir -p "${TRAP_DIR}/sonarqube"
cat > "${TRAP_DIR}/sonarqube/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL SonarQube</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',Arial,sans-serif;background:#f3f3f3;color:#3c3c3c;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#236a97;border-bottom:3px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#fff;font-size:16px;font-weight:700}.hdr .sub{color:rgba(255,255,255,.4);font-size:11px}
.main{flex:1;padding:20px;max-width:1000px;margin:0 auto;width:100%}
.proj-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:14px}
.proj-card{background:#fff;border:1px solid #ddd;border-radius:4px;padding:16px;box-shadow:0 1px 3px rgba(0,0,0,.05)}
.proj-card .pname{font-size:14px;font-weight:700;color:#236a97;margin-bottom:10px}
.metrics-row{display:flex;gap:12px}
.metric-box{text-align:center;flex:1}
.metric-box .grade{font-size:22px;font-weight:800;width:36px;height:36px;border-radius:4px;display:inline-flex;align-items:center;justify-content:center;margin-bottom:4px}
.grade-a{background:#00aa00;color:#fff}.grade-b{background:#7ec500;color:#fff}
.grade-c{background:#ff9900;color:#fff}.grade-d{background:#cc0000;color:#fff}
.metric-box .label{font-size:10px;color:#999;text-transform:uppercase;letter-spacing:.04em}
.metric-box .count{font-size:12px;font-weight:600;color:#3c3c3c;margin-top:2px}
.login{position:fixed;inset:0;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#fff;border-radius:4px;width:380px;overflow:hidden;box-shadow:0 8px 24px rgba(0,0,0,.2)}
.lh{background:#236a97;border-bottom:3px solid #c4a53e;padding:16px 20px;color:#fff;font-size:14px;font-weight:700}
.lbody{padding:20px}
.fg{margin-bottom:14px}.fg label{display:block;font-size:11px;font-weight:700;color:#999;margin-bottom:4px;text-transform:uppercase;letter-spacing:.06em}
.fg input{width:100%;padding:8px 12px;border:1px solid #ddd;border-radius:3px;font-size:13px}
.fg input:focus{outline:none;border-color:#236a97}
.btn{width:100%;padding:10px;background:#236a97;color:#fff;border:none;border-radius:3px;font-size:14px;font-weight:700;cursor:pointer}
.footer{background:#236a97;padding:8px 20px;text-align:center;font-size:10px;color:rgba(255,255,255,.3)}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">🔎 SonarQube — Log In</div>
<div class="lbody">
<div class="fg"><label>Login</label><input type="text" placeholder="admin or sonar-user"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">LOG IN</button>
</div></div></div>
<div class="hdr"><h1>SonarQube</h1><div class="sub">Prabal Urja Limited — Code Quality | pul-sonar.prabalurja.in</div></div>
<div class="main"><div class="proj-grid">
<div class="proj-card"><div class="pname">pul-infra-config</div>
<div class="metrics-row">
<div class="metric-box"><div class="grade grade-c">C</div><div class="label">Reliability</div><div class="count">14 bugs</div></div>
<div class="metric-box"><div class="grade grade-d">D</div><div class="label">Security</div><div class="count">3 vulns ⚠</div></div>
<div class="metric-box"><div class="grade grade-b">B</div><div class="label">Maintainability</div><div class="count">47 smells</div></div>
<div class="metric-box"><div class="grade grade-a">A</div><div class="label">Coverage</div><div class="count">82%</div></div>
</div></div>
<div class="proj-card"><div class="pname">pul-nexus-portal</div>
<div class="metrics-row">
<div class="metric-box"><div class="grade grade-a">A</div><div class="label">Reliability</div><div class="count">0 bugs</div></div>
<div class="metric-box"><div class="grade grade-b">B</div><div class="label">Security</div><div class="count">1 vuln</div></div>
<div class="metric-box"><div class="grade grade-a">A</div><div class="label">Maintainability</div><div class="count">12 smells</div></div>
<div class="metric-box"><div class="grade grade-b">B</div><div class="label">Coverage</div><div class="count">74%</div></div>
</div></div>
</div></div>
<div class="footer">SonarQube 10.3 Community | © 2024 Prabal Urja Limited | DevOps Division</div>
</body></html>
HTML
cat > "${TRAP_DIR}/sonarqube/server.py" << 'PYEOF'
#!/usr/bin/env python3
import http.server,logging,os
LOG="/var/log/pul-honeytrap/itops-m2-sonarqube.log"
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
http.server.HTTPServer(("0.0.0.0",3001),H).serve_forever()
PYEOF
make_svc "itops-m2-sonarqube" "${TRAP_DIR}/sonarqube/server.py" 3001

# ─── D5: Dependency-Track SCA — port 9000 ─────────────────────────────────────
mkdir -p "${TRAP_DIR}/deptrack"
cat > "${TRAP_DIR}/deptrack/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Dependency-Track</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Segoe UI',Arial,sans-serif;background:#0d1117;color:#c9d1d9;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#1a1f2e;border-bottom:2px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#c4a53e;font-size:15px;font-weight:700}.hdr p{color:rgba(255,255,255,.35);font-size:11px}
.main{flex:1;padding:20px;max-width:1000px;margin:0 auto;width:100%}
.kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:16px}
.kpi{background:#1a1f2e;border:1px solid #21262d;border-radius:6px;padding:12px}
.kpi .n{font-size:22px;font-weight:800;color:#58a6ff}.kpi .l{font-size:10px;color:#8b949e;text-transform:uppercase;letter-spacing:.06em;margin-top:3px}
.kpi.crit .n{color:#f85149}.kpi.high .n{color:#f59e0b}.kpi.ok .n{color:#3fb950}
.panel{background:#1a1f2e;border:1px solid #21262d;border-radius:6px;overflow:hidden;margin-bottom:12px}
.ph{background:#21262d;border-bottom:1px solid #30363d;padding:9px 14px;font-size:12px;font-weight:600;color:#c4a53e}
.table{width:100%;border-collapse:collapse;font-size:12px}
.table th{text-align:left;padding:7px 12px;background:#0d1117;color:#8b949e;font-size:10px;text-transform:uppercase;letter-spacing:.06em;border-bottom:1px solid #21262d}
.table td{padding:8px 12px;border-bottom:1px solid #1a1f2e;color:#c9d1d9}
.table tr:hover td{background:#1c2128}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700}
.b-c{background:rgba(248,81,73,.15);color:#f85149}.b-h{background:rgba(245,158,11,.15);color:#f59e0b}
.b-m{background:rgba(88,166,255,.15);color:#58a6ff}.b-l{background:rgba(63,185,80,.15);color:#3fb950}
.login{position:fixed;inset:0;background:rgba(0,0,0,.7);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#1a1f2e;border:1px solid #30363d;border-radius:6px;width:360px;overflow:hidden}
.lh{background:#21262d;border-bottom:1px solid #30363d;padding:14px;color:#c4a53e;font-size:13px;font-weight:700}
.lbody{padding:16px}
.fg{margin-bottom:12px}.fg label{display:block;font-size:10px;color:#8b949e;text-transform:uppercase;letter-spacing:.07em;margin-bottom:4px}
.fg input{width:100%;padding:8px 10px;background:#0d1117;border:1px solid #30363d;border-radius:4px;color:#c9d1d9;font-size:12px;outline:none}
.btn{width:100%;padding:9px;background:#c4a53e;color:#0d1117;border:none;border-radius:4px;font-size:13px;font-weight:800;cursor:pointer}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">🔒 Dependency-Track — Sign In</div>
<div class="lbody">
<div class="fg"><label>Username</label><input type="text" placeholder="admin or sec-analyst"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Sign In</button>
</div></div></div>
<div class="hdr"><h1>🔒 PUL Dependency-Track</h1><p>Software Composition Analysis | Supply Chain Security | pul-deptrack.prabalurja.in</p></div>
<div class="main">
<div class="kpis">
<div class="kpi crit"><div class="n">7</div><div class="l">Critical Vulns</div></div>
<div class="kpi high"><div class="n">23</div><div class="l">High Vulns</div></div>
<div class="kpi"><div class="n">14</div><div class="l">Projects Tracked</div></div>
<div class="kpi ok"><div class="n">1,842</div><div class="l">Components Total</div></div>
</div>
<div class="panel"><div class="ph">High-Risk Components</div>
<table class="table">
<tr><th>Component</th><th>Version</th><th>Project</th><th>CVE</th><th>Severity</th><th>CVSS</th></tr>
<tr><td>flask</td><td>2.0.1</td><td>pul-infra-config</td><td>CVE-2023-30861</td><td><span class="badge b-h">HIGH</span></td><td>8.1</td></tr>
<tr><td>pyyaml</td><td>5.3.1</td><td>pul-ansible-roles</td><td>CVE-2020-14343</td><td><span class="badge b-c">CRIT</span></td><td>9.8</td></tr>
<tr><td>cryptography</td><td>38.0.0</td><td>pul-nexus-portal</td><td>CVE-2023-49083</td><td><span class="badge b-h">HIGH</span></td><td>7.5</td></tr>
<tr><td>jinja2</td><td>2.11.3</td><td>pul-infra-config</td><td>CVE-2020-28493</td><td><span class="badge b-m">MEDIUM</span></td><td>5.3</td></tr>
</table></div></div>
</body></html>
HTML
cat > "${TRAP_DIR}/deptrack/server.py" << 'PYEOF'
#!/usr/bin/env python3
import http.server,logging,os
LOG="/var/log/pul-honeytrap/itops-m2-deptrack.log"
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
http.server.HTTPServer(("0.0.0.0",9000),H).serve_forever()
PYEOF
make_svc "itops-m2-deptrack" "${TRAP_DIR}/deptrack/server.py" 9000

# ─── D6: Harbor Container Registry — port 8888 ────────────────────────────────
mkdir -p "${TRAP_DIR}/harbor"
cat > "${TRAP_DIR}/harbor/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Harbor Registry</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',Arial,sans-serif;background:#f0f3f5;color:#1d2226;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#004d8c;border-bottom:3px solid #c4a53e;padding:0 20px;height:56px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#fff;font-size:16px;font-weight:700;display:flex;align-items:center;gap:10px}.hdr .sub{color:rgba(255,255,255,.4);font-size:11px}
.main{flex:1;padding:20px;max-width:1000px;margin:0 auto;width:100%}
.kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:20px}
.kpi{background:#fff;border:1px solid #dce3e8;border-radius:6px;padding:14px;box-shadow:0 1px 3px rgba(0,0,0,.05);border-top:3px solid #004d8c}
.kpi .n{font-size:24px;font-weight:800;color:#004d8c}.kpi .l{font-size:10.5px;color:#6c7b8a;text-transform:uppercase;letter-spacing:.05em;margin-top:3px}
.kpi.warn .n{color:#d97706}
.panel{background:#fff;border:1px solid #dce3e8;border-radius:6px;overflow:hidden;margin-bottom:14px;box-shadow:0 1px 3px rgba(0,0,0,.05)}
.ph{background:#004d8c;color:#fff;padding:10px 14px;font-size:12.5px;font-weight:600;border-bottom:2px solid #c4a53e}
.table{width:100%;border-collapse:collapse;font-size:12.5px}
.table th{text-align:left;padding:8px 14px;background:#f0f3f5;color:#6c7b8a;font-size:10.5px;text-transform:uppercase;letter-spacing:.05em;border-bottom:1px solid #dce3e8}
.table td{padding:9px 14px;border-bottom:1px solid #f0f3f5;color:#1d2226;font-family:'Courier New',monospace;font-size:11.5px}
.table tr:hover td{background:#f0f3f5}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700;font-family:sans-serif}
.b-ok{background:rgba(5,150,105,.12);color:#047857}.b-scan{background:rgba(217,119,6,.12);color:#b45309}
.b-vuln{background:rgba(220,38,38,.12);color:#991b1b}
.login{position:fixed;inset:0;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#fff;border-radius:6px;width:380px;overflow:hidden;box-shadow:0 8px 24px rgba(0,0,0,.15)}
.lh{background:#004d8c;border-bottom:2px solid #c4a53e;padding:16px 20px;color:#fff;font-size:14px;font-weight:700}
.lbody{padding:20px}
.fg{margin-bottom:14px}.fg label{display:block;font-size:11px;font-weight:700;color:#6c7b8a;margin-bottom:4px;text-transform:uppercase;letter-spacing:.06em}
.fg input{width:100%;padding:9px 12px;border:1px solid #dce3e8;border-radius:4px;font-size:13px}
.fg input:focus{outline:none;border-color:#004d8c}
.btn{width:100%;padding:10px;background:#004d8c;color:#fff;border:none;border-radius:4px;font-size:14px;font-weight:700;cursor:pointer}
.footer{background:#004d8c;padding:8px 20px;text-align:center;font-size:10px;color:rgba(255,255,255,.3)}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">⚓ Harbor Registry — Sign In</div>
<div class="lbody">
<div class="fg"><label>Username</label><input type="text" placeholder="admin or svc-cicd"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Harbor password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Log In</button>
</div></div></div>
<div class="hdr"><h1>⚓ PUL Harbor Container Registry</h1><div class="sub">registry.prabalurja.in | DevOps Division</div></div>
<div class="main">
<div class="kpis">
<div class="kpi"><div class="n">4</div><div class="l">Projects</div></div>
<div class="kpi"><div class="n">87</div><div class="l">Repositories</div></div>
<div class="kpi warn"><div class="n">12</div><div class="l">Vulnerabilities</div></div>
<div class="kpi"><div class="n">14.1 GB</div><div class="l">Total Size</div></div>
</div>
<div class="panel"><div class="ph">Recent Image Pushes</div>
<table class="table">
<tr><th>Repository</th><th>Tag</th><th>Pushed By</th><th>Size</th><th>Pushed At</th><th>Scan</th></tr>
<tr><td>pul-internal/nexus-portal</td><td>v1.4.2</td><td>svc-cicd</td><td>284 MB</td><td>Nov 15 09:14</td><td><span class="badge b-ok">PASS</span></td></tr>
<tr><td>pul-internal/monitoring-agent</td><td>latest</td><td>devops-bot</td><td>122 MB</td><td>Nov 14 23:44</td><td><span class="badge b-scan">SCANNING</span></td></tr>
<tr><td>pul-internal/ansible-runner</td><td>v2.1.0</td><td>svc-deploy</td><td>441 MB</td><td>Nov 14 18:22</td><td><span class="badge b-vuln">2 VULNS</span></td></tr>
<tr><td>pul-internal/vault-agent-sidecar</td><td>v0.3.1</td><td>arun.sharma</td><td>88 MB</td><td>Nov 13 11:08</td><td><span class="badge b-ok">PASS</span></td></tr>
</table></div></div>
<div class="footer">Harbor 2.9.1 | © 2024 Prabal Urja Limited | registry.prabalurja.in</div>
</body></html>
HTML
cat > "${TRAP_DIR}/harbor/server.py" << 'PYEOF'
#!/usr/bin/env python3
import http.server,logging,os
LOG="/var/log/pul-honeytrap/itops-m2-harbor.log"
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
http.server.HTTPServer(("0.0.0.0",8888),H).serve_forever()
PYEOF
make_svc "itops-m2-harbor" "${TRAP_DIR}/harbor/server.py" 8888

# ─── D7: Code Coverage Portal — port 8080 (alt port since Gitea is 3000) ──────
mkdir -p "${TRAP_DIR}/coverage"
cat > "${TRAP_DIR}/coverage/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Code Coverage</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Segoe UI',Arial,sans-serif;background:#f8f9fa;color:#212529;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#6f42c1;border-bottom:3px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#fff;font-size:15px;font-weight:700}.hdr p{color:rgba(255,255,255,.35);font-size:11px}
.main{flex:1;padding:20px;max-width:1000px;margin:0 auto;width:100%}
.repo-cards{display:grid;grid-template-columns:repeat(2,1fr);gap:14px;margin-bottom:14px}
.repo-card{background:#fff;border:1px solid #dee2e6;border-radius:6px;padding:16px;box-shadow:0 1px 3px rgba(0,0,0,.05)}
.repo-card .rname{font-size:14px;font-weight:700;color:#6f42c1;margin-bottom:12px;display:flex;align-items:center;justify-content:space-between}
.cov-bar-bg{background:#e9ecef;border-radius:20px;height:12px;position:relative;overflow:hidden;margin-bottom:6px}
.cov-bar{height:100%;border-radius:20px;position:absolute;left:0}
.cov-bar.high{background:#28a745}.cov-bar.med{background:#ffc107}.cov-bar.low{background:#dc3545}
.cov-num{font-size:11.5px;color:#495057;text-align:right;margin-bottom:10px}
.stats-row{display:flex;gap:12px;font-size:11.5px;color:#6c757d}
.stat-item{display:flex;flex-direction:column;align-items:center}
.stat-item .n{font-size:16px;font-weight:700;color:#343a40}.stat-item .l{font-size:10px;text-transform:uppercase;letter-spacing:.05em}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700}
.b-pass{background:rgba(40,167,69,.12);color:#155724}.b-fail{background:rgba(220,53,69,.12);color:#721c24}
.login{position:fixed;inset:0;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#fff;border-radius:6px;width:360px;overflow:hidden;box-shadow:0 8px 24px rgba(0,0,0,.15)}
.lh{background:#6f42c1;border-bottom:2px solid #c4a53e;padding:14px 18px;color:#fff;font-size:13px;font-weight:700}
.lbody{padding:18px}
.fg{margin-bottom:12px}.fg label{display:block;font-size:10.5px;font-weight:700;color:#6c757d;margin-bottom:4px;text-transform:uppercase;letter-spacing:.07em}
.fg input{width:100%;padding:8px 10px;border:1px solid #dee2e6;border-radius:4px;font-size:13px}
.btn{width:100%;padding:9px;background:#6f42c1;color:#fff;border:none;border-radius:4px;font-size:13px;font-weight:700;cursor:pointer}
.footer{background:#6f42c1;padding:8px 20px;text-align:center;font-size:10px;color:rgba(255,255,255,.3)}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">📊 Code Coverage — Sign In</div>
<div class="lbody">
<div class="fg"><label>Username</label><input type="text" placeholder="svc-cicd or dev-lead"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Sign In</button>
</div></div></div>
<div class="hdr"><h1>📊 PUL Code Coverage Portal</h1><p>Codecov-style | CI-CD Integration | pul-coverage.prabalurja.in</p></div>
<div class="main"><div class="repo-cards">
<div class="repo-card">
<div class="rname">pul-infra-config <span class="badge b-pass">82%</span></div>
<div class="cov-bar-bg"><div class="cov-bar high" style="width:82%"></div></div>
<div class="cov-num">Lines: 1,241 / 1,514 covered</div>
<div class="stats-row">
<div class="stat-item"><span class="n">94%</span><span class="l">Branches</span></div>
<div class="stat-item"><span class="n">79%</span><span class="l">Functions</span></div>
<div class="stat-item"><span class="n">82%</span><span class="l">Statements</span></div>
</div>
</div>
<div class="repo-card">
<div class="rname">pul-nexus-portal <span class="badge b-pass">74%</span></div>
<div class="cov-bar-bg"><div class="cov-bar med" style="width:74%"></div></div>
<div class="cov-num">Lines: 3,841 / 5,191 covered</div>
<div class="stats-row">
<div class="stat-item"><span class="n">68%</span><span class="l">Branches</span></div>
<div class="stat-item"><span class="n">81%</span><span class="l">Functions</span></div>
<div class="stat-item"><span class="n">74%</span><span class="l">Statements</span></div>
</div>
</div>
<div class="repo-card">
<div class="rname">pul-ansible-roles <span class="badge b-fail">41%</span></div>
<div class="cov-bar-bg"><div class="cov-bar low" style="width:41%"></div></div>
<div class="cov-num">Lines: 844 / 2,058 covered</div>
<div class="stats-row">
<div class="stat-item"><span class="n">38%</span><span class="l">Branches</span></div>
<div class="stat-item"><span class="n">44%</span><span class="l">Functions</span></div>
<div class="stat-item"><span class="n">41%</span><span class="l">Statements</span></div>
</div>
</div>
</div></div>
<div class="footer">Code Coverage Portal v2.1 | © 2024 Prabal Urja Limited | DevOps Division</div>
</body></html>
HTML
cat > "${TRAP_DIR}/coverage/server.py" << 'PYEOF'
#!/usr/bin/env python3
import http.server,logging,os
LOG="/var/log/pul-honeytrap/itops-m2-coverage.log"
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
http.server.HTTPServer(("0.0.0.0",8080),H).serve_forever()
PYEOF
make_svc "itops-m2-coverage" "${TRAP_DIR}/coverage/server.py" 8080

echo ""
echo "============================================================"
echo "  RNG-IT-02 | M2 itops-git — Honeytraps Active"
echo "  D1: Git daemon banner (socket)→ port 9418"
echo "  D2: Gerrit Code Review        → port 8929"
echo "  D3: Nexus Repository Manager  → port 7990"
echo "  D4: SonarQube Code Analysis   → port 3001"
echo "  D5: Dependency-Track SCA      → port 9000"
echo "  D6: Harbor Container Registry → port 8888"
echo "  D7: Code Coverage Portal      → port 8080"
echo "  Logs: ${LOG_DIR}/itops-m2-*.log"
echo "============================================================"
