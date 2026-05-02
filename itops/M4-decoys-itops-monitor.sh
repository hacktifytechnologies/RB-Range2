#!/usr/bin/env bash
# =============================================================================
# RNG-IT-02 | M4 — itops-monitor | Honeytraps (7 decoys)
# Ports:
#   6514  — Syslog collector banner (socket)
#   9090  — Grafana Dashboard (web)
#   9300  — PagerDuty-style Incident Manager (web)
#   9301  — Uptime Status Page (web)
#   9302  — SLO Dashboard (web)
#   9303  — APM / Distributed Tracer — Jaeger-style (web)
#   9304  — On-Call Scheduler (web)
# =============================================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
TRAP_DIR="/opt/pul-honeytrap/itops-m4"; LOG_DIR="/var/log/pul-honeytrap"
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

# ─── D1: Syslog Collector Banner — port 6514 ──────────────────────────────────
cat > "${TRAP_DIR}/syslog-banner.py" << 'PYEOF'
#!/usr/bin/env python3
import socket, threading, logging
LOG = "/var/log/pul-honeytrap/itops-m4-syslog.log"
logging.basicConfig(filename=LOG, level=logging.WARNING, format="%(asctime)s %(message)s")
# RFC 5425 syslog-over-TLS — accept connection, log the TLS hello, drop
def handle(conn, addr):
    logging.warning(f"SYSLOG_TLS_CONNECT|src={addr[0]}")
    try:
        data = conn.recv(512)
        if data:
            logging.warning(f"SYSLOG_TLS_DATA|src={addr[0]}|len={len(data)}|first_bytes={data[:8].hex()}")
        # TLS alert — unrecognised name
        conn.sendall(b"\x15\x03\x03\x00\x02\x02\x70")
    except: pass
    finally: conn.close()
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("0.0.0.0", 6514)); srv.listen(20)
while True:
    c, a = srv.accept()
    threading.Thread(target=handle, args=(c, a), daemon=True).start()
PYEOF
make_svc "itops-m4-syslog" "${TRAP_DIR}/syslog-banner.py" 6514

# ─── D2: Grafana Dashboard — port 9090 ────────────────────────────────────────
make_web_svc "grafana" 9090 "itops-m4-grafana" "itops-m4-grafana"
cat > "${TRAP_DIR}/grafana/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Grafana</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',Arial,sans-serif;background:#111217;color:#d8d9da;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#181b1f;border-bottom:2px solid #c4a53e;padding:0 20px;height:56px;display:flex;align-items:center;justify-content:space-between}
.hdr .brand{display:flex;align-items:center;gap:10px}
.hdr .logo{font-size:22px}.hdr h1{color:#f46800;font-size:16px;font-weight:700}
.hdr p{color:rgba(255,255,255,.3);font-size:11px}
.main{flex:1;display:flex;align-items:center;justify-content:center;padding:30px}
.login-card{background:#1f2229;border:1px solid #2c3038;border-radius:8px;width:440px;overflow:hidden;box-shadow:0 20px 50px rgba(0,0,0,.6)}
.lh{background:#181b1f;border-bottom:2px solid #c4a53e;padding:28px;text-align:center}
.lh .g-logo{font-size:48px;margin-bottom:8px}
.lh h2{color:#f46800;font-size:18px;font-weight:700;margin-bottom:4px}
.lh p{color:rgba(255,255,255,.35);font-size:11.5px;letter-spacing:.04em;text-transform:uppercase}
.lb{padding:24px}
.fg{margin-bottom:16px}.fg label{display:block;font-size:11px;font-weight:600;color:rgba(255,255,255,.4);margin-bottom:6px;text-transform:uppercase;letter-spacing:.08em}
.fg input{width:100%;padding:10px 14px;background:#111217;border:1.5px solid #2c3038;border-radius:5px;color:#d8d9da;font-size:14px;outline:none}
.fg input:focus{border-color:#f46800}
.btn{width:100%;padding:11px;background:#f46800;color:#fff;border:none;border-radius:5px;font-size:14px;font-weight:700;cursor:pointer}
.btn:hover{background:#e05900}
.or-divider{text-align:center;color:rgba(255,255,255,.2);font-size:12px;margin:16px 0;position:relative}
.or-divider::before,.or-divider::after{content:'';position:absolute;top:50%;width:42%;height:1px;background:#2c3038}
.or-divider::before{left:0}.or-divider::after{right:0}
.sso-btn{width:100%;padding:10px;background:#1f2229;color:#d8d9da;border:1px solid #2c3038;border-radius:5px;font-size:13px;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:8px}
.sso-btn:hover{border-color:#f46800}
.footer{text-align:center;font-size:10.5px;color:rgba(255,255,255,.15);margin-top:16px}
</style></head>
<body>
<div class="hdr"><div class="brand"><span class="logo">📊</span><h1>Grafana</h1></div><p>Prabal Urja Limited — Observability | pul-grafana.prabalurja.in</p></div>
<div class="main"><div class="login-card">
<div class="lh"><div class="g-logo">📊</div><h2>Welcome to Grafana</h2><p>PUL Monitoring & Observability Platform</p></div>
<div class="lb">
<div class="fg"><label>Email or username</label><input type="text" placeholder="admin@prabalurja.in or grafana-admin"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Password"></div>
<button class="btn" onclick="alert('Invalid username or password.')">Log in</button>
<div class="or-divider">or</div>
<button class="sso-btn" onclick="alert('Redirecting to SAML IdP...')">🔐 &nbsp;Sign in with PUL SSO</button>
<div class="footer">Grafana 10.2.2 | © 2024 Prabal Urja Limited</div>
</div></div></div>
</body></html>
HTML

# ─── D3: PagerDuty-style Incident Manager — port 9300 ────────────────────────
make_web_svc "incident" 9300 "itops-m4-incident" "itops-m4-incident"
cat > "${TRAP_DIR}/incident/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL Incident Manager</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',Arial,sans-serif;background:#f8f8f8;color:#1f2937;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#06ac38;border-bottom:3px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#fff;font-size:16px;font-weight:700}.hdr p{color:rgba(255,255,255,.4);font-size:11px}
.main{flex:1;padding:20px;max-width:1000px;margin:0 auto;width:100%}
.kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:20px}
.kpi{background:#fff;border:1px solid #e5e7eb;border-radius:7px;padding:14px;box-shadow:0 1px 3px rgba(0,0,0,.05)}
.kpi .n{font-size:24px;font-weight:800}.kpi .l{font-size:11px;color:#9ca3af;text-transform:uppercase;letter-spacing:.05em;margin-top:3px}
.kpi.trig .n{color:#e53e3e}.kpi.ack .n{color:#d97706}.kpi.res .n{color:#059669}.kpi.ok .n{color:#06ac38}
.panel{background:#fff;border:1px solid #e5e7eb;border-radius:7px;overflow:hidden;margin-bottom:14px;box-shadow:0 1px 3px rgba(0,0,0,.05)}
.ph{background:#06ac38;color:#fff;padding:10px 14px;font-size:12.5px;font-weight:600;border-bottom:2px solid #c4a53e}
.inc-row{display:flex;align-items:flex-start;gap:10px;padding:10px 14px;border-bottom:1px solid #f3f4f6;font-size:12.5px}
.inc-row:last-child{border-bottom:none}
.inc-sev{width:60px;flex-shrink:0;font-size:10px;font-weight:700;text-align:center}
.sev-p1{background:#dc2626;color:#fff;padding:3px 6px;border-radius:3px}
.sev-p2{background:#f59e0b;color:#fff;padding:3px 6px;border-radius:3px}
.sev-p3{background:#6b7280;color:#fff;padding:3px 6px;border-radius:3px}
.inc-body{flex:1}.inc-title{font-weight:600;color:#1f2937;margin-bottom:3px}.inc-meta{font-size:11px;color:#9ca3af}
.inc-status{width:90px;text-align:right;flex-shrink:0;font-size:10px;font-weight:700}
.s-trig{color:#dc2626}.s-ack{color:#d97706}.s-res{color:#059669}
.login{position:fixed;inset:0;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#fff;border-radius:7px;width:380px;overflow:hidden;box-shadow:0 8px 24px rgba(0,0,0,.15)}
.lh{background:#06ac38;border-bottom:2px solid #c4a53e;padding:16px 20px;color:#fff;font-size:14px;font-weight:700}
.lbody{padding:20px}
.fg{margin-bottom:14px}.fg label{display:block;font-size:11px;font-weight:700;color:#9ca3af;margin-bottom:4px;text-transform:uppercase;letter-spacing:.06em}
.fg input{width:100%;padding:9px 12px;border:1px solid #e5e7eb;border-radius:4px;font-size:13px}
.fg input:focus{outline:none;border-color:#06ac38}
.btn{width:100%;padding:10px;background:#06ac38;color:#fff;border:none;border-radius:4px;font-size:14px;font-weight:700;cursor:pointer}
.footer{background:#06ac38;padding:8px 20px;text-align:center;font-size:10px;color:rgba(255,255,255,.3)}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">🚨 Incident Manager — Sign In</div>
<div class="lbody">
<div class="fg"><label>Email</label><input type="text" placeholder="soc-analyst@prabalurja.in"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Sign In</button>
</div></div></div>
<div class="hdr"><h1>🚨 PUL Incident Manager</h1><p>On-call & Alerting | Grafana OnCall-style | NEXUS-IT SOC</p></div>
<div class="main">
<div class="kpis">
<div class="kpi trig"><div class="n">4</div><div class="l">Triggered</div></div>
<div class="kpi ack"><div class="n">2</div><div class="l">Acknowledged</div></div>
<div class="kpi res"><div class="n">18</div><div class="l">Resolved (24h)</div></div>
<div class="kpi ok"><div class="n">99.1%</div><div class="l">Uptime (30d)</div></div>
</div>
<div class="panel"><div class="ph">Active Incidents</div>
<div class="inc-row"><div class="inc-sev"><span class="sev-p1">P1</span></div><div class="inc-body"><div class="inc-title">itops-vault SNMP agent unreachable — monitoring blind spot</div><div class="inc-meta">Triggered 10:58 IST · Assigned: soc-on-call (rajiv.menon) · Source: Prometheus alerting rule</div></div><div class="inc-status s-trig">TRIGGERED</div></div>
<div class="inc-row"><div class="inc-sev"><span class="sev-p1">P1</span></div><div class="inc-body"><div class="inc-title">Anomalous LDAP bind volume — possible credential stuffing on itgw-sso</div><div class="inc-meta">Triggered 10:47 IST · Assigned: arun.sharma · Source: SIEM rule LDAP-ENUM-001</div></div><div class="inc-status s-ack">ACKNOWLEDGED</div></div>
<div class="inc-row"><div class="inc-sev"><span class="sev-p2">P2</span></div><div class="inc-body"><div class="inc-title">OT DMZ firewall CPU spike &gt;75% — capacity alert</div><div class="inc-meta">Triggered 09:41 IST · Assigned: priya.nair · Source: NMS SNMP threshold</div></div><div class="inc-status s-ack">ACKNOWLEDGED</div></div>
<div class="inc-row"><div class="inc-sev"><span class="sev-p2">P2</span></div><div class="inc-body"><div class="inc-title">Vault root token used operationally — policy violation detected</div><div class="inc-meta">Triggered 10:46 IST · Unassigned · Source: Vault audit log stream</div></div><div class="inc-status s-trig">TRIGGERED</div></div>
</div></div>
<div class="footer">© 2024 Prabal Urja Limited | Incident Manager | NEXUS-IT SOC | Classification: RESTRICTED</div>
</body></html>
HTML

# ─── D4: Uptime Status Page — port 9301 ───────────────────────────────────────
make_web_svc "uptime" 9301 "itops-m4-uptime" "itops-m4-uptime"
cat > "${TRAP_DIR}/uptime/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL System Status</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',Arial,sans-serif;background:#f0f4f8;color:#1a202c;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#2b6cb0;border-bottom:3px solid #c4a53e;padding:0 24px;height:60px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#fff;font-size:18px;font-weight:700}.hdr p{color:rgba(255,255,255,.4);font-size:12px}
.status-banner{background:#276749;border-bottom:1px solid #c6f6d5;padding:14px 24px;text-align:center;font-size:14px;font-weight:700;color:#f0fff4;display:flex;align-items:center;justify-content:center;gap:10px}
.main{flex:1;padding:24px;max-width:860px;margin:0 auto;width:100%}
.section-hdr{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.1em;color:#718096;margin-bottom:10px;margin-top:20px}
.service-row{display:flex;align-items:center;gap:10px;background:#fff;border:1px solid #e2e8f0;border-radius:6px;padding:12px 16px;margin-bottom:6px;box-shadow:0 1px 2px rgba(0,0,0,.04)}
.svc-name{flex:1;font-size:13px;font-weight:600;color:#2d3748}.svc-uptime{font-size:11.5px;color:#718096;width:100px;text-align:right}
.svc-bars{display:flex;gap:2px;align-items:flex-end;width:180px}
.bar-day{width:8px;border-radius:2px;cursor:default}
.bar-up{background:#48bb78}.bar-down{background:#fc8181}.bar-deg{background:#f6ad55}
.badge{display:inline-block;padding:3px 10px;border-radius:12px;font-size:10.5px;font-weight:700;margin-left:8px}
.b-op{background:rgba(72,187,120,.15);color:#276749}.b-deg{background:rgba(246,173,85,.15);color:#b7791f}
.b-down{background:rgba(252,129,129,.15);color:#9b2c2c}
.incident-card{background:#fff;border:1px solid #e2e8f0;border-radius:6px;padding:14px 16px;margin-bottom:8px}
.inc-title{font-size:13px;font-weight:700;color:#2d3748;margin-bottom:4px}.inc-meta{font-size:11.5px;color:#718096}.inc-update{font-size:12px;color:#4a5568;margin-top:6px;line-height:1.5}
.footer{background:#2b6cb0;padding:10px 24px;text-align:center;font-size:10px;color:rgba(255,255,255,.3)}
</style></head>
<body>
<div class="hdr"><h1>⚡ PUL System Status</h1><p>status.prabalurja.in | Operational Dashboard</p></div>
<div class="status-banner">✅ &nbsp;All Core Systems Operational &nbsp;—&nbsp; Last updated: 15 Nov 2024 11:02 IST</div>
<div class="main">
<div class="section-hdr">IT Gateway Services</div>
<div class="service-row"><span class="svc-name">PUL Web Portal &amp; SSO</span><div class="svc-bars">
<div class="bar-day bar-up" style="height:18px" title="Nov 1"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-deg" style="height:12px" title="Degraded"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div>
</div><span class="svc-uptime">99.8% uptime</span><span class="badge b-op">OPERATIONAL</span></div>
<div class="service-row"><span class="svc-name">Mail Relay &amp; Webmail</span><div class="svc-bars">
<div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div>
</div><span class="svc-uptime">100% uptime</span><span class="badge b-op">OPERATIONAL</span></div>
<div class="section-hdr">IT Operations Services</div>
<div class="service-row"><span class="svc-name">Vault Secret Manager</span><div class="svc-bars">
<div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-down" style="height:8px"></div><div class="bar-day bar-up" style="height:18px"></div>
</div><span class="svc-uptime">99.1% uptime</span><span class="badge b-deg">DEGRADED</span></div>
<div class="service-row"><span class="svc-name">CI/CD Pipeline (Git + AWX)</span><div class="svc-bars">
<div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div><div class="bar-day bar-up" style="height:18px"></div>
</div><span class="svc-uptime">100% uptime</span><span class="badge b-op">OPERATIONAL</span></div>
<div class="section-hdr">Active Incidents</div>
<div class="incident-card"><div class="inc-title">🟡 Vault SNMP monitoring agent degraded — Nov 15 10:58 IST</div><div class="inc-meta">Affected: Vault Secret Manager | Severity: Medium</div><div class="inc-update">Update 11:00 — SOC investigating connectivity issue with SNMP agent on itops-vault. Vault API itself is functional. Monitoring coverage temporarily reduced.</div></div>
</div>
<div class="footer">© 2024 Prabal Urja Limited | System Status Page | Powered by NEXUS-IT</div>
</body></html>
HTML

# ─── D5: SLO Dashboard — port 9302 ────────────────────────────────────────────
make_web_svc "slo" 9302 "itops-m4-slo" "itops-m4-slo"
cat > "${TRAP_DIR}/slo/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL SLO Dashboard</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Segoe UI',Arial,sans-serif;background:#0d1117;color:#c9d1d9;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#161b22;border-bottom:2px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#c4a53e;font-size:15px;font-weight:700}.hdr p{color:rgba(255,255,255,.35);font-size:11px}
.main{flex:1;padding:20px;max-width:1000px;margin:0 auto;width:100%}
.slo-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:14px;margin-bottom:16px}
.slo-card{background:#161b22;border:1px solid #21262d;border-radius:8px;padding:18px;position:relative;overflow:hidden}
.slo-card::before{content:'';position:absolute;top:0;left:0;right:0;height:3px}
.slo-card.ok::before{background:#3fb950}.slo-card.warn::before{background:#f59e0b}.slo-card.breach::before{background:#f85149}
.slo-name{font-size:13px;font-weight:700;color:#c9d1d9;margin-bottom:4px}
.slo-desc{font-size:11px;color:#8b949e;margin-bottom:14px}
.slo-value{display:flex;align-items:flex-end;gap:8px;margin-bottom:8px}
.slo-value .actual{font-size:32px;font-weight:800}.slo-card.ok .actual{color:#3fb950}.slo-card.warn .actual{color:#f59e0b}.slo-card.breach .actual{color:#f85149}
.slo-value .target{font-size:13px;color:#8b949e;margin-bottom:6px}
.budget-bar-bg{background:#21262d;border-radius:20px;height:8px;position:relative;overflow:hidden;margin-bottom:6px}
.budget-bar{height:100%;border-radius:20px;position:absolute;left:0}
.budget-bar.ok{background:#3fb950}.budget-bar.warn{background:#f59e0b}.budget-bar.low{background:#f85149}
.budget-label{font-size:11px;color:#8b949e}
.panel{background:#161b22;border:1px solid #21262d;border-radius:7px;overflow:hidden}
.ph{background:#21262d;border-bottom:1px solid #30363d;padding:9px 14px;font-size:12.5px;font-weight:700;color:#c4a53e}
.table{width:100%;border-collapse:collapse;font-size:12px}
.table th{text-align:left;padding:7px 12px;background:#0d1117;color:#8b949e;font-size:10.5px;text-transform:uppercase;letter-spacing:.05em;border-bottom:1px solid #21262d}
.table td{padding:8px 12px;border-bottom:1px solid #161b22;color:#c9d1d9}
.table tr:hover td{background:#1c2128}
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
<div class="lh">📐 SLO Dashboard — Login</div>
<div class="lbody">
<div class="fg"><label>Username</label><input type="text" placeholder="sre-lead or monitoring-admin"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Sign In</button>
</div></div></div>
<div class="hdr"><h1>📐 PUL SLO Dashboard</h1><p>Service Level Objectives | SRE Portal | NEXUS-IT</p></div>
<div class="main">
<div class="slo-grid">
<div class="slo-card ok">
<div class="slo-name">IT Portal Availability</div>
<div class="slo-desc">Web portal &amp; SSO — monthly rolling window</div>
<div class="slo-value"><span class="actual">99.82%</span><span class="target">target: 99.5%</span></div>
<div class="budget-bar-bg"><div class="budget-bar ok" style="width:88%"></div></div>
<div class="budget-label">Error budget: 88% remaining (26.2 min used of 3.6h)</div>
</div>
<div class="slo-card warn">
<div class="slo-name">Vault P99 Latency</div>
<div class="slo-desc">Secret reads &lt; 150ms at P99 — rolling 7d</div>
<div class="slo-value"><span class="actual">148ms</span><span class="target">target: &lt;150ms</span></div>
<div class="budget-bar-bg"><div class="budget-bar warn" style="width:12%"></div></div>
<div class="budget-label">Error budget: 12% remaining — approaching breach ⚠</div>
</div>
<div class="slo-card ok">
<div class="slo-name">CI/CD Pipeline Success Rate</div>
<div class="slo-desc">Build job success rate — rolling 30d</div>
<div class="slo-value"><span class="actual">97.4%</span><span class="target">target: 95%</span></div>
<div class="budget-bar-bg"><div class="budget-bar ok" style="width:74%"></div></div>
<div class="budget-label">Error budget: 74% remaining</div>
</div>
<div class="slo-card breach">
<div class="slo-name">LDAP Authentication P95</div>
<div class="slo-desc">Auth request latency &lt; 200ms P95 — rolling 7d</div>
<div class="slo-value"><span class="actual">412ms</span><span class="target">target: &lt;200ms</span></div>
<div class="budget-bar-bg"><div class="budget-bar low" style="width:0%"></div></div>
<div class="budget-label">Error budget: BREACHED — SLO violation active 🔴</div>
</div>
</div></div>
</body></html>
HTML

# ─── D6: APM / Distributed Tracer — Jaeger-style — port 9303 ─────────────────
make_web_svc "apm" 9303 "itops-m4-apm" "itops-m4-apm"
cat > "${TRAP_DIR}/apm/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL APM Tracer</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,'Segoe UI',Arial,sans-serif;background:#f5f6f7;color:#24272e;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#60b0f4;border-bottom:3px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#fff;font-size:16px;font-weight:700}.hdr p{color:rgba(255,255,255,.5);font-size:11px}
.search-bar{background:#fff;border-bottom:1px solid #e0e0e0;padding:12px 20px;display:flex;gap:10px;align-items:center}
.search-bar select,.search-bar input{padding:7px 10px;border:1px solid #ddd;border-radius:4px;font-size:12.5px;outline:none}
.search-bar select:focus,.search-bar input:focus{border-color:#60b0f4}
.search-bar button{background:#60b0f4;color:#fff;border:none;padding:7px 18px;border-radius:4px;font-size:12.5px;font-weight:700;cursor:pointer}
.main{flex:1;padding:16px 20px;max-width:1100px;margin:0 auto;width:100%}
.trace-row{background:#fff;border:1px solid #e0e0e0;border-radius:5px;padding:12px 16px;margin-bottom:8px;box-shadow:0 1px 2px rgba(0,0,0,.04)}
.tr-hdr{display:flex;align-items:center;gap:10px;margin-bottom:8px}
.tr-svc{font-size:12.5px;font-weight:700;color:#60b0f4}.tr-op{font-size:12.5px;color:#24272e;flex:1}
.tr-dur{font-size:12px;color:#9e9e9e;width:80px;text-align:right}.tr-spans{font-size:11.5px;color:#9e9e9e}
.tr-bar-bg{background:#e0e0e0;border-radius:20px;height:6px;position:relative;overflow:hidden;margin-bottom:6px}
.tr-bar{height:100%;border-radius:20px;background:#60b0f4;position:absolute;left:0}
.tr-bar.err{background:#f85149}.tr-bar.slow{background:#f59e0b}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700}
.b-ok{background:rgba(63,185,80,.12);color:#2e7d32}.b-err{background:rgba(248,81,73,.12);color:#c62828}
.b-slow{background:rgba(245,158,11,.12);color:#e65100}
.login{position:fixed;inset:0;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#fff;border-radius:6px;width:380px;overflow:hidden;box-shadow:0 8px 24px rgba(0,0,0,.15)}
.lh{background:#60b0f4;border-bottom:2px solid #c4a53e;padding:16px 20px;color:#fff;font-size:14px;font-weight:700}
.lbody{padding:20px}
.fg{margin-bottom:14px}.fg label{display:block;font-size:11px;font-weight:700;color:#9e9e9e;margin-bottom:4px;text-transform:uppercase;letter-spacing:.06em}
.fg input{width:100%;padding:9px 12px;border:1px solid #ddd;border-radius:4px;font-size:13px}
.fg input:focus{outline:none;border-color:#60b0f4}
.btn{width:100%;padding:10px;background:#60b0f4;color:#fff;border:none;border-radius:4px;font-size:14px;font-weight:700;cursor:pointer}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">🔬 APM Tracer — Login</div>
<div class="lbody">
<div class="fg"><label>Username</label><input type="text" placeholder="sre-lead or devops-admin"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Sign In</button>
</div></div></div>
<div class="hdr"><h1>🔬 PUL APM — Distributed Tracer</h1><p>Jaeger / OpenTelemetry | pul-apm.prabalurja.in</p></div>
<div class="search-bar">
<select><option>itgw-webportal</option><option>itgw-sso</option><option>itops-vault</option><option>itops-git</option><option>all services</option></select>
<input type="text" placeholder="Operation / endpoint" style="width:200px">
<input type="text" placeholder="Trace ID" style="width:220px">
<button>Find Traces</button>
</div>
<div class="main">
<div class="trace-row">
<div class="tr-hdr"><span class="tr-svc">itgw-sso</span><span class="tr-op">POST /saml/sso/post → LDAP bind cn=svc-deploy</span><span class="tr-spans">14 spans</span><span class="tr-dur">412ms</span><span class="badge b-slow">SLOW</span></div>
<div class="tr-bar-bg"><div class="tr-bar slow" style="width:82%"></div></div>
<div style="font-size:10.5px;color:#9e9e9e">3c2b1a0f9e8d7c6b · Nov 15 10:47:12</div>
</div>
<div class="trace-row">
<div class="tr-hdr"><span class="tr-svc">itops-vault</span><span class="tr-op">GET /v1/secret/pul/ad (AppRole auth)</span><span class="tr-spans">6 spans</span><span class="tr-dur">28ms</span><span class="badge b-ok">OK</span></div>
<div class="tr-bar-bg"><div class="tr-bar" style="width:6%"></div></div>
<div style="font-size:10.5px;color:#9e9e9e">9f8e7d6c5b4a3928 · Nov 15 10:44:55</div>
</div>
<div class="trace-row">
<div class="tr-hdr"><span class="tr-svc">itops-git</span><span class="tr-op">GET /api/v1/repos/svc-cicd/pul-infra-config/contents</span><span class="tr-spans">3 spans</span><span class="tr-dur">8ms</span><span class="badge b-ok">OK</span></div>
<div class="tr-bar-bg"><div class="tr-bar" style="width:2%"></div></div>
<div style="font-size:10.5px;color:#9e9e9e">a7f3b2c1d4e9f8a3 · Nov 15 10:46:18</div>
</div>
<div class="trace-row">
<div class="tr-hdr"><span class="tr-svc">itops-monitor</span><span class="tr-op">GET /metrics — unauthenticated (no bearer token)</span><span class="tr-spans">1 span</span><span class="tr-dur">2ms</span><span class="badge b-err">401</span></div>
<div class="tr-bar-bg"><div class="tr-bar err" style="width:1%"></div></div>
<div style="font-size:10.5px;color:#9e9e9e">b2c1d4e9f8a37f3b · Nov 15 10:43:11</div>
</div>
</div>
</body></html>
HTML

# ─── D7: On-Call Scheduler — port 9304 ────────────────────────────────────────
make_web_svc "oncall" 9304 "itops-m4-oncall" "itops-m4-oncall"
cat > "${TRAP_DIR}/oncall/index.html" << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>PUL On-Call Scheduler</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Segoe UI',Arial,sans-serif;background:#f8fafc;color:#1e293b;min-height:100vh;display:flex;flex-direction:column}
.hdr{background:#1e3a5f;border-bottom:3px solid #c4a53e;padding:0 20px;height:54px;display:flex;align-items:center;justify-content:space-between}
.hdr h1{color:#c4a53e;font-size:15px;font-weight:700}.hdr p{color:rgba(255,255,255,.35);font-size:11px}
.main{flex:1;padding:20px;max-width:1000px;margin:0 auto;width:100%}
.current-oncall{background:linear-gradient(135deg,#1e3a5f,#2d5a8e);border:1px solid #c4a53e;border-radius:8px;padding:20px;margin-bottom:20px;display:flex;align-items:center;gap:16px}
.co-avatar{width:52px;height:52px;border-radius:50%;background:#c4a53e;display:flex;align-items:center;justify-content:center;font-size:22px;flex-shrink:0}
.co-info .label{font-size:10.5px;color:rgba(255,255,255,.4);text-transform:uppercase;letter-spacing:.08em;margin-bottom:4px}
.co-info .name{font-size:17px;font-weight:700;color:#fff}.co-info .meta{font-size:12px;color:rgba(255,255,255,.5);margin-top:2px}
.co-ends{margin-left:auto;text-align:right}.co-ends .label{font-size:10.5px;color:rgba(255,255,255,.4);text-transform:uppercase;letter-spacing:.08em}.co-ends .val{font-size:13px;color:#c4a53e;font-weight:600}
.panel{background:#fff;border:1px solid #e2e8f0;border-radius:7px;overflow:hidden;margin-bottom:14px;box-shadow:0 1px 3px rgba(0,0,0,.05)}
.ph{background:#1e3a5f;color:#c4a53e;padding:10px 14px;font-size:12.5px;font-weight:700;border-bottom:2px solid #c4a53e}
.sched-row{display:flex;align-items:center;gap:10px;padding:10px 14px;border-bottom:1px solid #f1f5f9;font-size:12.5px}
.sched-row:last-child{border-bottom:none}
.sched-date{width:140px;flex-shrink:0;color:#64748b;font-family:monospace;font-size:11.5px}
.sched-who{font-weight:600;color:#1e293b;flex:1}.sched-team{color:#94a3b8;font-size:11.5px}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700}
.b-now{background:rgba(196,165,62,.2);color:#b8860b}
.login{position:fixed;inset:0;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;z-index:99}
.lb{background:#fff;border-radius:7px;width:360px;overflow:hidden}
.lh{background:#1e3a5f;border-bottom:2px solid #c4a53e;padding:14px 18px;color:#c4a53e;font-size:13px;font-weight:700}
.lbody{padding:18px}
.fg{margin-bottom:12px}.fg label{display:block;font-size:10.5px;font-weight:700;color:#64748b;margin-bottom:4px;text-transform:uppercase;letter-spacing:.07em}
.fg input{width:100%;padding:8px 10px;border:1px solid #e2e8f0;border-radius:4px;font-size:13px}
.btn{width:100%;padding:9px;background:#1e3a5f;color:#fff;border:none;border-radius:4px;font-size:13px;font-weight:700;cursor:pointer}
.footer{background:#1e3a5f;padding:8px 20px;text-align:center;font-size:10px;color:rgba(255,255,255,.25)}
</style></head>
<body>
<div class="login" id="ov"><div class="lb">
<div class="lh">📅 On-Call Scheduler — Login</div>
<div class="lbody">
<div class="fg"><label>Username</label><input type="text" placeholder="your username"></div>
<div class="fg"><label>Password</label><input type="password" placeholder="Password"></div>
<button class="btn" onclick="document.getElementById('ov').style.display='none'">Sign In</button>
</div></div></div>
<div class="hdr"><h1>📅 PUL On-Call Scheduler</h1><p>SOC &amp; IT Operations | pul-oncall.prabalurja.in</p></div>
<div class="main">
<div class="current-oncall">
<div class="co-avatar">👤</div>
<div class="co-info"><div class="label">Currently On-Call — SOC / IT Ops</div><div class="name">Rajiv Menon</div><div class="meta">rajiv.menon@prabalurja.in · +91-98XXXXXXXX · SOC Lead</div></div>
<div class="co-ends"><div class="label">Shift Ends</div><div class="val">Nov 16 08:00 IST</div></div>
</div>
<div class="panel"><div class="ph">Upcoming On-Call Rotation — SOC Team</div>
<div class="sched-row"><span class="sched-date">Nov 15–16 (Now)</span><span class="sched-who">Rajiv Menon</span><span class="sched-team">SOC Lead</span><span class="badge b-now">ON CALL</span></div>
<div class="sched-row"><span class="sched-date">Nov 16–17</span><span class="sched-who">Arun Sharma</span><span class="sched-team">IT Infrastructure</span></div>
<div class="sched-row"><span class="sched-date">Nov 17–18</span><span class="sched-who">Priya Nair</span><span class="sched-team">IT Operations</span></div>
<div class="sched-row"><span class="sched-date">Nov 18–19</span><span class="sched-who">Deepa Iyer</span><span class="sched-team">Grid Ops (backup SOC)</span></div>
<div class="sched-row"><span class="sched-date">Nov 19–20</span><span class="sched-who">Rajiv Menon</span><span class="sched-team">SOC Lead</span></div>
</div></div>
<div class="footer">© 2024 Prabal Urja Limited | On-Call Scheduler | NEXUS-IT SOC</div>
</body></html>
HTML

echo ""
echo "============================================================"
echo "  RNG-IT-02 | M4 itops-monitor — Honeytraps Active"
echo "  D1: Syslog TLS banner (socket) → port 6514"
echo "  D2: Grafana Dashboard          → port 9090"
echo "  D3: Incident Manager           → port 9300"
echo "  D4: Uptime Status Page         → port 9301"
echo "  D5: SLO Dashboard              → port 9302"
echo "  D6: APM / Distributed Tracer   → port 9303"
echo "  D7: On-Call Scheduler          → port 9304"
echo "  Logs: ${LOG_DIR}/itops-m4-*.log"
echo "============================================================"
