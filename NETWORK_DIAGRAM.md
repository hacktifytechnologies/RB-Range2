# Network Diagram — RNG-IT-02 · Internal Operations Zone
## OPERATION GRIDFALL

```
                          ╔══════════════════════════════════════════╗
                          ║  RNG-IT-01 · Corporate Gateway           ║
                          ║  203.x.x.x/24                            ║
                          ║  M5 itops-cache: 203.x.x.x:6379        ║
                          ║  Redis — cn=svc-deploy:D3pl0y@PUL2024   ║
                          ╚══════════════════════╦═══════════════════╝
                                                 │  Pivot credential
                                                 ▼
╔══════════════════════════════════════════════════════════════════════════╗
║  v-Public | RNG-IT-02 — Internal Operations Zone | 203.x.x.x/24         ║
║                                                                          ║
║  ┌─────────────────┐   LDAP enum    ┌─────────────────┐                 ║
║  │ M1 itops-ldap   │ ─────────────► │ M2 itops-git    │                 ║
║  │ 203.x.x.x:389  │  svc-cicd cred │ 203.x.x.x:3000 │                 ║
║  │ OpenLDAP        │                │ Gitea           │                 ║
║  │ VULN: anon bind │                │ VULN: git hist  │                 ║
║  └─────────────────┘                └────────┬────────┘                 ║
║                                              │ Vault AppRole            ║
║                                              ▼                          ║
║                                    ┌─────────────────┐                  ║
║                                    │ M3 itops-vault  │                  ║
║                                    │ 203.x.x.x:8200 │                  ║
║                                    │ HashiCorp Vault  │                  ║
║                                    │ VULN: dev mode  │                  ║
║                                    └────────┬────────┘                  ║
║                                             │ secret/pul/ad             ║
║                                             ▼                           ║
║                                    ┌─────────────────┐                  ║
║                                    │ M4 itops-monitor│                  ║
║                                    │ 203.x.x.x:9090 │                  ║
║                                    │ Prometheus UI   │                  ║
║                                    │ VULN: /metrics  │                  ║
║                                    └────────┬────────┘                  ║
║                                             │ devops-admin cred         ║
║                                             ▼                           ║
║                                    ┌─────────────────┐                  ║
║                                    │ M5 itops-ansible│                  ║
║                                    │ 203.x.x.x:8080 │                  ║
║                                    │ Ansible AWX     │                  ║
║                                    │ VULN: job output│                  ║
║                                    └────────┬────────┘                  ║
╚═════════════════════════════════════════════╪════════════════════════════╝
                                              │  SSH key + vault pass
                                              ▼
                          ╔══════════════════════════════════════════╗
                          ║  RNG-DEV-01 · Code Forge / CI-CD Zone   ║
                          ║  11.x.x.x/24 (v-DMZ)                    ║
                          ║  dev-jump.prabalurja.in (11.x.x.x)      ║
                          ║  devops@dev-jump.prabalurja.in          ║
                          ╚══════════════════════════════════════════╝

Honeytrap Ports (per machine):
  M1: 8080, 8443, 9389, 9636, 9100
  M2: 8929, 7990, 3001, 9000, 8888
  M3: 8500, 8201, 8202, 8443, 8022
  M4: 3000, 9091, 9093, 9100, 8081
  M5: 9080, 8111, 4440, 8000, 9001
```
