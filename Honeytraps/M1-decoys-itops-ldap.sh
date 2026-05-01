#!/usr/bin/env bash
# =============================================================================
# M1 — itops-ldap | Honeytraps (5 decoys)
# Ports: 8080 (phpLDAPadmin), 8443 (LDAP Admin Console), 9389 (LDAP Sync API),
#        9636 (AD Connector UI), 9100 (LDAP Monitor)
# Each decoy has a proper themed web UI served via Python HTTP.
# Ubuntu 22.04 LTS
# =============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi

LOG_DIR="/var/log/pul-honeytrap"
TRAP_DIR="/opt/pul-honeytrap"
mkdir -p "${LOG_DIR}" "${TRAP_DIR}"

# ─────────────────────────────────────────────────────────────────────────────
# DECOY 1 — phpLDAPadmin Clone (port 8080)
# ─────────────────────────────────────────────────────────────────────────────
mkdir -p "${TRAP_DIR}/d1-phpldapadmin"
cat > "${TRAP_DIR}/d1-phpldapadmin/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<title>phpLDAPadmin — Prabal Urja Limited</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:Tahoma,Arial,sans-serif;background:#e8ecf0;color:#333;font-size:13px}
.header{background:#2c5282;color:#fff;padding:8px 16px;display:flex;align-items:center;gap:12px;border-bottom:3px solid #c4a53e}
.header h1{font-size:16px;font-weight:bold}.header .ver{font-size:10px;opacity:.6;margin-top:2px}
.layout{display:flex;height:calc(100vh - 44px)}
.sidebar{width:240px;background:#fff;border-right:1px solid #ddd;overflow-y:auto;flex-shrink:0}
.sidebar-hdr{background:#f0f4f8;border-bottom:1px solid #ddd;padding:8px 12px;font-weight:bold;font-size:11px;color:#555;text-transform:uppercase;letter-spacing:.05em}
.tree-item{padding:6px 12px 6px 24px;border-bottom:1px solid #f0f0f0;cursor:pointer;display:flex;align-items:center;gap:6px;font-size:12px;color:#2c5282}
.tree-item:hover{background:#f0f7ff}.tree-item.selected{background:#dbeafe}
.tree-item .icon{font-size:14px;flex-shrink:0}
.main{flex:1;padding:20px;overflow-y:auto}
.login-box{max-width:420px;margin:40px auto;background:#fff;border:1px solid #ddd;border-radius:4px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,.08)}
.login-box .lh{background:#2c5282;color:#fff;padding:14px 20px;font-size:14px;font-weight:bold;border-bottom:2px solid #c4a53e}
.login-box .lb{padding:20px}
.form-row{margin-bottom:14px}
.form-row label{display:block;font-size:11px;font-weight:bold;color:#555;margin-bottom:4px;text-transform:uppercase;letter-spacing:.05em}
.form-row input{width:100%;padding:8px 10px;border:1px solid #ccc;border-radius:3px;font-size:13px}
.form-row input:focus{outline:none;border-color:#2c5282;box-shadow:0 0 0 2px rgba(44,82,130,.15)}
.form-row select{width:100%;padding:8px 10px;border:1px solid #ccc;border-radius:3px;font-size:13px}
.btn-submit{background:#2c5282;color:#fff;border:none;padding:9px 20px;border-radius:3px;font-size:13px;font-weight:bold;cursor:pointer;width:100%}
.btn-submit:hover{background:#1a3a5c}
.notice{background:#fefce8;border:1px solid #f59e0b;border-radius:3px;padding:8px 12px;font-size:11px;color:#92400e;margin-bottom:14px}
.footer{text-align:center;font-size:10px;color:#999;margin-top:16px}
</style></head>
<body>
<div class="header">
  <div>
    <div class="h1" style="font-size:16px;font-weight:bold">phpLDAPadmin</div>
    <div class="ver">Prabal Urja Limited — IT Directory Management</div>
  </div>
</div>
<div class="layout">
  <div class="sidebar">
    <div class="sidebar-hdr">Servers</div>
    <div class="tree-item selected"><span class="icon">🖥</span> ldap.prabalurja.in</div>
    <div class="tree-item"><span class="icon">🖥</span> ldap-backup.prabalurja.in</div>
    <div class="sidebar-hdr" style="margin-top:8px">Quick Links</div>
    <div class="tree-item"><span class="icon">🔍</span> Search</div>
    <div class="tree-item"><span class="icon">➕</span> Create Entry</div>
    <div class="tree-item"><span class="icon">📥</span> Import</div>
    <div class="tree-item"><span class="icon">📤</span> Export</div>
  </div>
  <div class="main">
    <div class="login-box">
      <div class="lh">🔐 &nbsp;Authenticate to LDAP Server</div>
      <div class="lb">
        <div class="notice">⚠ Session expired. Please re-authenticate to continue directory management.</div>
        <div class="form-row">
          <label>Login DN</label>
          <input type="text" placeholder="cn=admin,dc=prabalurja,dc=in">
        </div>
        <div class="form-row">
          <label>Password</label>
          <input type="password" placeholder="Enter LDAP bind password">
        </div>
        <div class="form-row">
          <label>Authentication Type</label>
          <select><option>Simple</option><option>SASL</option></select>
        </div>
        <button class="btn-submit" onclick="alert('Invalid credentials. This session has been logged.')">Authenticate</button>
        <div class="footer">phpLDAPadmin 1.2.6.2 — PUL IT Infrastructure Division</div>
      </div>
    </div>
  </div>
</div>
</body></html>
HTML

cat > "${TRAP_DIR}/d1-phpldapadmin/server.py" << 'PYEOF'
#!/usr/bin/env python3
import http.server, logging, os, urllib.parse
LOG_FILE = "/var/log/pul-honeytrap/M1-decoy-phpldapadmin.log"
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
logging.basicConfig(filename=LOG_FILE, level=logging.WARNING,
    format="%(asctime)s %(message)s", datefmt="%Y-%m-%dT%H:%M:%S")
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        logging.warning(f"HONEYTRAP_HIT | src={self.client_address[0]} | {fmt % args}")
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type","text/html")
        self.end_headers()
        with open(os.path.join(os.path.dirname(__file__),"index.html"),"rb") as f:
            self.wfile.write(f.read())
    def do_POST(self):
        length = int(self.headers.get("Content-Length",0))
        body = self.rfile.read(length).decode("utf-8","replace")
        logging.warning(f"HONEYTRAP_POST | src={self.client_address[0]} | body={repr(body[:200])}")
        self.send_response(302)
        self.send_header("Location","/")
        self.end_headers()
http.server.HTTPServer(("0.0.0.0",8080),H).serve_forever()
PYEOF
chmod +x "${TRAP_DIR}/d1-phpldapadmin/server.py"

# ─────────────────────────────────────────────────────────────────────────────
# DECOY 2 — LDAP Admin Console (port 8443)
# ─────────────────────────────────────────────────────────────────────────────
mkdir -p "${TRAP_DIR}/d2-ldapadmin"
cat > "${TRAP_DIR}/d2-ldapadmin/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<title>PUL LDAP Admin Console</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',Arial,sans-serif;background:linear-gradient(135deg,#0d1b2a 0%,#1a3a5c 100%);min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;color:#fff}
.box{background:rgba(255,255,255,0.06);border:1px solid rgba(196,165,62,0.25);border-radius:10px;width:400px;overflow:hidden;box-shadow:0 20px 60px rgba(0,0,0,0.5)}
.bh{background:rgba(0,0,0,0.3);border-bottom:2px solid #c4a53e;padding:20px 24px;text-align:center}
.bh .logo{font-size:36px;margin-bottom:8px}.bh h2{color:#c4a53e;font-size:16px;font-weight:700;letter-spacing:.06em}
.bh p{color:rgba(255,255,255,0.4);font-size:11px;margin-top:3px}
.bb{padding:24px}
.fg{margin-bottom:16px}
.fg label{display:block;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.08em;color:rgba(255,255,255,0.45);margin-bottom:5px}
.fg input{width:100%;padding:10px 14px;background:rgba(255,255,255,0.07);border:1px solid rgba(255,255,255,0.15);border-radius:6px;color:#fff;font-size:13px;outline:none}
.fg input:focus{border-color:#c4a53e;box-shadow:0 0 0 3px rgba(196,165,62,0.15)}
.fg input::placeholder{color:rgba(255,255,255,0.25)}
.btn{width:100%;padding:11px;background:linear-gradient(135deg,#c4a53e,#d4bb5a);color:#0d1b2a;border:none;border-radius:6px;font-size:13px;font-weight:800;letter-spacing:.06em;text-transform:uppercase;cursor:pointer}
.btn:hover{opacity:.9}
.footer{text-align:center;font-size:10px;color:rgba(255,255,255,0.2);margin-top:16px;padding-bottom:20px}
.warn{background:rgba(185,28,28,0.2);border:1px solid rgba(185,28,28,0.4);border-radius:5px;padding:8px 12px;font-size:11px;color:#fca5a5;margin-bottom:14px}
</style></head>
<body>
<div class="box">
  <div class="bh"><div class="logo">🗂</div><h2>LDAP Admin Console</h2><p>Prabal Urja Limited — Directory Services</p></div>
  <div class="bb">
    <div class="warn">⚠ Restricted system — authorised administrators only. All access is audited.</div>
    <div class="fg"><label>Administrator DN</label><input type="text" placeholder="cn=admin,dc=prabalurja,dc=in"></div>
    <div class="fg"><label>Password</label><input type="password" placeholder="Enter admin password"></div>
    <div class="fg"><label>LDAP Server</label><input type="text" value="ldap://203.x.x.x:389" readonly style="opacity:.5"></div>
    <button class="btn" onclick="alert('Authentication failed. Incident logged.')">Connect to Directory</button>
    <div class="footer">PUL-LDAP-Admin v2.1 | IT Infrastructure Division | © 2024 Prabal Urja Limited</div>
  </div>
</div>
</body></html>
HTML

cat > "${TRAP_DIR}/d2-ldapadmin/server.py" << 'PYEOF'
#!/usr/bin/env python3
import http.server, logging, os
LOG_FILE = "/var/log/pul-honeytrap/M1-decoy-ldapadmin.log"
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
logging.basicConfig(filename=LOG_FILE, level=logging.WARNING,
    format="%(asctime)s %(message)s", datefmt="%Y-%m-%dT%H:%M:%S")
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        logging.warning(f"HONEYTRAP_HIT | src={self.client_address[0]} | {fmt % args}")
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Type","text/html"); self.end_headers()
        with open(os.path.join(os.path.dirname(__file__),"index.html"),"rb") as f: self.wfile.write(f.read())
    def do_POST(self):
        length=int(self.headers.get("Content-Length",0)); body=self.rfile.read(length).decode("utf-8","replace")
        logging.warning(f"HONEYTRAP_POST | src={self.client_address[0]} | body={repr(body[:200])}")
        self.send_response(302); self.send_header("Location","/"); self.end_headers()
http.server.HTTPServer(("0.0.0.0",8443),H).serve_forever()
PYEOF
chmod +x "${TRAP_DIR}/d2-ldapadmin/server.py"

# ─────────────────────────────────────────────────────────────────────────────
# DECOY 3 — LDAP Sync API (port 9389) — JSON API with swagger-like UI
# ─────────────────────────────────────────────────────────────────────────────
mkdir -p "${TRAP_DIR}/d3-ldapsync"
cat > "${TRAP_DIR}/d3-ldapsync/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<title>PUL Directory Sync API</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',monospace,Arial;background:#1a1a2e;color:#e0e0e0;font-size:13px}
.hdr{background:#16213e;border-bottom:2px solid #0f3460;padding:14px 20px;display:flex;align-items:center;gap:12px}
.hdr h1{color:#e94560;font-size:16px}.hdr .ver{background:#0f3460;color:#64ffda;padding:2px 8px;border-radius:3px;font-size:10px;font-weight:bold}
.hdr .base{color:#888;font-size:11px;margin-left:auto}
.content{max-width:900px;margin:20px auto;padding:0 20px}
.info-box{background:#16213e;border:1px solid #0f3460;border-radius:6px;padding:16px;margin-bottom:16px}
.info-box h3{color:#64ffda;font-size:12px;text-transform:uppercase;letter-spacing:.08em;margin-bottom:8px}
.tag{display:inline-block;padding:2px 8px;border-radius:12px;font-size:10px;font-weight:bold;margin-right:4px}
.tag-get{background:rgba(100,255,218,0.15);color:#64ffda}.tag-post{background:rgba(233,69,96,0.15);color:#e94560}
.tag-del{background:rgba(255,165,0,0.15);color:orange}
.endpoint{background:#0d1117;border:1px solid #21262d;border-radius:6px;margin-bottom:8px;overflow:hidden}
.ep-hdr{padding:10px 14px;display:flex;align-items:center;gap:10px;cursor:pointer;border-bottom:1px solid #21262d}
.ep-hdr:hover{background:#161b22}
.ep-path{color:#e0e0e0;font-family:monospace;font-size:12px}
.ep-desc{color:#666;font-size:11px;margin-left:auto}
.ep-body{padding:14px;display:none;border-top:1px solid #21262d}
.ep-body.open{display:block}
.field{margin-bottom:10px}
.field label{display:block;font-size:10px;color:#888;margin-bottom:4px;text-transform:uppercase}
.field input{background:#161b22;border:1px solid #30363d;border-radius:4px;color:#e0e0e0;padding:7px 10px;width:100%;font-size:12px;font-family:monospace}
.try-btn{background:#238636;color:#fff;border:none;padding:7px 16px;border-radius:4px;font-size:12px;cursor:pointer}
.try-btn:hover{background:#2ea043}
.lock{color:#f59e0b;font-size:12px}
</style></head>
<body>
<div class="hdr">
  <div>
    <h1>PUL Directory Sync API</h1>
    <div style="display:flex;align-items:center;gap:8px;margin-top:4px">
      <span class="ver">v1.4.2</span>
      <span style="color:#888;font-size:11px">OAS 3.0 | ldap-sync-svc</span>
    </div>
  </div>
  <div class="base">Base URL: http://203.x.x.x:9389/api/v1</div>
</div>
<div class="content">
  <div class="info-box">
    <h3>Authentication</h3>
    <p style="color:#888;font-size:12px">All endpoints require <code style="color:#64ffda">X-API-Key</code> header. Keys are provisioned via the LDAP Admin Console. <span class="lock">🔒 Bearer Token (JWT)</span> also accepted on v1.4+.</p>
  </div>
  <div class="endpoint">
    <div class="ep-hdr" onclick="this.nextElementSibling.classList.toggle('open')">
      <span class="tag tag-get">GET</span>
      <span class="ep-path">/api/v1/sync/status</span>
      <span class="ep-desc">Get sync daemon health and last-run statistics</span>
    </div>
    <div class="ep-body">
      <div class="field"><label>X-API-Key</label><input type="text" placeholder="pul-sync-key-xxxxxxxx"></div>
      <button class="try-btn">Try it out</button>
    </div>
  </div>
  <div class="endpoint">
    <div class="ep-hdr" onclick="this.nextElementSibling.classList.toggle('open')">
      <span class="tag tag-post">POST</span>
      <span class="ep-path">/api/v1/sync/trigger</span>
      <span class="ep-desc">Manually trigger directory synchronisation</span>
    </div>
    <div class="ep-body">
      <div class="field"><label>X-API-Key</label><input type="text" placeholder="pul-sync-key-xxxxxxxx"></div>
      <div class="field"><label>Request Body (JSON)</label><input type="text" value='{"source":"ldap://203.x.x.x","target":"ldap://ad.corp.prabalurja.in","base_dn":"dc=prabalurja,dc=in"}'></div>
      <button class="try-btn">Try it out</button>
    </div>
  </div>
  <div class="endpoint">
    <div class="ep-hdr" onclick="this.nextElementSibling.classList.toggle('open')">
      <span class="tag tag-get">GET</span>
      <span class="ep-path">/api/v1/accounts</span>
      <span class="ep-desc">List synchronised accounts and sync status</span>
    </div>
    <div class="ep-body">
      <div class="field"><label>X-API-Key</label><input type="text" placeholder="pul-sync-key-xxxxxxxx"></div>
      <div class="field"><label>Filter (optional)</label><input type="text" placeholder="ou=service"></div>
      <button class="try-btn">Try it out</button>
    </div>
  </div>
  <div class="endpoint">
    <div class="ep-hdr" onclick="this.nextElementSibling.classList.toggle('open')">
      <span class="tag tag-del">DELETE</span>
      <span class="ep-path">/api/v1/accounts/{dn}</span>
      <span class="ep-desc">Remove account from sync scope <span class="lock">🔒 Admin only</span></span>
    </div>
    <div class="ep-body">
      <div class="field"><label>X-API-Key (Admin)</label><input type="text" placeholder="pul-sync-admin-key-xxxxxxxx"></div>
      <div class="field"><label>DN</label><input type="text" placeholder="cn=svc-account,ou=service,dc=prabalurja,dc=in"></div>
      <button class="try-btn">Try it out</button>
    </div>
  </div>
</div>
</body></html>
HTML

cat > "${TRAP_DIR}/d3-ldapsync/server.py" << 'PYEOF'
#!/usr/bin/env python3
import http.server, logging, os, json
LOG_FILE = "/var/log/pul-honeytrap/M1-decoy-ldapsync.log"
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
logging.basicConfig(filename=LOG_FILE, level=logging.WARNING,
    format="%(asctime)s %(message)s", datefmt="%Y-%m-%dT%H:%M:%S")
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        logging.warning(f"HONEYTRAP_HIT | src={self.client_address[0]} | path={self.path} | {fmt % args}")
    def do_GET(self):
        if self.path.startswith("/api"):
            body = json.dumps({"error":"Unauthorized","code":401,"message":"Valid X-API-Key required"}).encode()
            self.send_response(401); self.send_header("Content-Type","application/json"); self.end_headers(); self.wfile.write(body)
        else:
            self.send_response(200); self.send_header("Content-Type","text/html"); self.end_headers()
            with open(os.path.join(os.path.dirname(__file__),"index.html"),"rb") as f: self.wfile.write(f.read())
    def do_POST(self):
        length=int(self.headers.get("Content-Length",0)); body=self.rfile.read(length).decode("utf-8","replace")
        logging.warning(f"HONEYTRAP_POST | src={self.client_address[0]} | body={repr(body[:300])}")
        resp=json.dumps({"error":"Unauthorized","code":401}).encode()
        self.send_response(401); self.send_header("Content-Type","application/json"); self.end_headers(); self.wfile.write(resp)
http.server.HTTPServer(("0.0.0.0",9389),H).serve_forever()
PYEOF
chmod +x "${TRAP_DIR}/d3-ldapsync/server.py"

# ─────────────────────────────────────────────────────────────────────────────
# DECOY 4 — AD Connector UI (port 9636)
# ─────────────────────────────────────────────────────────────────────────────
mkdir -p "${TRAP_DIR}/d4-adconnector"
cat > "${TRAP_DIR}/d4-adconnector/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<title>PUL AD Connector</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',Arial,sans-serif;background:#f3f4f6;color:#111827;font-size:13px}
.topbar{background:#1d4ed8;color:#fff;padding:10px 20px;display:flex;align-items:center;justify-content:space-between}
.topbar h1{font-size:15px;font-weight:700}.topbar .meta{font-size:11px;opacity:.7}
.nav{background:#1e3a8a;display:flex;gap:0;border-bottom:2px solid #c4a53e}
.nav a{color:rgba(255,255,255,0.65);padding:10px 18px;font-size:12px;font-weight:600;text-decoration:none;border-bottom:3px solid transparent;display:inline-block}
.nav a:hover,.nav a.active{color:#fff;border-color:#c4a53e;background:rgba(255,255,255,0.05)}
.content{padding:24px;max-width:900px;margin:0 auto}
.panel{background:#fff;border:1px solid #e5e7eb;border-radius:8px;overflow:hidden;margin-bottom:20px;box-shadow:0 1px 4px rgba(0,0,0,.06)}
.ph{background:#1e3a8a;color:#fff;padding:12px 16px;font-size:13px;font-weight:600;border-bottom:2px solid #c4a53e}
.pb{padding:16px}
.status-row{display:flex;align-items:center;gap:10px;padding:8px 0;border-bottom:1px solid #f0f0f0}
.status-row:last-child{border-bottom:none}
.s-key{color:#6b7280;width:200px;flex-shrink:0;font-size:12px}
.s-val{color:#111827;font-size:12px;font-weight:500}
.dot-g{width:8px;height:8px;border-radius:50%;background:#10b981;display:inline-block;margin-right:5px}
.dot-r{width:8px;height:8px;border-radius:50%;background:#ef4444;display:inline-block;margin-right:5px}
.dot-y{width:8px;height:8px;border-radius:50%;background:#f59e0b;display:inline-block;margin-right:5px}
.fg{margin-bottom:12px}
.fg label{display:block;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#6b7280;margin-bottom:4px}
.fg input{width:100%;padding:8px 12px;border:1px solid #d1d5db;border-radius:5px;font-size:13px}
.fg input:focus{outline:none;border-color:#1d4ed8;box-shadow:0 0 0 2px rgba(29,78,216,.1)}
.btn{background:#1d4ed8;color:#fff;border:none;padding:9px 20px;border-radius:5px;font-size:13px;font-weight:600;cursor:pointer}
.btn:hover{background:#1e40af}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:16px}
</style></head>
<body>
<div class="topbar">
  <h1>🔗 &nbsp;PUL AD Connector — Directory Bridge v3.1</h1>
  <div class="meta">Last sync: 4 minutes ago &nbsp;|&nbsp; Managed by IT Operations</div>
</div>
<div class="nav">
  <a href="#" class="active">Dashboard</a>
  <a href="#">Sync Config</a>
  <a href="#">Object Mapping</a>
  <a href="#">Audit Log</a>
  <a href="#">Settings</a>
</div>
<div class="content">
  <div class="grid2">
    <div class="panel">
      <div class="ph">Connection Status</div>
      <div class="pb">
        <div class="status-row"><span class="s-key">Source (OpenLDAP)</span><span class="s-val"><span class="dot-g"></span>Connected — ldap://203.x.x.x:389</span></div>
        <div class="status-row"><span class="s-key">Target (AD Forest)</span><span class="s-val"><span class="dot-y"></span>Authenticating — ad.corp.prabalurja.in</span></div>
        <div class="status-row"><span class="s-key">Sync Mode</span><span class="s-val">Delta Sync (every 15 min)</span></div>
        <div class="status-row"><span class="s-key">Objects Synced</span><span class="s-val">247 users, 12 groups, 8 service accounts</span></div>
        <div class="status-row"><span class="s-key">Last Error</span><span class="s-val"><span class="dot-r"></span>AD bind failed — credential rotation pending</span></div>
      </div>
    </div>
    <div class="panel">
      <div class="ph">AD Bind Credentials</div>
      <div class="pb">
        <div class="fg"><label>AD Service Account DN</label><input type="text" value="CN=AADSync,CN=Users,DC=corp,DC=prabalurja,DC=in"></div>
        <div class="fg"><label>Password</label><input type="password" placeholder="Enter updated AD sync password"></div>
        <div class="fg"><label>Domain Controller</label><input type="text" value="ad.corp.prabalurja.in:389"></div>
        <button class="btn" onclick="alert('Credential update failed. Contact IT Operations.')">Update & Test Connection</button>
      </div>
    </div>
  </div>
</div>
</body></html>
HTML

cat > "${TRAP_DIR}/d4-adconnector/server.py" << 'PYEOF'
#!/usr/bin/env python3
import http.server, logging, os
LOG_FILE = "/var/log/pul-honeytrap/M1-decoy-adconnector.log"
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
logging.basicConfig(filename=LOG_FILE, level=logging.WARNING,
    format="%(asctime)s %(message)s", datefmt="%Y-%m-%dT%H:%M:%S")
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        logging.warning(f"HONEYTRAP_HIT | src={self.client_address[0]} | {fmt % args}")
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Type","text/html"); self.end_headers()
        with open(os.path.join(os.path.dirname(__file__),"index.html"),"rb") as f: self.wfile.write(f.read())
    def do_POST(self):
        length=int(self.headers.get("Content-Length",0)); body=self.rfile.read(length).decode("utf-8","replace")
        logging.warning(f"HONEYTRAP_POST | src={self.client_address[0]} | body={repr(body[:200])}")
        self.send_response(302); self.send_header("Location","/"); self.end_headers()
http.server.HTTPServer(("0.0.0.0",9636),H).serve_forever()
PYEOF
chmod +x "${TRAP_DIR}/d4-adconnector/server.py"

# ─────────────────────────────────────────────────────────────────────────────
# DECOY 5 — LDAP Monitor Dashboard (port 9100)
# ─────────────────────────────────────────────────────────────────────────────
mkdir -p "${TRAP_DIR}/d5-ldapmonitor"
cat > "${TRAP_DIR}/d5-ldapmonitor/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<title>LDAP Monitor — PUL</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Courier New',monospace;background:#0d1117;color:#c9d1d9;font-size:12px;min-height:100vh}
.hdr{background:#161b22;border-bottom:1px solid #30363d;padding:12px 20px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#58a6ff;font-size:14px}.hdr .ts{color:#8b949e;font-size:11px}
.metrics{padding:20px;display:grid;grid-template-columns:repeat(4,1fr);gap:12px}
.metric-card{background:#161b22;border:1px solid #30363d;border-radius:6px;padding:14px}
.metric-card .label{color:#8b949e;font-size:10px;text-transform:uppercase;letter-spacing:.06em;margin-bottom:6px}
.metric-card .value{font-size:24px;font-weight:bold;color:#58a6ff}
.metric-card .sub{color:#8b949e;font-size:10px;margin-top:3px}
.metric-card.warn .value{color:#f59e0b}
.metric-card.err .value{color:#f85149}
.logs{margin:0 20px 20px;background:#161b22;border:1px solid #30363d;border-radius:6px;overflow:hidden}
.logs-hdr{background:#21262d;padding:10px 14px;color:#8b949e;font-size:11px;border-bottom:1px solid #30363d}
.log-entry{padding:4px 14px;border-bottom:1px solid #21262d;font-size:11px;display:flex;gap:12px}
.log-entry:hover{background:#1c2128}
.ts{color:#8b949e;flex-shrink:0;width:160px}
.level-info{color:#58a6ff}.level-warn{color:#f59e0b}.level-err{color:#f85149}
.conn{color:#3fb950}
.login-overlay{position:fixed;inset:0;background:rgba(0,0,0,.7);display:flex;align-items:center;justify-content:center;z-index:99}
.login-box{background:#161b22;border:1px solid #30363d;border-radius:8px;width:340px;overflow:hidden}
.login-box .lh{background:#21262d;border-bottom:1px solid #30363d;padding:14px;color:#c9d1d9;font-size:13px}
.login-box .lb{padding:16px}
.login-box input{width:100%;background:#0d1117;border:1px solid #30363d;border-radius:4px;color:#c9d1d9;padding:8px 10px;font-size:12px;font-family:monospace;margin-bottom:10px}
.login-box button{width:100%;background:#238636;color:#fff;border:none;padding:8px;border-radius:4px;font-size:12px;cursor:pointer}
</style></head>
<body>
<div class="login-overlay" id="overlay">
  <div class="login-box">
    <div class="lh">🔐 LDAP Monitor — Authentication Required</div>
    <div class="lb">
      <input type="text" placeholder="Username (e.g. admin)">
      <input type="password" placeholder="Password">
      <button onclick="document.getElementById('overlay').style.display='none'">Login</button>
    </div>
  </div>
</div>
<div class="hdr">
  <h1>⚡ LDAP Monitor Dashboard — prabalurja.in</h1>
  <div class="ts" id="ts">Loading...</div>
</div>
<div class="metrics">
  <div class="metric-card"><div class="label">Total Connections</div><div class="value">1,847</div><div class="sub">+12 last hour</div></div>
  <div class="metric-card warn"><div class="label">Failed Binds</div><div class="value">23</div><div class="sub">Last 24 hours</div></div>
  <div class="metric-card"><div class="label">Active Sessions</div><div class="value">14</div><div class="sub">Right now</div></div>
  <div class="metric-card err"><div class="label">Replication Lag</div><div class="value">4.2s</div><div class="sub">Above threshold (2s)</div></div>
</div>
<div class="logs">
  <div class="logs-hdr">Live Access Log — /var/log/slapd/access.log</div>
  <div class="log-entry"><span class="ts">2024-11-15 10:14:23</span><span class="level-info">INFO</span>&nbsp;&nbsp;<span class="conn">BIND</span>&nbsp;cn=svc-monitor,ou=service,dc=prabalurja,dc=in SUCCESS</div>
  <div class="log-entry"><span class="ts">2024-11-15 10:14:21</span><span class="level-info">INFO</span>&nbsp;&nbsp;<span class="conn">SRCH</span>&nbsp;base="ou=users" scope=1 filter="(mail=*)" entries=47</div>
  <div class="log-entry"><span class="ts">2024-11-15 10:13:58</span><span class="level-warn">WARN</span>&nbsp;&nbsp;BIND FAIL: cn=svc-backup,ou=service - invalid credentials from 203.0.2.X</div>
  <div class="log-entry"><span class="ts">2024-11-15 10:13:44</span><span class="level-info">INFO</span>&nbsp;&nbsp;<span class="conn">BIND</span>&nbsp;anonymous SUCCESS (anon bind enabled)</div>
  <div class="log-entry"><span class="ts">2024-11-15 10:13:12</span><span class="level-err">ERROR</span>&nbsp;Replication: provider ldap://203.x.x.x-replica unreachable</div>
  <div class="log-entry"><span class="ts">2024-11-15 10:12:55</span><span class="level-info">INFO</span>&nbsp;&nbsp;<span class="conn">SRCH</span>&nbsp;base="ou=service" scope=2 filter="(objectClass=*)" entries=8</div>
</div>
<script>
function tick(){document.getElementById('ts').textContent=new Date().toLocaleString('en-IN',{timeZone:'Asia/Kolkata'})+" IST"}
tick();setInterval(tick,1000);
</script>
</body></html>
HTML

cat > "${TRAP_DIR}/d5-ldapmonitor/server.py" << 'PYEOF'
#!/usr/bin/env python3
import http.server, logging, os
LOG_FILE = "/var/log/pul-honeytrap/M1-decoy-ldapmonitor.log"
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
logging.basicConfig(filename=LOG_FILE, level=logging.WARNING,
    format="%(asctime)s %(message)s", datefmt="%Y-%m-%dT%H:%M:%S")
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        logging.warning(f"HONEYTRAP_HIT | src={self.client_address[0]} | {fmt % args}")
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Type","text/html"); self.end_headers()
        with open(os.path.join(os.path.dirname(__file__),"index.html"),"rb") as f: self.wfile.write(f.read())
    def do_POST(self):
        length=int(self.headers.get("Content-Length",0)); body=self.rfile.read(length).decode("utf-8","replace")
        logging.warning(f"HONEYTRAP_POST | src={self.client_address[0]} | body={repr(body[:200])}")
        self.send_response(302); self.send_header("Location","/"); self.end_headers()
http.server.HTTPServer(("0.0.0.0",9100),H).serve_forever()
PYEOF
chmod +x "${TRAP_DIR}/d5-ldapmonitor/server.py"

# ─────────────────────────────────────────────────────────────────────────────
# SYSTEMD SERVICES
# ─────────────────────────────────────────────────────────────────────────────
for i in 1 2 3 4 5; do
    case $i in
        1) NAME="pul-decoy-m1-phpldapadmin"; SCRIPT="${TRAP_DIR}/d1-phpldapadmin/server.py"; PORT=8080;;
        2) NAME="pul-decoy-m1-ldapadmin";    SCRIPT="${TRAP_DIR}/d2-ldapadmin/server.py";    PORT=8443;;
        3) NAME="pul-decoy-m1-ldapsync";     SCRIPT="${TRAP_DIR}/d3-ldapsync/server.py";     PORT=9389;;
        4) NAME="pul-decoy-m1-adconnector";  SCRIPT="${TRAP_DIR}/d4-adconnector/server.py";  PORT=9636;;
        5) NAME="pul-decoy-m1-ldapmonitor";  SCRIPT="${TRAP_DIR}/d5-ldapmonitor/server.py";  PORT=9100;;
    esac
    cat > /etc/systemd/system/${NAME}.service << EOF
[Unit]
Description=PUL Honeytrap M1 Decoy — port ${PORT}
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 ${SCRIPT}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "${NAME}" --quiet
    systemctl restart "${NAME}"
    echo "[+] Decoy ${i} active on port ${PORT}"
done

echo ""
echo "============================================================"
echo "  M1 Honeytraps Active"
echo "  D1: phpLDAPadmin clone     → port 8080"
echo "  D2: LDAP Admin Console     → port 8443"
echo "  D3: LDAP Sync API (Swagger)→ port 9389"
echo "  D4: AD Connector UI        → port 9636"
echo "  D5: LDAP Monitor Dashboard → port 9100"
echo "  Logs: ${LOG_DIR}/M1-decoy-*.log"
echo "============================================================"
