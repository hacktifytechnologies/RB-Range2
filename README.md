# RNG-IT-02 — Internal Operations Zone
## OPERATION GRIDFALL | Prabal Urja Limited

**Classification:** RESTRICTED — Exercise White Team Only
**Range:** RNG-IT-02 · Internal Operations Zone (`203.x.x.x/24`)
**Pivot From:** RNG-IT-01 M5 (Redis cache — LDAP bind credential)
**Pivot To:** RNG-DEV-01 (`11.x.x.x/24`) via SSH jump host

---

## Machine Summary

| Machine | Hostname | IP:Port | Service | Vulnerability |
|---|---|---|---|---|
| M1 | itops-ldap | 203.x.x.x:389 | OpenLDAP | Anon bind + `userPassword-plain` attribute |
| M2 | itops-git | 203.x.x.x:3000 | Gitea | Vault AppRole creds in git history |
| M3 | itops-vault | 203.x.x.x:8200 | HashiCorp Vault | Dev mode — root token in systemd journal |
| M4 | itops-monitor | 203.x.x.x:9090 | Prometheus Portal | Unauthenticated `/metrics` — creds in URL labels |
| M5 | itops-ansible | 203.x.x.x:8080 | Ansible AWX | Vault pass + SSH key in verbose job output |

---

## Credential Chain

```
[RNG-IT-01 M5 Pivot In]
cn=svc-deploy:D3pl0y@PUL2024 → LDAP 203.x.x.x:389

M1 → svc-cicd:CICD@Deploy!2024
M2 → VAULT_ROLE_ID=pul-cicd-role-7a3f9b2c1d4e / VAULT_SECRET_ID=3b8f2a1c-...
M3 → pul-vault-root-s3cr3t-2024-gridfall → secret/pul/ad → svc-monitor:M0n!tor@PUL24
M4 → devops-admin:DevOps@PUL!24
M5 → Ansibl3Vault@PUL!GridFall2024 + SSH key → devops@11.x.x.x

[RNG-DEV-01 Pivot Out]
SSH -i dev_jump_key devops@dev-jump.prabalurja.in (11.x.x.x)
```

---

## Setup Instructions

```bash
# On each machine VM, run in order:
sudo bash deps.sh       # Install packages (requires internet)
# [Take snapshot here]
sudo bash setup.sh      # Configure challenge (no internet needed)
sudo bash Honeytraps/M1-decoys-itops-ldap.sh  # M1 only
sudo bash Honeytraps/M2-M5-decoys-itops.sh    # M2-M5 (run on each respective VM)
```

---

## File Structure

```
nexus-itops-range/
├── README.md
├── STORYLINE.md
├── NETWORK_DIAGRAM.md
├── AssessmentQuestions.md
├── github_push.sh
├── Honeytraps/
│   ├── M1-decoys-itops-ldap.sh     (5 decoys)
│   └── M2-M5-decoys-itops.sh       (20 decoys)
├── machines/
│   ├── M1-itops-ldap/
│   ├── M2-itops-git/
│   ├── M3-itops-vault/
│   ├── M4-itops-monitor/
│   └── M5-itops-ansible/
└── ttps/
    ├── red_01_itops-ldap_setup.yml
    ├── red_02_itops-git_setup.yml
    ├── red_03_itops-vault_setup.yml
    ├── red_04_itops-monitor_setup.yml
    └── red_05_itops-ansible_setup.yml
```

**Maintained by:** GRIDFALL Exercise Design Team | **Platform:** NEXUS-IT Purple Team Range
