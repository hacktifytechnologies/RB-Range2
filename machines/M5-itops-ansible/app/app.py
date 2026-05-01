#!/usr/bin/env python3
"""
PUL Ansible Job Runner (AWX-style) Portal
M5 Challenge: Ansible Vault Password + SSH Key in Job Output / File Browser
Range: RNG-IT-02 | OPERATION GRIDFALL
"""

from flask import (Flask, request, render_template, redirect,
                   url_for, session, make_response, jsonify)
import hashlib, logging, os, json, html

app = Flask(__name__)
app.secret_key = 'pul-awx-secret-rngit02-2024'
LOG_DIR = '/var/log/pul-ansible'
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=f'{LOG_DIR}/awx.log', level=logging.INFO,
                    format='%(asctime)s [%(levelname)s] %(message)s')

def h(p): return hashlib.sha256(p.encode()).hexdigest()

USERS = {
    'devops-admin': {'hash': h('DevOps@PUL!24'), 'role': 'admin',    'name': 'DevOps Administrator'},
    'ansible-svc':  {'hash': h('Ansible@Svc!9'), 'role': 'executor', 'name': 'Ansible Service Account'},
}

# ── Seeded job history — contains the vault password + SSH key ────────────────
JOBS = [
    {
        'id': 'JOB-20241115-018',
        'name': 'deploy-dev-infra',
        'template': 'PUL Dev Infrastructure Deployment',
        'status': 'successful',
        'started': '2024-11-15 08:14:33 IST',
        'finished': '2024-11-15 08:17:52 IST',
        'duration': '3m 19s',
        'launched_by': 'svc-deploy',
        'inventory': 'Production (203.x.x.x/24)',
        'output': [
            'PLAY [PUL Dev Infrastructure Deployment] ************************************',
            '',
            'TASK [Gathering Facts] ******************************************************',
            'ok: [203.x.x.x]',
            'ok: [203.x.x.x]',
            '',
            'TASK [Load encrypted vault variables] ***************************************',
            'Executing: ansible-vault decrypt group_vars/all/vault.yml --vault-password-file=/etc/ansible/.vault_pass --output=-',
            'Vault password file: /etc/ansible/.vault_pass',
            'Vault password (read from file): Ansibl3Vault@PUL!GridFall2024',
            '',
            'TASK [Configure deployment SSH key] *****************************************',
            'Changed: [203.x.x.x] => (item=authorized_keys)',
            'Writing SSH private key to /home/deploy/.ssh/id_ed25519 on jump host',
            '-----BEGIN OPENSSH PRIVATE KEY-----',
            'b3BlbnNzaC1rZXktdjEAAAAA BG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW',
            'QyNTUxOQAAACBpdWwtZGV2LWp1bXAta2V5LTIwMjQtZ3JpZGZhbGwAAAAA PLACEHOLDER',
            'KEY-MATERIAL-FOR-EXERCISE devops@dev-jump.prabalurja.in GRIDFALL-2024',
            'AAAA B3NzaC1lZDI1NTE5AAAAIGl1bC1kZXYtanVtcC1rZXktMjAyNC1ncmlkZmFsbA==',
            '-----END OPENSSH PRIVATE KEY-----',
            '',
            'TASK [Deploy application configuration] **************************************',
            'Changed: [203.x.x.x] => {"changed":true,"dest":"/opt/pul-app/.env"}',
            '',
            'TASK [Restart application services] *****************************************',
            'Changed: [203.x.x.x, 203.x.x.x]',
            '',
            'PLAY RECAP ******************************************************************',
            '203.x.x.x  : ok=8  changed=3  unreachable=0  failed=0',
            '203.x.x.x  : ok=6  changed=2  unreachable=0  failed=0',
            '',
            'Deployment completed successfully. Jump host dev-jump.prabalurja.in (11.x.x.x) updated.',
            'SSH access: ssh -i /home/deploy/.ssh/id_ed25519 devops@dev-jump.prabalurja.in',
        ]
    },
    {
        'id': 'JOB-20241115-017',
        'name': 'sync-ldap-groups',
        'template': 'LDAP Group Synchronisation',
        'status': 'successful',
        'started': '2024-11-15 07:00:00 IST',
        'finished': '2024-11-15 07:01:14 IST',
        'duration': '1m 14s',
        'launched_by': 'svc-cicd',
        'inventory': 'Internal (203.x.x.x/24)',
        'output': [
            'PLAY [LDAP Group Sync] ******************************',
            'TASK [Gathering Facts] ok: [203.x.x.x]',
            'TASK [Sync user groups] changed: [203.x.x.x]',
            'PLAY RECAP: ok=3 changed=1 failed=0',
        ]
    },
    {
        'id': 'JOB-20241114-015',
        'name': 'rotate-vault-approle',
        'template': 'Vault AppRole Rotation',
        'status': 'failed',
        'started': '2024-11-14 22:00:00 IST',
        'finished': '2024-11-14 22:02:33 IST',
        'duration': '2m 33s',
        'launched_by': 'devops-admin',
        'inventory': 'Secrets Infra',
        'output': [
            'PLAY [Rotate Vault AppRole] **************************',
            'TASK [Connect to Vault] FAILED: Connection refused — vault may be in dev mode',
            'PLAY RECAP: failed=1',
        ]
    },
]

# Seeded file browser content
FILES = {
    '/': ['group_vars/', 'inventory/', 'playbooks/', 'scripts/', 'README.md'],
    '/group_vars/': ['all/', 'ldap/', 'vault-hosts/'],
    '/group_vars/all/': ['main.yml', 'vault.yml'],
    '/group_vars/all/vault.yml': 'VAULT_ENCRYPTED_FILE',
    '/playbooks/': ['deploy-dev-infra.yml', 'sync-ldap-groups.yml', 'rotate-vault-approle.yml'],
    '/inventory/': ['production.ini', 'staging.ini'],
}

VAULT_FILE_DECRYPTED = """# group_vars/all/vault.yml (decrypted with Ansibl3Vault@PUL!GridFall2024)
# PUL Infrastructure Vault Variables — GRIDFALL Operation
# This file is ansible-vault encrypted at rest

vault_dev_jump_ssh_key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  b3BlbnNzaC1rZXktdjEAAAAA[EXERCISE-KEY-PLACEHOLDER]
  devops@dev-jump.prabalurja.in GridFall-2024-Ed25519
  -----END OPENSSH PRIVATE KEY-----

vault_dev_jump_host: "dev-jump.prabalurja.in"
vault_dev_jump_ip: "11.x.x.x"
vault_dev_jump_user: "devops"
vault_dev_jump_port: 22

vault_dev_zone_cidr: "11.x.x.x/24"
vault_dev_zone_note: "RNG-DEV-01 — Code Forge / CI-CD Zone"

vault_db_password: "PGResDb@PUL!2024"
vault_app_secret: "AppSecret@PUL24!"
"""

@app.route('/')
def index(): return redirect(url_for('login'))

@app.route('/login', methods=['GET','POST'])
def login():
    error = None
    if request.method == 'POST':
        u = request.form.get('username','').strip()
        p = request.form.get('password','')
        user = USERS.get(u)
        if user and user['hash'] == h(p):
            session['user'] = {'username':u,'role':user['role'],'name':user['name']}
            logging.info(f"LOGIN_OK | user={u} from={request.remote_addr}")
            return redirect(url_for('dashboard'))
        logging.warning(f"LOGIN_FAIL | user={u} from={request.remote_addr}")
        error = 'Invalid credentials.'
    return render_template('login.html', error=error)

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

@app.route('/dashboard')
def dashboard():
    if 'user' not in session: return redirect(url_for('login'))
    return render_template('dashboard.html', user=session['user'], jobs=JOBS[:3])

@app.route('/jobs')
def jobs():
    if 'user' not in session: return redirect(url_for('login'))
    return render_template('jobs.html', user=session['user'], jobs=JOBS)

@app.route('/jobs/<job_id>')
def job_detail(job_id):
    if 'user' not in session: return redirect(url_for('login'))
    job = next((j for j in JOBS if j['id'] == job_id), None)
    if not job: return redirect(url_for('jobs'))
    logging.warning(f"JOB_OUTPUT_ACCESS | user={session['user']['username']} | job={job_id} | from={request.remote_addr}")
    return render_template('job_detail.html', user=session['user'], job=job)

@app.route('/files')
def file_browser():
    if 'user' not in session: return redirect(url_for('login'))
    path = request.args.get('path', '/')
    logging.warning(f"FILE_BROWSE | user={session['user']['username']} | path={path} | from={request.remote_addr}")
    content = FILES.get(path)
    is_vault = (path == '/group_vars/all/vault.yml')
    return render_template('file_browser.html', user=session['user'],
                           path=path, content=content, is_vault=is_vault,
                           vault_content=VAULT_FILE_DECRYPTED if is_vault else None)

@app.route('/metrics')
def metrics():
    return make_response(
        '# PUL Ansible AWX Metrics\npul_awx_jobs_total 42\npul_awx_jobs_failed 3\n',
        200, {'Content-Type': 'text/plain'}
    )

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
