#!/usr/bin/env python3
"""
M5 — itops-ansible | app.py
PUL Ansible AWX Job Runner Portal
Challenge: Ansible Vault Password + SSH Private Key Exposed in Verbose Job Output
Range: RNG-IT-02 | OPERATION GRIDFALL
MITRE: T1552.001 (Credentials in Files) · T1552.004 (Private Keys)

UPDATED: SSH private key and jump host IP are loaded dynamically from files
written by setup.sh at deploy time. The key is never hardcoded in this file.
Files consumed:
  /etc/pul-gridfall/job_config.json      — jump host IP + key file path
  /opt/pul-awx/app/data/job_output_018.txt — full job output with live key
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

# ── Dynamic config: loaded from files written by setup.sh ─────────────────────

JOB_OUTPUT_FILE = os.path.join(os.path.dirname(__file__), 'data', 'job_output_018.txt')
JOB_CONFIG_FILE = '/etc/pul-gridfall/job_config.json'

def _load_job_config() -> dict:
    """Load jump host IP and key metadata written by setup.sh."""
    try:
        with open(JOB_CONFIG_FILE, 'r') as f:
            return json.load(f)
    except Exception:
        return {'jump_host_ip': '11.x.x.x', 'key_comment': 'devops@dev-jump.prabalurja.in GRIDFALL-2024'}

def _load_job_output_018() -> list:
    """
    Load the verbose job output for JOB-20241115-018 from the file written by setup.sh.
    This file contains the REAL SSH private key generated at setup time.
    Falls back to a placeholder list if the file has not been written yet (dev mode).
    Returns a list of strings (one per output line) to match the JOBS structure.
    """
    try:
        with open(JOB_OUTPUT_FILE, 'r') as f:
            content = f.read()
        # Return as list of lines (strip trailing newline per line)
        return content.splitlines()
    except FileNotFoundError:
        cfg = _load_job_config()
        ip  = cfg.get('jump_host_ip', '11.x.x.x')
        return [
            'TASK [Configure deployment SSH key] *************************************',
            f'Changed: [{ip}] => (item=authorized_keys)',
            'Writing SSH private key to /home/deploy/.ssh/id_ed25519 on jump host',
            '',
            '-----BEGIN OPENSSH PRIVATE KEY-----',
            '[ KEY NOT YET GENERATED — Run setup.sh on this machine first ]',
            '-----END OPENSSH PRIVATE KEY-----',
            '',
            'TASK [Deploy application configuration] **********************************',
            f'Changed: [{ip}] => {{"changed":true,"dest":"/opt/pul-app/.env"}}',
            '',
            'TASK [Restart application services] *************************************',
            f'Changed: [{ip}]',
        ]

# ── Seeded job history ─────────────────────────────────────────────────────────
# JOB-20241115-018 output is loaded dynamically at request time.
# Other jobs are static and do not contain sensitive material.

JOBS_STATIC = [
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
        'verbose': False,
        'output': [
            'PLAY [LDAP Group Sync] **************************************************',
            'TASK [Gathering Facts] ok: [203.x.x.x]',
            'TASK [Sync user groups] changed: [203.x.x.x]',
            'PLAY RECAP: ok=3 changed=1 failed=0',
        ]
    },
    {
        'id': 'JOB-20241115-016',
        'name': 'backup-config',
        'template': 'PUL Configuration Backup',
        'status': 'successful',
        'started': '2024-11-15 06:00:00 IST',
        'finished': '2024-11-15 06:04:22 IST',
        'duration': '4m 22s',
        'launched_by': 'svc-cicd',
        'inventory': 'Internal (203.x.x.x/24)',
        'verbose': False,
        'output': [
            'PLAY [PUL Configuration Backup] *****************************************',
            'TASK [Gathering Facts] ok: [203.x.x.x]',
            'TASK [Archive configs] changed: [203.x.x.x]',
            'TASK [Upload to store] changed: [203.x.x.x]',
            'PLAY RECAP: ok=5 changed=2 failed=0',
        ]
    },
    {
        'id': 'JOB-20241114-015',
        'name': 'patch-linux-hosts',
        'template': 'Linux Host Patching',
        'status': 'failed',
        'started': '2024-11-14 22:00:00 IST',
        'finished': '2024-11-14 22:12:08 IST',
        'duration': '12m 8s',
        'launched_by': 'ansible-svc',
        'inventory': 'Production (203.x.x.x/24)',
        'verbose': False,
        'output': [
            'PLAY [Linux Host Patching] **********************************************',
            'TASK [Gathering Facts] ok: [203.x.x.x]',
            'TASK [apt update] ok: [203.x.x.x]',
            'TASK [apt upgrade] FAILED: [203.x.x.x] - dpkg lock held',
            'PLAY RECAP: ok=3 changed=0 failed=1',
        ]
    },
]

def get_jobs_list():
    """Return full job list with JOB-20241115-018 at the top, loaded fresh each call."""
    cfg = _load_job_config()
    ip  = cfg.get('jump_host_ip', '11.x.x.x')
    job_018 = {
        'id': 'JOB-20241115-018',
        'name': 'deploy-dev-infra',
        'template': 'PUL Dev Infrastructure Deployment',
        'status': 'successful',
        'started': '2024-11-15 08:14:33 IST',
        'finished': '2024-11-15 08:17:52 IST',
        'duration': '3m 19s',
        'launched_by': 'svc-deploy',
        'inventory': 'Production (203.x.x.x/24)',
        'verbose': True,
        'verbose_warn': 'Verbose mode was enabled for this job run — full task output including secret operations is logged below.',
        # output loaded dynamically — see get_job_018_output()
        'output': None,
        'pivot_target': f'devops@dev-jump.prabalurja.in ({ip})',
    }
    return [job_018] + JOBS_STATIC

def get_job_018_output() -> list:
    """Return the live job output lines for JOB-20241115-018."""
    return _load_job_output_018()

# ── Vault file browser content ─────────────────────────────────────────────────

def _get_vault_decrypted_preview() -> str:
    """Build the decrypted vault preview shown in the file browser."""
    cfg = _load_job_config()
    ip  = cfg.get('jump_host_ip', '11.x.x.x')
    key_comment = cfg.get('key_comment', 'devops@dev-jump.prabalurja.in GRIDFALL-2024')
    # Try to read the actual key for display in file browser
    try:
        priv_key_path = cfg.get('priv_key_path', '/etc/pul-gridfall/jump_ed25519')
        with open(priv_key_path, 'r') as f:
            key_material = f.read().strip()
    except Exception:
        key_material = (
            "-----BEGIN OPENSSH PRIVATE KEY-----\n"
            "[ KEY NOT YET GENERATED — Run setup.sh first ]\n"
            "-----END OPENSSH PRIVATE KEY-----"
        )

    return f"""vault_ansible_vault_password: "Ansibl3Vault@PUL!GridFall2024"

vault_dev_jump_ssh_key: |
{chr(10).join('  ' + line for line in key_material.splitlines())}

vault_dev_jump_host: "dev-jump.prabalurja.in"
vault_dev_jump_ip: "{ip}"
vault_dev_jump_user: "devops"
vault_dev_jump_port: 22

vault_dev_zone_cidr: "11.x.x.x/24"
vault_dev_zone_note: "RNG-DEV-01 — Code Forge / CI-CD Zone"

vault_db_password: "PGResDb@PUL!2024"
vault_app_secret: "AppSecret@PUL24!"
"""

FILE_TREE = {
    '/': ['group_vars/', 'inventory/', 'playbooks/', 'roles/', 'ansible.cfg'],
    '/group_vars/': ['all/'],
    '/group_vars/all/': ['vault.yml', 'vars.yml'],
    '/inventory/': ['production.ini', 'staging.ini'],
    '/playbooks/': ['deploy-dev-infra.yml', 'sync-ldap-groups.yml', 'backup-config.yml'],
}

# ── Routes ─────────────────────────────────────────────────────────────────────

@app.route('/')
def index(): return redirect(url_for('login'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    error = None
    if request.method == 'POST':
        u = request.form.get('username', '').strip()
        p = request.form.get('password', '')
        user = USERS.get(u)
        if user and user['hash'] == h(p):
            session['user'] = {'username': u, 'role': user['role'], 'name': user['name']}
            logging.info(f"LOGIN_OK | user={u} from={request.remote_addr}")
            return redirect(url_for('dashboard'))
        logging.warning(f"LOGIN_FAIL | user={u} from={request.remote_addr}")
        error = 'Invalid username or password.'
    return render_template('login.html', error=error)

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

@app.route('/dashboard')
def dashboard():
    if 'user' not in session:
        return redirect(url_for('login'))
    jobs = get_jobs_list()
    stats = {
        'total': len(jobs),
        'successful': sum(1 for j in jobs if j['status'] == 'successful'),
        'failed': sum(1 for j in jobs if j['status'] == 'failed'),
        'running': 0,
    }
    return render_template('dashboard.html', jobs=jobs, stats=stats, user=session['user'])

@app.route('/jobs')
def jobs():
    if 'user' not in session:
        return redirect(url_for('login'))
    return render_template('jobs.html', jobs=get_jobs_list(), user=session['user'])

@app.route('/jobs/<job_id>')
def job_detail(job_id):
    if 'user' not in session:
        return redirect(url_for('login'))
    logging.info(f"JOB_VIEW | job={job_id} user={session['user']['username']} from={request.remote_addr}")
    jobs = get_jobs_list()
    job  = next((j for j in jobs if j['id'] == job_id), None)
    if not job:
        return "Job not found", 404
    # Load live output for the target job
    if job_id == 'JOB-20241115-018':
        output = get_job_018_output()
        logging.warning(f"SENSITIVE_JOB_ACCESSED | job=JOB-20241115-018 user={session['user']['username']} from={request.remote_addr}")
    else:
        output = job.get('output', [])
    # Assign back to job dict so templates accessing job.output directly also work
    job['output'] = output
    return render_template('job_detail.html', job=job, output=output, user=session['user'])

@app.route('/files')
def files():
    if 'user' not in session:
        return redirect(url_for('login'))
    path  = request.args.get('path', '/')
    error = None
    content = None
    is_file = False
    filename = None

    # Normalise path
    if not path.startswith('/'):
        path = '/' + path

    if path == '/group_vars/all/vault.yml':
        is_file  = True
        filename = 'vault.yml'
        content  = html.escape(_get_vault_decrypted_preview())
        logging.warning(f"VAULT_FILE_ACCESSED | user={session['user']['username']} from={request.remote_addr}")
    elif path.endswith('/') or path == '/':
        children = FILE_TREE.get(path, [])
    else:
        # Generic file stub
        is_file  = True
        filename = path.split('/')[-1]
        content  = html.escape(f'# {filename}\n# PUL NEXUS-IT automation file\n# Contact: devops@prabalurja.in\n')

    children = FILE_TREE.get(path, []) if not is_file else []
    return render_template('file_browser.html',
                           path=path, children=children,
                           is_file=is_file, filename=filename,
                           content=content, error=error,
                           user=session['user'])

@app.route('/health')
def health():
    return jsonify({'status': 'healthy', 'service': 'pul-awx', 'version': '4.5.1'})

# ── Run ────────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
