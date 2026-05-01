#!/usr/bin/env bash
# =============================================================================
# M2–M5 Honeytraps | RNG-IT-02 | OPERATION GRIDFALL
# 5 decoys per machine × 4 machines = 20 decoy services total
# Each has a themed web UI served by a minimal Python HTTP server
# =============================================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi

TRAP_DIR="/opt/pul-honeytrap"
LOG_DIR="/var/log/pul-honeytrap"
mkdir -p "${LOG_DIR}"

# ─────────────────────────────────────────────────────────────────────────────
# Helper: create a minimal Python server for each decoy
# Usage: make_server DIR PORT LOGNAME
# ─────────────────────────────────────────────────────────────────────────────
make_server() {
  local dir=$1 port=$2 logname=$3
  cat > "${dir}/server.py" << PYEOF
#!/usr/bin/env python3
import http.server, logging, os, json
LOG_FILE = "/var/log/pul-honeytrap/${logname}.log"
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
logging.basicConfig(filename=LOG_FILE, level=logging.WARNING,
    format="%(asctime)s %(message)s", datefmt="%Y-%m-%dT%H:%M:%S")
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        logging.warning(f"HIT|src={self.client_address[0]}|path={self.path}|{fmt % args}")
    def do_GET(self):
        idx = os.path.join(os.path.dirname(__file__), "index.html")
        if os.path.exists(idx):
            self.send_response(200); self.send_header("Content-Type","text/html"); self.end_headers()
            with open(idx,"rb") as f: self.wfile.write(f.read())
        else:
            self.send_response(404); self.end_headers()
    def do_POST(self):
        length = int(self.headers.get("Content-Length",0))
        body = self.rfile.read(length).decode("utf-8","replace")
        logging.warning(f"POST|src={self.client_address[0]}|body={repr(body[:300])}")
        self.send_response(302); self.send_header("Location","/"); self.end_headers()
http.server.HTTPServer(("0.0.0.0",${port}),H).serve_forever()
PYEOF
  chmod +x "${dir}/server.py"
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper: create a systemd service
# ─────────────────────────────────────────────────────────────────────────────
make_service() {
  local name=$1 script=$2 port=$3
  cat > "/etc/systemd/system/${name}.service" << EOF
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
  systemctl enable "${name}" --quiet
  systemctl restart "${name}"
}

# =============================================================================
# M2 — itops-git DECOYS
# Ports: 8929 (GitLab), 7990 (Bitbucket), 3001 (Gogs), 9000 (Webhook), 8888 (CI API)
# =============================================================================
echo "[*] Setting up M2 honeytraps..."

# D1: GitLab CE clone (8929)
mkdir -p "${TRAP_DIR}/m2-d1-gitlab"
cat > "${TRAP_DIR}/m2-d1-gitlab/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL GitLab CE</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#fafafa;color:#303030}
.hdr{background:#fc6d26;padding:0 20px;height:52px;display:flex;align-items:center;gap:12px}
.hdr .logo{color:#fff;font-size:18px;font-weight:700;letter-spacing:-.02em}
.hdr .sub{color:rgba(255,255,255,.7);font-size:12px;border-left:1px solid rgba(255,255,255,.3);padding-left:12px}
.main{max-width:480px;margin:60px auto;padding:0 20px}
.card{background:#fff;border:1px solid #ddd;border-radius:8px;padding:28px;box-shadow:0 2px 8px rgba(0,0,0,.06)}
.card h2{font-size:18px;color:#303030;margin-bottom:20px;text-align:center}
.fg{margin-bottom:14px}.fg label{display:block;font-size:12px;font-weight:600;color:#6b7280;margin-bottom:4px}
.fg input{width:100%;padding:9px 12px;border:1px solid #ddd;border-radius:5px;font-size:14px;color:#303030}
.fg input:focus{outline:none;border-color:#fc6d26;box-shadow:0 0 0 3px rgba(252,109,38,.12)}
.btn{width:100%;padding:10px;background:#fc6d26;color:#fff;border:none;border-radius:5px;font-size:14px;font-weight:600;cursor:pointer}
.notice{text-align:center;margin-top:16px;font-size:12px;color:#9ca3af}
.tabs{display:flex;border-bottom:2px solid #e5e7eb;margin-bottom:20px}
.tab{padding:8px 16px;font-size:13px;font-weight:600;cursor:pointer;border-bottom:2px solid transparent;margin-bottom:-2px}
.tab.active{color:#fc6d26;border-color:#fc6d26}
</style></head>
<body>
<div class="hdr"><div class="logo">GitLab</div><div class="sub">Prabal Urja Limited — Internal DevOps</div></div>
<div class="main">
  <div class="card">
    <div class="tabs"><div class="tab active">Sign in</div><div class="tab">Register</div></div>
    <div class="fg"><label>Username or email</label><input type="text" placeholder="e.g. svc-cicd or user@prabalurja.in"></div>
    <div class="fg"><label>Password</label><input type="password" placeholder="GitLab password"></div>
    <button class="btn" onclick="alert('Authentication failed. Access attempt logged.')">Sign in</button>
    <div class="notice">This is a restricted system. Unauthorised access is prohibited.</div>
  </div>
</div>
</body></html>
HTML
make_server "${TRAP_DIR}/m2-d1-gitlab" 8929 "M2-decoy-gitlab"
make_service "pul-decoy-m2-gitlab" "${TRAP_DIR}/m2-d1-gitlab/server.py" 8929

# D2: Bitbucket clone (7990)
mkdir -p "${TRAP_DIR}/m2-d2-bitbucket"
cat > "${TRAP_DIR}/m2-d2-bitbucket/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Bitbucket Server</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',sans-serif;background:#0052CC;min-height:100vh;display:flex;align-items:center;justify-content:center}
.card{background:#fff;border-radius:8px;width:420px;overflow:hidden;box-shadow:0 8px 30px rgba(0,0,0,.3)}
.ch{background:#0052CC;padding:24px;text-align:center;color:#fff}
.ch h1{font-size:22px;font-weight:700}.ch p{font-size:12px;opacity:.7;margin-top:4px}
.cb{padding:24px}
.fg{margin-bottom:14px}.fg label{display:block;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#6b7280;margin-bottom:5px}
.fg input{width:100%;padding:9px 12px;border:1px solid #ddd;border-radius:4px;font-size:13px}
.fg input:focus{outline:none;border-color:#0052CC}
.btn{width:100%;padding:10px;background:#0052CC;color:#fff;border:none;border-radius:4px;font-size:14px;font-weight:700;cursor:pointer}
</style></head>
<body><div class="card">
<div class="ch"><h1>Bitbucket Server</h1><p>Prabal Urja Limited — Source Control</p></div>
<div class="cb">
  <div class="fg"><label>Username</label><input type="text" placeholder="username or email"></div>
  <div class="fg"><label>Password</label><input type="password" placeholder="password"></div>
  <button class="btn" onclick="alert('Login failed. This attempt has been logged.')">Log in</button>
</div></div>
</body></html>
HTML
make_server "${TRAP_DIR}/m2-d2-bitbucket" 7990 "M2-decoy-bitbucket"
make_service "pul-decoy-m2-bitbucket" "${TRAP_DIR}/m2-d2-bitbucket/server.py" 7990

# D3: Gogs (3001)
mkdir -p "${TRAP_DIR}/m2-d3-gogs"
cat > "${TRAP_DIR}/m2-d3-gogs/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Gogs</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Segoe UI',sans-serif;background:#f5f5f5}
.hdr{background:#4b4b4b;padding:0 20px;height:50px;display:flex;align-items:center;color:#fff;gap:10px}
.hdr .logo{font-size:16px;font-weight:700}.hdr .sub{color:rgba(255,255,255,.5);font-size:12px}
.main{max-width:420px;margin:50px auto;background:#fff;border:1px solid #ddd;border-radius:6px;padding:24px}
.main h2{font-size:16px;color:#333;margin-bottom:18px;border-bottom:1px solid #eee;padding-bottom:12px}
.fg{margin-bottom:13px}.fg label{display:block;font-size:12px;color:#666;margin-bottom:4px}
.fg input{width:100%;padding:8px 10px;border:1px solid #ccc;border-radius:4px;font-size:13px}
.btn{background:#4b4b4b;color:#fff;border:none;padding:9px 20px;border-radius:4px;font-size:13px;cursor:pointer;width:100%}
</style></head>
<body>
<div class="hdr"><div class="logo">⎇ Gogs</div><div class="sub">Prabal Urja — IT Infrastructure Repos</div></div>
<div class="main">
  <h2>Sign In</h2>
  <div class="fg"><label>Username or Email</label><input type="text" placeholder="Enter username"></div>
  <div class="fg"><label>Password</label><input type="password" placeholder="Enter password"></div>
  <button class="btn" onclick="alert('Access denied. Attempt recorded.')">Sign In</button>
</div>
</body></html>
HTML
make_server "${TRAP_DIR}/m2-d3-gogs" 3001 "M2-decoy-gogs"
make_service "pul-decoy-m2-gogs" "${TRAP_DIR}/m2-d3-gogs/server.py" 3001

# D4: Webhook receiver (9000) — JSON API decoy
mkdir -p "${TRAP_DIR}/m2-d4-webhook"
cat > "${TRAP_DIR}/m2-d4-webhook/index.html" << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL Webhook Receiver</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:monospace;background:#0d1117;color:#c9d1d9;padding:20px}
h1{color:#58a6ff;margin-bottom:10px;font-size:16px}.ep{background:#161b22;border:1px solid #21262d;border-radius:6px;padding:14px;margin-bottom:10px}
.method{color:#3fb950;font-weight:700;margin-right:8px}.path{color:#c4a53e}
.desc{color:#8b949e;font-size:12px;margin-top:4px}
</style></head>
<body>
<h1>PUL CI/CD Webhook Receiver — v1.3</h1>
<p style="color:#8b949e;font-size:12px;margin-bottom:16px">Endpoint for Git push events, pipeline triggers, and deployment notifications.</p>
<div class="ep"><span class="method">POST</span><span class="path">/webhook/push</span><div class="desc">Git push event receiver — triggers CI pipeline</div></div>
<div class="ep"><span class="method">POST</span><span class="path">/webhook/merge</span><div class="desc">Pull/merge request event handler</div></div>
<div class="ep"><span class="method">POST</span><span class="path">/webhook/deploy</span><div class="desc">Deployment trigger endpoint — requires X-PUL-Token header</div></div>
<div class="ep"><span class="method">GET</span><span class="path">/webhook/health</span><div class="desc">Service health check</div></div>
</body></html>
HTML
make_server "${TRAP_DIR}/m2-d4-webhook" 9000 "M2-decoy-webhook"
make_service "pul-decoy-m2-webhook" "${TRAP_DIR}/m2-d4-webhook/server.py" 9000

# D5: CI Status API (8888) — Swagger-like
mkdir -p "${TRAP_DIR}/m2-d5-cistatus"
cat > "${TRAP_DIR}/m2-d5-cistatus/index.html" << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL CI Status API</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Segoe UI',sans-serif;background:#1a1a2e;color:#e0e0e0;padding:20px}
.hdr{display:flex;align-items:center;gap:12px;margin-bottom:20px;border-bottom:1px solid #333;padding-bottom:12px}
.hdr h1{color:#64ffda;font-size:16px}.ver{background:#0f3460;color:#64ffda;padding:2px 8px;border-radius:3px;font-size:10px}
.ep{background:#16213e;border:1px solid #0f3460;border-radius:5px;padding:12px;margin-bottom:8px}
.row{display:flex;align-items:center;gap:10px}.method{padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700}
.get{background:rgba(100,255,218,.15);color:#64ffda}.post{background:rgba(233,69,96,.15);color:#e94560}
.path{font-family:monospace;font-size:12px;color:#e0e0e0}.desc{color:#666;font-size:11px;margin-top:4px}
</style></head>
<body>
<div class="hdr"><h1>PUL CI Status API</h1><span class="ver">v2.1</span><span style="color:#666;font-size:11px">Base: http://203.x.x.x:8888/api</span></div>
<div class="ep"><div class="row"><span class="method get">GET</span><span class="path">/api/pipelines</span></div><div class="desc">List all active pipelines and their status</div></div>
<div class="ep"><div class="row"><span class="method get">GET</span><span class="path">/api/pipelines/{id}/stages</span></div><div class="desc">Get pipeline stage details</div></div>
<div class="ep"><div class="row"><span class="method post">POST</span><span class="path">/api/pipelines/{id}/retry</span></div><div class="desc">Retry failed pipeline (requires API token)</div></div>
<div class="ep"><div class="row"><span class="method get">GET</span><span class="path">/api/artifacts/{build_id}</span></div><div class="desc">Retrieve build artifacts — requires Auth header</div></div>
</body></html>
HTML
make_server "${TRAP_DIR}/m2-d5-cistatus" 8888 "M2-decoy-cistatus"
make_service "pul-decoy-m2-cistatus" "${TRAP_DIR}/m2-d5-cistatus/server.py" 8888

echo "[+] M2 honeytraps active (8929,7990,3001,9000,8888)"

# =============================================================================
# M3 — itops-vault DECOYS
# Ports: 8500 (Consul), 8201 (Vault Enterprise), 8202 (Secrets API), 8443 (PKI), 8022 (SSH helper)
# =============================================================================
echo "[*] Setting up M3 honeytraps..."

mkdir -p "${TRAP_DIR}/m3-d1-consul"
cat > "${TRAP_DIR}/m3-d1-consul/index.html" << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL Consul UI</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',sans-serif;background:#f4f5f5;color:#1d2022}
.hdr{background:#dc477d;padding:0 20px;height:54px;display:flex;align-items:center;gap:12px}
.hdr h1{color:#fff;font-size:16px;font-weight:700}.hdr .sub{color:rgba(255,255,255,.6);font-size:12px}
.nav{background:#fff;border-bottom:1px solid #e5e7eb;display:flex;padding:0 20px}
.nav a{padding:12px 16px;font-size:13px;color:#6b7280;text-decoration:none;border-bottom:2px solid transparent}
.nav a.active{color:#dc477d;border-color:#dc477d}
.main{padding:20px;max-width:800px;margin:0 auto}
.login-card{background:#fff;border:1px solid #e5e7eb;border-radius:8px;padding:24px;max-width:360px;margin:40px auto}
.login-card h2{font-size:15px;margin-bottom:16px;color:#1d2022}
.fg{margin-bottom:12px}.fg label{display:block;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#6b7280;margin-bottom:4px}
.fg input{width:100%;padding:8px 10px;border:1px solid #ddd;border-radius:4px;font-size:13px}
.btn{background:#dc477d;color:#fff;border:none;padding:9px 20px;border-radius:4px;font-size:13px;font-weight:700;cursor:pointer;width:100%}
</style></head>
<body>
<div class="hdr"><h1>Consul UI</h1><div class="sub">Prabal Urja Limited — Service Mesh & Config</div></div>
<nav class="nav"><a href="#" class="active">Services</a><a href="#">Nodes</a><a href="#">Key/Value</a><a href="#">ACL</a></nav>
<div class="main"><div class="login-card">
<h2>ACL Authentication Required</h2>
<div class="fg"><label>Consul Token</label><input type="password" placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"></div>
<button class="btn" onclick="alert('Invalid token. Access denied.')">Authenticate</button>
</div></div>
</body></html>
HTML
make_server "${TRAP_DIR}/m3-d1-consul" 8500 "M3-decoy-consul"
make_service "pul-decoy-m3-consul" "${TRAP_DIR}/m3-d1-consul/server.py" 8500

mkdir -p "${TRAP_DIR}/m3-d2-vault-ent"
cat > "${TRAP_DIR}/m3-d2-vault-ent/index.html" << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL Vault Enterprise</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',sans-serif;background:#0a1929;min-height:100vh;display:flex;align-items:center;justify-content:center}
.card{background:#0d2137;border:1px solid rgba(255,213,0,.2);border-radius:10px;width:400px;overflow:hidden;box-shadow:0 20px 50px rgba(0,0,0,.5)}
.ch{background:rgba(0,0,0,.3);border-bottom:2px solid #ffd500;padding:24px;text-align:center}
.ch .logo{font-size:40px;margin-bottom:8px}.ch h1{color:#ffd500;font-size:16px;font-weight:700}.ch p{color:rgba(255,255,255,.4);font-size:11px;margin-top:3px}
.cb{padding:22px}
.fg{margin-bottom:14px}.fg label{display:block;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.08em;color:rgba(255,255,255,.4);margin-bottom:5px}
.fg input{width:100%;padding:10px 12px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.12);border-radius:6px;color:#fff;font-size:13px;outline:none}
.fg input:focus{border-color:#ffd500}
.btn{width:100%;padding:10px;background:linear-gradient(135deg,#ffd500,#ffdf40);color:#0a1929;border:none;border-radius:6px;font-size:13px;font-weight:800;cursor:pointer}
.ent{text-align:center;margin-top:12px;font-size:10px;color:rgba(255,213,0,.4)}
</style></head>
<body><div class="card">
<div class="ch"><div class="logo">🔑</div><h1>HashiCorp Vault Enterprise</h1><p>Prabal Urja Limited — Secrets Management</p></div>
<div class="cb">
  <div class="fg"><label>Auth Method</label><input type="text" value="Token" readonly style="opacity:.5"></div>
  <div class="fg"><label>Token / Password</label><input type="password" placeholder="hvs.xxxxxxxxxxxx"></div>
  <button class="btn" onclick="alert('Authentication failed. Token invalid or expired.')">Sign In to Vault</button>
  <div class="ent">Vault Enterprise v1.15.4+ent | Cluster: pul-vault-prod</div>
</div></div>
</body></html>
HTML
make_server "${TRAP_DIR}/m3-d2-vault-ent" 8201 "M3-decoy-vault-ent"
make_service "pul-decoy-m3-vault-ent" "${TRAP_DIR}/m3-d2-vault-ent/server.py" 8201

mkdir -p "${TRAP_DIR}/m3-d3-secrets-api"
cat > "${TRAP_DIR}/m3-d3-secrets-api/index.html" << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL Secrets API</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:monospace;background:#1a1a2e;color:#e0e0e0;padding:20px}
h1{color:#e94560;font-size:15px;margin-bottom:4px}.sub{color:#666;font-size:11px;margin-bottom:20px}
.ep{background:#16213e;border:1px solid #0f3460;border-radius:5px;padding:12px;margin-bottom:8px}
.row{display:flex;align-items:center;gap:10px}.tag{padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700}
.get{background:rgba(100,255,218,.15);color:#64ffda}.post{background:rgba(233,69,96,.15);color:#e94560}
.del{background:rgba(255,165,0,.15);color:orange}
.path{font-size:12px}.desc{color:#666;font-size:11px;margin-top:4px}
.auth-note{background:rgba(233,69,96,.08);border:1px solid rgba(233,69,96,.2);border-radius:5px;padding:10px;font-size:11px;color:#e94560;margin-bottom:16px}
</style></head>
<body>
<h1>PUL Secrets Management API</h1>
<div class="sub">v1.2.0 | Internal use only — requires X-Vault-Token header</div>
<div class="auth-note">🔒 All endpoints require a valid Vault token in X-Vault-Token header</div>
<div class="ep"><div class="row"><span class="tag get">GET</span><span class="path">/v1/secret/pul/{path}</span></div><div class="desc">Read a secret from the KV store</div></div>
<div class="ep"><div class="row"><span class="tag post">POST</span><span class="path">/v1/secret/pul/{path}</span></div><div class="desc">Write or update a secret</div></div>
<div class="ep"><div class="row"><span class="tag get">GET</span><span class="path">/v1/auth/approle/login</span></div><div class="desc">AppRole authentication endpoint</div></div>
<div class="ep"><div class="row"><span class="tag del">DELETE</span><span class="path">/v1/secret/pul/{path}</span></div><div class="desc">Delete a secret (admin only)</div></div>
</body></html>
HTML
make_server "${TRAP_DIR}/m3-d3-secrets-api" 8202 "M3-decoy-secrets-api"
make_service "pul-decoy-m3-secrets-api" "${TRAP_DIR}/m3-d3-secrets-api/server.py" 8202

mkdir -p "${TRAP_DIR}/m3-d4-pki"
cat > "${TRAP_DIR}/m3-d4-pki/index.html" << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL PKI Portal</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Segoe UI',sans-serif;background:#f3f4f6;color:#111827}
.hdr{background:#1e3a5f;border-bottom:3px solid #c4a53e;padding:0 20px;height:56px;display:flex;align-items:center;gap:12px}
.hdr h1{color:#c4a53e;font-size:15px;font-weight:700}.hdr p{color:rgba(255,255,255,.4);font-size:11px}
.main{max-width:560px;margin:40px auto;padding:0 20px}
.panel{background:#fff;border:1px solid #e5e7eb;border-radius:8px;overflow:hidden;box-shadow:0 1px 4px rgba(0,0,0,.05)}
.ph{background:#1e3a5f;border-bottom:2px solid #c4a53e;padding:10px 14px;color:#fff;font-size:13px;font-weight:600}
.pb{padding:20px}
.fg{margin-bottom:14px}.fg label{display:block;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#6b7280;margin-bottom:5px}
.fg input,.fg select,.fg textarea{width:100%;padding:8px 12px;border:1px solid #d1d5db;border-radius:5px;font-size:13px}
.fg textarea{height:80px;font-family:monospace;font-size:11px;resize:vertical}
.btn{background:#1e3a5f;color:#fff;border:none;padding:9px 20px;border-radius:5px;font-size:13px;font-weight:600;cursor:pointer}
</style></head>
<body>
<div class="hdr"><div><h1>PUL PKI Certificate Portal</h1><p>Internal CA — Prabal Urja Limited</p></div></div>
<div class="main"><div class="panel">
<div class="ph">Request Certificate</div>
<div class="pb">
  <div class="fg"><label>Common Name (CN)</label><input type="text" placeholder="service.prabalurja.in"></div>
  <div class="fg"><label>Certificate Type</label><select><option>Server TLS</option><option>Client Auth</option><option>Code Signing</option></select></div>
  <div class="fg"><label>CSR (optional)</label><textarea placeholder="-----BEGIN CERTIFICATE REQUEST-----"></textarea></div>
  <div class="fg"><label>Vault Token (required)</label><input type="password" placeholder="hvs.xxxxxxxx"></div>
  <button class="btn" onclick="alert('Authentication failed. Valid Vault token required.')">Request Certificate</button>
</div></div></div>
</body></html>
HTML
make_server "${TRAP_DIR}/m3-d4-pki" 8443 "M3-decoy-pki"
make_service "pul-decoy-m3-pki" "${TRAP_DIR}/m3-d4-pki/server.py" 8443

mkdir -p "${TRAP_DIR}/m3-d5-vault-ssh"
cat > "${TRAP_DIR}/m3-d5-vault-ssh/index.html" << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL Vault SSH Helper</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:monospace;background:#0d1117;color:#c9d1d9;padding:20px}
h1{color:#c4a53e;font-size:15px;margin-bottom:8px}.sub{color:#8b949e;font-size:11px;margin-bottom:20px}
.box{background:#161b22;border:1px solid #21262d;border-radius:6px;padding:16px;margin-bottom:12px}
.box h3{color:#58a6ff;font-size:12px;margin-bottom:8px}
.code{background:#0d1117;border:1px solid #30363d;border-radius:4px;padding:10px;font-size:11px;color:#3fb950;overflow-x:auto}
.fg{margin-bottom:12px}.fg label{display:block;font-size:10px;color:#8b949e;text-transform:uppercase;letter-spacing:.06em;margin-bottom:4px}
.fg input{background:#0d1117;border:1px solid #30363d;border-radius:4px;color:#c9d1d9;padding:7px 10px;width:100%;font-size:12px;font-family:monospace}
.btn{background:#238636;color:#fff;border:none;padding:7px 16px;border-radius:4px;font-size:12px;cursor:pointer}
</style></head>
<body>
<h1>PUL Vault SSH Signer</h1>
<div class="sub">Signs SSH public keys using Vault's SSH secrets engine. Requires valid Vault token.</div>
<div class="box"><h3>Sign Public Key</h3>
<div class="fg"><label>Vault Token</label><input type="password" placeholder="hvs.xxxxxxxxxxxxxxxxx"></div>
<div class="fg"><label>SSH Public Key</label><input type="text" placeholder="ssh-ed25519 AAAA..."></div>
<div class="fg"><label>Target Role</label><input type="text" value="pul-deploy-role" readonly style="opacity:.5"></div>
<button class="btn" onclick="alert('Token validation failed.')">Sign Key</button>
</div>
<div class="box"><h3>Usage</h3>
<div class="code">vault write ssh/sign/pul-deploy-role public_key=@~/.ssh/id_ed25519.pub</div>
</div>
</body></html>
HTML
make_server "${TRAP_DIR}/m3-d5-vault-ssh" 8022 "M3-decoy-vault-ssh"
make_service "pul-decoy-m3-vault-ssh" "${TRAP_DIR}/m3-d5-vault-ssh/server.py" 8022

echo "[+] M3 honeytraps active (8500,8201,8202,8443,8022)"

# =============================================================================
# M4 — itops-monitor DECOYS
# Ports: 3000 (Grafana), 9091 (Prometheus alt), 9093 (AlertManager), 9100 (Node Exporter), 8081 (Zabbix)
# =============================================================================
echo "[*] Setting up M4 honeytraps..."

mkdir -p "${TRAP_DIR}/m4-d1-grafana"
cat > "${TRAP_DIR}/m4-d1-grafana/index.html" << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL Grafana</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',sans-serif;background:#111217;color:#d8d9da;min-height:100vh;display:flex;align-items:center;justify-content:center}
.card{background:#181b1f;border:1px solid #34373f;border-radius:8px;width:400px;overflow:hidden;box-shadow:0 10px 30px rgba(0,0,0,.5)}
.ch{padding:28px;text-align:center;border-bottom:1px solid #34373f}
.ch .logo{font-size:48px;margin-bottom:8px}.ch h1{color:#ff7f00;font-size:18px;font-weight:700}.ch p{color:#6e7281;font-size:12px;margin-top:3px}
.cb{padding:24px}
.fg{margin-bottom:14px}.fg label{display:block;font-size:11px;font-weight:500;color:#6e7281;margin-bottom:5px}
.fg input{width:100%;padding:9px 12px;background:#22252b;border:1px solid #34373f;border-radius:4px;color:#d8d9da;font-size:13px;outline:none}
.fg input:focus{border-color:#ff7f00}
.btn{width:100%;padding:10px;background:#ff7f00;color:#111217;border:none;border-radius:4px;font-size:14px;font-weight:700;cursor:pointer}
.social{display:flex;gap:8px;margin-top:12px}
.social-btn{flex:1;padding:8px;background:#22252b;border:1px solid #34373f;border-radius:4px;font-size:12px;color:#6e7281;cursor:pointer;text-align:center}
</style></head>
<body><div class="card">
<div class="ch"><div class="logo">📊</div><h1>Grafana</h1><p>Prabal Urja Limited — Observability Platform</p></div>
<div class="cb">
  <div class="fg"><label>Email or username</label><input type="text" placeholder="admin"></div>
  <div class="fg"><label>Password</label><input type="password" placeholder="password"></div>
  <button class="btn" onclick="alert('Invalid credentials. Access attempt logged.')">Log in</button>
  <div class="social"><div class="social-btn">Sign in with LDAP</div><div class="social-btn">Sign in with OAuth</div></div>
</div></div>
</body></html>
HTML
make_server "${TRAP_DIR}/m4-d1-grafana" 3000 "M4-decoy-grafana"
make_service "pul-decoy-m4-grafana" "${TRAP_DIR}/m4-d1-grafana/server.py" 3000

mkdir -p "${TRAP_DIR}/m4-d2-prometheus"
cat > "${TRAP_DIR}/m4-d2-prometheus/index.html" << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL Prometheus</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,monospace,sans-serif;background:#fff;color:#333}
.hdr{background:#e6522c;padding:10px 20px;color:#fff;display:flex;align-items:center;gap:10px}
.hdr h1{font-size:16px}.hdr .sub{font-size:12px;opacity:.7}
.nav{background:#f4f4f4;border-bottom:1px solid #ddd;display:flex;padding:0 20px}
.nav a{padding:10px 14px;font-size:13px;color:#666;text-decoration:none;border-bottom:2px solid transparent}
.nav a.active{color:#e6522c;border-color:#e6522c}
.main{padding:20px;max-width:700px}
.qbox{display:flex;gap:8px;margin-bottom:20px}
.qbox input{flex:1;padding:9px 12px;border:1px solid #ddd;border-radius:4px;font-size:13px;font-family:monospace}
.qbox button{background:#e6522c;color:#fff;border:none;padding:9px 18px;border-radius:4px;font-size:13px;cursor:pointer}
.notice{background:#fff8e1;border:1px solid #f59e0b;border-radius:4px;padding:10px;font-size:12px;color:#92400e}
</style></head>
<body>
<div class="hdr"><h1>Prometheus</h1><div class="sub">Prabal Urja Limited — Metrics Platform (Secondary)</div></div>
<nav class="nav"><a href="#" class="active">Graph</a><a href="#">Alerts</a><a href="#">Status</a><a href="#">Help</a></nav>
<div class="main">
  <div class="qbox">
    <input type="text" placeholder="Enter PromQL expression..." value="">
    <button onclick="alert('Query failed: authentication required for this endpoint.')">Execute</button>
  </div>
  <div class="notice">⚠ This Prometheus instance requires authentication. Please provide valid credentials via HTTP Basic Auth.</div>
</div>
</body></html>
HTML
make_server "${TRAP_DIR}/m4-d2-prometheus" 9091 "M4-decoy-prometheus"
make_service "pul-decoy-m4-prometheus" "${TRAP_DIR}/m4-d2-prometheus/server.py" 9091

mkdir -p "${TRAP_DIR}/m4-d3-alertmanager"
cat > "${TRAP_DIR}/m4-d3-alertmanager/index.html" << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL AlertManager</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',sans-serif;background:#f4f5f5;color:#1d2022}
.hdr{background:#e74c3c;padding:0 20px;height:52px;display:flex;align-items:center;gap:10px}
.hdr h1{color:#fff;font-size:15px;font-weight:700}.hdr .sub{color:rgba(255,255,255,.6);font-size:12px}
.main{padding:20px;max-width:700px;margin:0 auto}
.alert{background:#fff;border:1px solid #ddd;border-radius:6px;padding:14px;margin-bottom:10px;border-left:3px solid}
.alert.crit{border-color:#e74c3c}.alert.warn{border-color:#f39c12}
.ah{display:flex;align-items:center;gap:8px;margin-bottom:6px}
.badge{font-size:10.5px;font-weight:700;padding:2px 8px;border-radius:12px}
.badge-c{background:rgba(231,76,60,.1);color:#e74c3c}.badge-w{background:rgba(243,156,18,.1);color:#f39c12}
.aname{font-weight:600;color:#1d2022;font-size:13px}
.adesc{font-size:12px;color:#6b7280}
.ameta{font-size:10.5px;color:#9ca3af;font-family:monospace;margin-top:3px}
</style></head>
<body>
<div class="hdr"><h1>AlertManager</h1><div class="sub">Prabal Urja Limited — Alert Routing</div></div>
<div class="main">
  <div class="alert crit"><div class="ah"><span class="badge badge-c">FIRING</span><span class="aname">VaultSecretEngineDown</span></div><div class="adesc">Vault secrets engine unreachable — AppRole auth may be impacted</div><div class="ameta">203.x.x.x:8200 | firing 14m</div></div>
  <div class="alert warn"><div class="ah"><span class="badge badge-w">FIRING</span><span class="aname">LDAPBindFailureRate</span></div><div class="adesc">LDAP authentication failures exceeding threshold on 203.x.x.x:389</div><div class="ameta">203.x.x.x:389 | firing 9m</div></div>
  <div class="alert warn"><div class="ah"><span class="badge badge-w">FIRING</span><span class="aname">GitScrapeLatencyHigh</span></div><div class="adesc">Gitea metrics scrape latency 340ms — threshold 200ms</div><div class="ameta">203.x.x.x:3000 | firing 3m</div></div>
</div>
</body></html>
HTML
make_server "${TRAP_DIR}/m4-d3-alertmanager" 9093 "M4-decoy-alertmanager"
make_service "pul-decoy-m4-alertmanager" "${TRAP_DIR}/m4-d3-alertmanager/server.py" 9093

mkdir -p "${TRAP_DIR}/m4-d4-nodeexporter"
cat > "${TRAP_DIR}/m4-d4-nodeexporter/index.html" << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Node Exporter</title>
<style>body{font-family:monospace;background:#fff;padding:20px;color:#333}
h1{font-size:14px;color:#e6522c;margin-bottom:10px}
p{font-size:12px;color:#666;margin-bottom:16px}
a{color:#e6522c}
.metrics-preview{background:#f4f4f4;border:1px solid #ddd;border-radius:4px;padding:12px;font-size:11px;line-height:1.7;color:#333}
</style></head>
<body>
<h1>Node Exporter</h1>
<p>Metrics for machine monitoring. <a href="/metrics">Click here to view metrics.</a></p>
<div class="metrics-preview"># HELP node_cpu_seconds_total CPU usage<br>
node_cpu_seconds_total{cpu="0",mode="idle"} 183423.45<br>
node_cpu_seconds_total{cpu="0",mode="system"} 2341.12<br>
# HELP node_memory_MemAvailable_bytes Available memory<br>
node_memory_MemAvailable_bytes 3.24e+09<br>
# HELP node_filesystem_free_bytes Free disk space<br>
node_filesystem_free_bytes{mountpoint="/"} 4.21e+10</div>
</body></html>
HTML
make_server "${TRAP_DIR}/m4-d4-nodeexporter" 9100 "M4-decoy-nodeexporter"
make_service "pul-decoy-m4-nodeexporter" "${TRAP_DIR}/m4-d4-nodeexporter/server.py" 9100

mkdir -p "${TRAP_DIR}/m4-d5-zabbix"
cat > "${TRAP_DIR}/m4-d5-zabbix/index.html" << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL Zabbix</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',sans-serif;background:#d4dce8;min-height:100vh;display:flex;align-items:center;justify-content:center}
.card{background:#fff;border-radius:6px;width:380px;overflow:hidden;box-shadow:0 4px 16px rgba(0,0,0,.15)}
.ch{background:#d40000;padding:18px;text-align:center;color:#fff}
.ch h1{font-size:18px;font-weight:700}.ch p{font-size:11px;opacity:.7;margin-top:3px}
.cb{padding:22px}
.fg{margin-bottom:12px}.fg label{display:block;font-size:11px;color:#777;margin-bottom:4px}
.fg input{width:100%;padding:8px 10px;border:1px solid #ccc;border-radius:3px;font-size:13px}
.fg input:focus{outline:none;border-color:#d40000}
.btn{width:100%;padding:10px;background:#d40000;color:#fff;border:none;border-radius:3px;font-size:14px;font-weight:600;cursor:pointer}
.footer{text-align:center;font-size:10px;color:#aaa;margin-top:12px}
</style></head>
<body><div class="card">
<div class="ch"><h1>ZABBIX</h1><p>Prabal Urja Limited — Infrastructure Monitoring</p></div>
<div class="cb">
  <div class="fg"><label>Username</label><input type="text" placeholder="Admin"></div>
  <div class="fg"><label>Password</label><input type="password" placeholder="zabbix"></div>
  <button class="btn" onclick="alert('Incorrect username or password.')">Sign in</button>
  <div class="footer">Zabbix 6.4.9 | PUL IT Operations</div>
</div></div>
</body></html>
HTML
make_server "${TRAP_DIR}/m4-d5-zabbix" 8081 "M4-decoy-zabbix"
make_service "pul-decoy-m4-zabbix" "${TRAP_DIR}/m4-d5-zabbix/server.py" 8081

echo "[+] M4 honeytraps active (3000,9091,9093,9100,8081)"

# =============================================================================
# M5 — itops-ansible DECOYS
# Ports: 9080 (Jenkins), 8111 (TeamCity), 4440 (Rundeck), 8000 (SaltStack), 9001 (Puppet)
# =============================================================================
echo "[*] Setting up M5 honeytraps..."

mkdir -p "${TRAP_DIR}/m5-d1-jenkins"
cat > "${TRAP_DIR}/m5-d1-jenkins/index.html" << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL Jenkins</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',sans-serif;background:#f0f0f0;color:#333}
.hdr{background:#335061;padding:0 20px;height:54px;display:flex;align-items:center;gap:12px}
.hdr h1{color:#fff;font-size:15px;font-weight:700}.hdr .sub{color:rgba(255,255,255,.5);font-size:12px}
.main{max-width:440px;margin:50px auto;background:#fff;border:1px solid #ddd;border-radius:6px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,.08)}
.mh{background:#335061;padding:14px 20px;color:#fff;font-size:13px;font-weight:600;border-bottom:2px solid #c4a53e}
.mb{padding:22px}
.fg{margin-bottom:14px}.fg label{display:block;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#6b7280;margin-bottom:4px}
.fg input{width:100%;padding:8px 10px;border:1px solid #ccc;border-radius:4px;font-size:13px}
.fg input:focus{outline:none;border-color:#335061}
.btn{background:#335061;color:#fff;border:none;padding:9px 20px;border-radius:4px;font-size:13px;font-weight:700;cursor:pointer;width:100%}
.notice{font-size:11px;color:#9ca3af;margin-top:12px;text-align:center}
</style></head>
<body>
<div class="hdr"><h1>Jenkins</h1><div class="sub">Prabal Urja Limited — CI/CD Automation</div></div>
<div class="main">
<div class="mh">Sign in to Jenkins</div>
<div class="mb">
  <div class="fg"><label>Username</label><input type="text" placeholder="Jenkins username"></div>
  <div class="fg"><label>Password</label><input type="password" placeholder="Jenkins password or API token"></div>
  <button class="btn" onclick="alert('Invalid username or password.')">Sign in</button>
  <div class="notice">Prabal Urja Limited — DevOps Team. Unauthorised access is prohibited.</div>
</div></div>
</body></html>
HTML
make_server "${TRAP_DIR}/m5-d1-jenkins" 9080 "M5-decoy-jenkins"
make_service "pul-decoy-m5-jenkins" "${TRAP_DIR}/m5-d1-jenkins/server.py" 9080

mkdir -p "${TRAP_DIR}/m5-d2-teamcity"
cat > "${TRAP_DIR}/m5-d2-teamcity/index.html" << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL TeamCity</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',sans-serif;background:#20232a;min-height:100vh;display:flex;align-items:center;justify-content:center}
.card{background:#2b2d36;border:1px solid #3c3f4d;border-radius:8px;width:400px;overflow:hidden}
.ch{padding:24px;text-align:center;border-bottom:1px solid #3c3f4d}
.ch .logo{font-size:38px;margin-bottom:8px}.ch h1{color:#fff;font-size:16px;font-weight:700}.ch p{color:#9197a3;font-size:11px;margin-top:3px}
.cb{padding:22px}
.fg{margin-bottom:14px}.fg label{display:block;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.08em;color:#9197a3;margin-bottom:5px}
.fg input{width:100%;padding:9px 12px;background:#20232a;border:1px solid #3c3f4d;border-radius:5px;color:#fff;font-size:13px;outline:none}
.fg input:focus{border-color:#4e9de0}
.btn{width:100%;padding:10px;background:#4e9de0;color:#fff;border:none;border-radius:5px;font-size:13px;font-weight:700;cursor:pointer}
</style></head>
<body><div class="card">
<div class="ch"><div class="logo">🏗</div><h1>TeamCity</h1><p>Prabal Urja Limited — Build Server</p></div>
<div class="cb">
  <div class="fg"><label>Username</label><input type="text" placeholder="username"></div>
  <div class="fg"><label>Password</label><input type="password" placeholder="password"></div>
  <button class="btn" onclick="alert('Authentication failed. Attempt has been logged.')">Log In</button>
</div></div>
</body></html>
HTML
make_server "${TRAP_DIR}/m5-d2-teamcity" 8111 "M5-decoy-teamcity"
make_service "pul-decoy-m5-teamcity" "${TRAP_DIR}/m5-d2-teamcity/server.py" 8111

mkdir -p "${TRAP_DIR}/m5-d3-rundeck"
cat > "${TRAP_DIR}/m5-d3-rundeck/index.html" << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL Rundeck</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',sans-serif;background:#f1f3f5;color:#343a40}
.hdr{background:#222;padding:0 20px;height:52px;display:flex;align-items:center;gap:10px}
.hdr h1{color:#f80;font-size:16px;font-weight:700}.hdr p{color:rgba(255,255,255,.4);font-size:12px}
.main{max-width:420px;margin:50px auto;background:#fff;border:1px solid #dee2e6;border-radius:6px;overflow:hidden;box-shadow:0 2px 6px rgba(0,0,0,.07)}
.mh{background:#222;border-bottom:2px solid #f80;padding:12px 20px;color:#f80;font-size:13px;font-weight:700}
.mb{padding:22px}
.fg{margin-bottom:13px}.fg label{display:block;font-size:11px;color:#6c757d;margin-bottom:4px}
.fg input{width:100%;padding:8px 10px;border:1px solid #ced4da;border-radius:4px;font-size:13px}
.btn{background:#f80;color:#222;border:none;padding:9px 20px;border-radius:4px;font-size:13px;font-weight:700;cursor:pointer;width:100%}
</style></head>
<body>
<div class="hdr"><h1>Rundeck</h1><p>Prabal Urja Limited — Operations Runbook Automation</p></div>
<div class="main">
<div class="mh">Sign In to Rundeck</div>
<div class="mb">
  <div class="fg"><label>Username</label><input type="text" placeholder="admin or LDAP username"></div>
  <div class="fg"><label>Password</label><input type="password" placeholder="password"></div>
  <button class="btn" onclick="alert('Invalid credentials. Access denied.')">Login</button>
</div></div>
</body></html>
HTML
make_server "${TRAP_DIR}/m5-d3-rundeck" 4440 "M5-decoy-rundeck"
make_service "pul-decoy-m5-rundeck" "${TRAP_DIR}/m5-d3-rundeck/server.py" 4440

mkdir -p "${TRAP_DIR}/m5-d4-saltstack"
cat > "${TRAP_DIR}/m5-d4-saltstack/index.html" << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL SaltStack API</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:monospace;background:#1a1a2e;color:#e0e0e0;padding:20px}
h1{color:#00b4d8;font-size:15px;margin-bottom:6px}.sub{color:#666;font-size:11px;margin-bottom:20px}
.ep{background:#16213e;border:1px solid #0f3460;border-radius:5px;padding:12px;margin-bottom:8px}
.row{display:flex;align-items:center;gap:10px}.tag{padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700}
.post{background:rgba(233,69,96,.15);color:#e94560}.get{background:rgba(0,180,216,.15);color:#00b4d8}
.path{font-size:12px}.desc{color:#666;font-size:11px;margin-top:4px}
.auth{background:rgba(0,180,216,.06);border:1px solid rgba(0,180,216,.2);border-radius:5px;padding:10px;font-size:11px;color:#00b4d8;margin-bottom:16px}
</style></head>
<body>
<h1>PUL SaltStack REST API</h1>
<div class="sub">cherrypy-based REST API | v3004 | Requires X-Auth-Token</div>
<div class="auth">🔑 Authenticate first: POST /login with username + password + eauth=pam</div>
<div class="ep"><div class="row"><span class="tag post">POST</span><span class="path">/login</span></div><div class="desc">Authenticate and get session token</div></div>
<div class="ep"><div class="row"><span class="tag post">POST</span><span class="path">/</span></div><div class="desc">Execute Salt commands against minions</div></div>
<div class="ep"><div class="row"><span class="tag get">GET</span><span class="path">/minions</span></div><div class="desc">List all registered Salt minions</div></div>
<div class="ep"><div class="row"><span class="tag get">GET</span><span class="path">/jobs</span></div><div class="desc">List recent job history</div></div>
</body></html>
HTML
make_server "${TRAP_DIR}/m5-d4-saltstack" 8000 "M5-decoy-saltstack"
make_service "pul-decoy-m5-saltstack" "${TRAP_DIR}/m5-d4-saltstack/server.py" 8000

mkdir -p "${TRAP_DIR}/m5-d5-puppet"
cat > "${TRAP_DIR}/m5-d5-puppet/index.html" << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL Puppet Dashboard</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',sans-serif;background:#f9f9f9;color:#2d2d2d}
.hdr{background:#ffae1a;border-bottom:3px solid #333;padding:0 20px;height:52px;display:flex;align-items:center;gap:10px}
.hdr h1{color:#333;font-size:15px;font-weight:800}.hdr p{color:#666;font-size:12px}
.main{max-width:400px;margin:50px auto;background:#fff;border:1px solid #ddd;border-radius:6px;padding:24px;box-shadow:0 2px 6px rgba(0,0,0,.07)}
.main h2{font-size:15px;margin-bottom:16px;color:#2d2d2d;border-bottom:1px solid #eee;padding-bottom:10px}
.fg{margin-bottom:13px}.fg label{display:block;font-size:11px;color:#888;margin-bottom:4px}
.fg input{width:100%;padding:8px 10px;border:1px solid #ccc;border-radius:4px;font-size:13px}
.btn{background:#ffae1a;color:#333;border:none;padding:9px 20px;border-radius:4px;font-size:13px;font-weight:700;cursor:pointer;width:100%;border:2px solid #333}
.notice{font-size:10.5px;color:#aaa;margin-top:10px;text-align:center}
</style></head>
<body>
<div class="hdr"><h1>🐶 Puppet Enterprise</h1><p>Prabal Urja Limited — Configuration Management</p></div>
<div class="main">
  <h2>Console Login</h2>
  <div class="fg"><label>Username</label><input type="text" placeholder="puppet admin or LDAP user"></div>
  <div class="fg"><label>Password</label><input type="password" placeholder="password"></div>
  <button class="btn" onclick="alert('Login failed. Invalid credentials.')">Log in</button>
  <div class="notice">Puppet Enterprise 2023.3 | Managed by IT Operations</div>
</div>
</body></html>
HTML
make_server "${TRAP_DIR}/m5-d5-puppet" 9001 "M5-decoy-puppet"
make_service "pul-decoy-m5-puppet" "${TRAP_DIR}/m5-d5-puppet/server.py" 9001

echo "[+] M5 honeytraps active (9080,8111,4440,8000,9001)"

echo ""
echo "============================================================"
echo "  RNG-IT-02 | M2–M5 Honeytraps All Active"
echo "  M2: 8929 (GitLab), 7990 (Bitbucket), 3001 (Gogs), 9000 (Webhook), 8888 (CI API)"
echo "  M3: 8500 (Consul), 8201 (Vault Ent), 8202 (Secrets API), 8443 (PKI), 8022 (SSH)"
echo "  M4: 3000 (Grafana), 9091 (Prometheus), 9093 (AlertManager), 9100 (NodeExp), 8081 (Zabbix)"
echo "  M5: 9080 (Jenkins), 8111 (TeamCity), 4440 (Rundeck), 8000 (SaltStack), 9001 (Puppet)"
echo "  Logs: ${LOG_DIR}/"
echo "============================================================"
