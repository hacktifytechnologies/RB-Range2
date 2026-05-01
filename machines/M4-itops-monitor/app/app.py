#!/usr/bin/env python3
"""
PUL Internal Monitoring Portal — Prometheus-Style Metrics Dashboard
M4 Challenge: Unauthenticated /metrics endpoint with credentials in scrape target URLs
Range: RNG-IT-02 | OPERATION GRIDFALL
"""

from flask import Flask, request, render_template, redirect, url_for, session, make_response
import hashlib
import logging
import os
import time

app = Flask(__name__)
app.secret_key = 'pul-monitor-secret-rngit02-2024'

LOG_DIR = '/var/log/pul-monitor'
os.makedirs(LOG_DIR, exist_ok=True)

logging.basicConfig(
    filename=f'{LOG_DIR}/monitor.log',
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)

def hash_pw(p): return hashlib.sha256(p.encode()).hexdigest()

USERS = {
    'svc-monitor': {'hash': hash_pw('M0n!tor@PUL24'), 'role': 'monitor', 'name': 'Monitoring Agent'},
    'ops-admin':   {'hash': hash_pw('OpsAdmin@PUL24!'), 'role': 'admin',   'name': 'Operations Admin'},
}

# ── Prometheus /metrics endpoint — VULNERABILITY: credentials in labels ───────
METRICS_OUTPUT = """\
# HELP pul_scrape_target_up Whether the scrape target is reachable (1=up, 0=down)
# TYPE pul_scrape_target_up gauge
pul_scrape_target_up{job="node-exporter",instance="203.x.x.x:9100",zone="ldap"} 1
pul_scrape_target_up{job="node-exporter",instance="203.x.x.x:9100",zone="git"} 1
pul_scrape_target_up{job="node-exporter",instance="203.x.x.x:9100",zone="vault"} 0
pul_scrape_target_up{job="node-exporter",instance="203.x.x.x:9100",zone="monitor"} 1
pul_scrape_target_up{job="node-exporter",instance="203.x.x.x:9100",zone="ansible"} 1

# HELP pul_scrape_target_url Full scrape URL including authentication
# TYPE pul_scrape_target_url gauge
# VULNERABILITY: basic-auth credentials embedded in scrape URL labels
pul_scrape_target_url{job="ansible-metrics",url="http://devops-admin:DevOps%40PUL%2124@203.x.x.x:8080/metrics",zone="ansible"} 1
pul_scrape_target_url{job="vault-metrics",url="http://vault-monitor:VaultMon@PUL!9@203.x.x.x:8200/v1/sys/metrics",zone="vault"} 0
pul_scrape_target_url{job="gitea-metrics",url="http://gitea-prom:GitProm@24!@203.x.x.x:3000/metrics",zone="git"} 1

# HELP pul_grid_power_mw Current grid power output in megawatts
# TYPE pul_grid_power_mw gauge
pul_grid_power_mw{region="north",substation="SUB-N01"} 1842.5
pul_grid_power_mw{region="south",substation="SUB-S04"} 2103.1
pul_grid_power_mw{region="east",substation="SUB-E02"}  987.7

# HELP pul_alert_count Total active alerts by severity
# TYPE pul_alert_count gauge
pul_alert_count{severity="critical"} 2
pul_alert_count{severity="warning"}  7
pul_alert_count{severity="info"}    14

# HELP pul_http_requests_total Total HTTP requests to portal
# TYPE pul_http_requests_total counter
pul_http_requests_total{method="GET",status="200"} 14872
pul_http_requests_total{method="POST",status="200"} 3241
pul_http_requests_total{method="GET",status="401"} 128

# HELP pul_uptime_seconds Service uptime in seconds
# TYPE pul_uptime_seconds counter
pul_uptime_seconds 864300
"""

@app.route('/')
def index():
    return redirect(url_for('login'))

@app.route('/login', methods=['GET','POST'])
def login():
    error = None
    if request.method == 'POST':
        u = request.form.get('username','').strip()
        p = request.form.get('password','')
        user = USERS.get(u)
        if user and user['hash'] == hash_pw(p):
            session['user'] = {'username': u, 'role': user['role'], 'name': user['name']}
            logging.info(f"LOGIN_OK | user={u} from={request.remote_addr}")
            return redirect(url_for('dashboard'))
        logging.warning(f"LOGIN_FAIL | user={u} from={request.remote_addr}")
        error = 'Invalid monitoring credentials.'
    return render_template('login.html', error=error)

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

@app.route('/dashboard')
def dashboard():
    if 'user' not in session:
        return redirect(url_for('login'))
    return render_template('dashboard.html', user=session['user'])

@app.route('/targets')
def targets():
    if 'user' not in session:
        return redirect(url_for('login'))
    return render_template('targets.html', user=session['user'])

@app.route('/alerts')
def alerts():
    if 'user' not in session:
        return redirect(url_for('login'))
    return render_template('alerts.html', user=session['user'])

# VULNERABILITY: /metrics endpoint has NO authentication
@app.route('/metrics')
def metrics():
    logging.warning(f"METRICS_ACCESS | from={request.remote_addr} | ua={request.headers.get('User-Agent','unknown')}")
    resp = make_response(METRICS_OUTPUT)
    resp.headers['Content-Type'] = 'text/plain; version=0.0.4; charset=utf-8'
    return resp

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=9090, debug=False)
