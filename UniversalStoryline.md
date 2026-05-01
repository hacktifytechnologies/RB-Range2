# OPERATION GRIDFALL - Universal Storyline & Exercise Narrative
## Classification: RESTRICTED - Exercise Staff, White Team, and Range Designers Only
## Document Version: 1.0 | Last Updated: November 2024

---

# PART I - THE THREAT ACTOR: KAAL CHAKRA

## 1.1 Group Overview

**Designation:** KAAL CHAKRA
**Internal Aliases:** Trident-7, NEXUS-Shadow (internal PUL SOC designation)
**Nation-State Nexus:** Composite of two real-world groups:
- Primary TTP inspiration: APT36 / Transparent Tribe (espionage, credential phishing, CII targeting)
- Secondary TTP inspiration: RedEcho / TAG-38 (Indian power grid targeting, OT-adjacent intrusions)

**Classification:** State-sponsored APT targeting Indian Critical Information Infrastructure (CII)
**Primary Focus:** Indian power utilities, grid management organisations, and their IT/OT suppliers
**Operational Tempo:** Long-dwell, low-and-slow - priority on persistence and intelligence collection over disruption
**CERT-In Classification:** APT-IN-CII-04 (fictionalised designation)

---

## 1.2 Strategic Objectives

KAAL CHAKRA's operations against the Indian power sector are driven by three strategic imperatives:

**Objective 1 - Persistent Pre-Positioning**
Establish persistent access to Indian power utility IT networks before any geopolitical escalation. The goal is not immediate disruption but maintaining the capability to disrupt on demand - the "loaded gun" posture seen in historical RedEcho campaigns against the Mumbai grid.

**Objective 2 - OT Network Mapping**
Bridge from IT networks into operational technology (OT) environments - SCADA systems, Energy Management Systems (EMS), substation automation, and protection relays. The group collects network topology, device inventories, and protocol details (IEC 61850, DNP3, Modbus) for future targeting.

**Objective 3 - Intelligence Collection**
Exfiltrate strategically sensitive documents: grid load forecasts, outage schedules, substation interconnection maps, and employee data for spear-phishing and potential physical access facilitation.

---

## 1.3 Tactics, Techniques, and Procedures (TTPs)

**Initial Access**
KAAL CHAKRA typically gains initial access via spear-phishing with weaponised attachments (macro-enabled XLSX, PDF with embedded exploit) or watering hole attacks on industry forums and vendor portals. In the GRIDFALL scenario, initial access was gained via a zero-day web application vulnerability on PUL's external NEXUS portal - a HTTP Host Header injection in the password reset flow (modelled in RNG-IT-01 M1).

**Credential Access**
The group aggressively targets credential material across the estate - LDAP directories, source code repositories, secrets management platforms, configuration management databases, and automation job outputs. They specifically exploit the pattern of over-privileged service accounts carrying credentials across system boundaries.

**Lateral Movement**
KAAL CHAKRA chains through Linux/Windows IT infrastructure before pivoting to OT-adjacent networks. They exploit trust relationships between IT zones - LDAP binds, SSH key chains, Ansible automation, Kerberos delegation - rather than exploiting individual software vulnerabilities.

**Persistence**
Backdoored cron jobs, modified SSH `authorized_keys`, rogue Ansible playbooks that re-establish access post-remediation, and implanted LDAP service accounts in legitimate OUs.

**Command and Control**
Encrypted C2 over HTTPS using legitimate-looking domains registered to Indian hosting providers. Also uses DNS-over-HTTPS for fallback C2. In the GRIDFALL scenario, C2 details are abstracted - participants focus on the lateral movement chain rather than malware analysis.

**Impact (Assessed Capability)**
The group has demonstrated capability to reach OT-adjacent systems in prior campaigns. Assessed capable of: disrupting SCADA human-machine interfaces (HMIs), interfering with protection relay coordination, and causing targeted substation outages during high-demand periods.

---

## 1.4 Known Campaign History (Fictionalised)

| Campaign | Year | Target | Method | Outcome |
|---|---|---|---|---|
| Operation VOLTAGE | 2021 | Northern Regional Load Despatch Centre | Spear-phishing → VPN cred theft | 6-month dwell; grid maps exfiltrated |
| Operation DARKLINE | 2022 | Three major Indian power utilities | Watering hole on vendor portal | OT-adjacent access achieved; detected before impact |
| Operation GRIDFALL (current) | 2024 | Prabal Urja Limited | Web app exploit → IT zone chain | Active intrusion - incident under response |

---

## 1.5 Key Personnel (Fictionalised - KAAL CHAKRA Operators)

These are exercise artefact characters - their names may appear in log entries, email headers, and attribution artefacts planted across the range.

**"Agni-1"** - Lead operator on GRIDFALL. Responsible for initial access and early-stage LDAP/Git enumeration. Leaves characteristic artefacts: uses `ldapsearch` with `scope=2`, prefers Python-based tooling over compiled malware.

**"Indra-3"** - Vault and secrets specialist. Exploits misconfigured secrets management platforms. Known for methodical enumeration of Vault KV stores.

**"Rudra-7"** - CI/CD and automation specialist. Targets Ansible/Jenkins/Gitea environments. History of extracting credentials from automation job logs.

---

# PART II - THE TARGET: PRABAL URJA LIMITED (PUL)

## 2.1 Organisation Overview

**Full Name:** Prabal Urja Limited
**Short Form:** PUL
**Type:** Central Public Sector Undertaking (CPSU) - under the Ministry of Power, Government of India (fictionalised)
**Headquarters:** New Delhi, India
**Founded:** 1971 (fictionalised)
**Employees:** ~14,000 (direct) + ~60,000 contracted
**CERT-In Registration:** CII Sector - Power & Energy

**Mission:** Transmission, distribution, and management of electrical power across Northern and Eastern India. PUL operates approximately 48,000 circuit kilometres of transmission lines, 312 substations, and manages grid balancing for four states.

**Annual Revenue:** ₹38,200 crore (FY 2023–24, fictionalised)

---

## 2.2 Organisational Structure (Relevant Departments)

```
Board of Directors
└── Chairman & Managing Director (CMD)
    ├── Director - Technical (grid operations, substation, protection)
    ├── Director - Finance
    ├── Director - HR & Administration
    └── Director - IT & Digital (CISO reports here)
        ├── CISO - Rajiv Menon (see Characters)
        ├── IT Infrastructure Division (Arun Sharma)
        ├── IT Operations Division (Priya Nair)
        ├── DevOps & Automation Team
        ├── Security Operations Centre (SOC)
        └── OT/SCADA Integration Team
```

---

## 2.3 Technology Environment (NEXUS-IT Platform)

PUL operates the **NEXUS-IT** platform - an internally branded converged IT infrastructure that was partially modernised in 2022–2024 as part of a digital transformation programme. The modernisation introduced DevOps tooling, container orchestration, and secrets management, but was implemented with significant security gaps due to delivery pressure.

**Network Zones:**
| Zone | CIDR | Description |
|---|---|---|
| v-Public | 203.0.0.0/8 | Internet-facing and internal IT systems |
| v-DMZ | 11.0.0.0/8 | Development, CI/CD, and staging systems |
| v-Private | 193.0.0.0/8 | OT-adjacent, SCADA, substation interfaces |

**Key IT Systems (Exercise Ranges):**
| Range | Zone | Purpose |
|---|---|---|
| RNG-IT-01 | v-Public 203.x.x.x/24 | Corporate Gateway - web portal, mail, SSO, SNMP, cache |
| RNG-IT-02 | v-Public 203.x.x.x/24 | Internal Ops - LDAP, Git, Vault, Monitoring, Ansible |
| RNG-DEV-01 | v-DMZ 11.x.x.x/24 | Code Forge - CI/CD, artifact registry, dev environments |
| RNG-AD-01 | v-Private 193.x.x.x/24 | Windows AD forest - corp.prabalurja.in |
| RNG-OT-01 | v-Private 193.x.x.x/24 | OT Gateway - historian, DMZ firewall, SCADA proxy |
| RNG-OT-02 | v-Private 193.x.x.x/24 | SCADA Zone - HMI, EMS, protection relay interface |

---

## 2.4 Named Characters

These characters appear across exercise artefacts - email headers, log entries, LDAP attributes, documents, and Slack-like message snippets.

---

### Arun Sharma - IT Infrastructure Lead
**Employee ID:** EMP-001
**Department:** IT Infrastructure Division
**Email:** arun.sharma@prabalurja.in
**Phone:** +91-11-2468-3301
**LDAP DN:** cn=Arun Sharma,ou=users,dc=prabalurja,dc=in

**Background:** 14-year PUL veteran. Led the NEXUS-IT modernisation programme. Under significant delivery pressure during the 2022–2024 transformation - many of the security misconfigurations in RNG-IT-02 (Vault dev mode, anonymous LDAP bind, verbose Ansible logging) were introduced by his team during rapid deployment. Not malicious - simply under-resourced and moving too fast. Well-meaning but technically stretched.

**Exercise Role:** Appears in setup scripts as the admin who created misconfigured configs. His name appears in Gitea commit author metadata (`arun.sharma@prabalurja.in`), LDAP admin DN, and as the person who approved the `svc-cicd` service account without proper credential hygiene review.

**Key Quote (planted in repo README):** "We'll clean up the vault creds after the release - just need to get this over the line first."

---

### Priya Nair - IT Operations Manager
**Employee ID:** EMP-002
**Department:** IT Operations Division
**Email:** priya.nair@prabalurja.in
**LDAP DN:** cn=Priya Nair,ou=users,dc=prabalurja,dc=in

**Background:** 8 years at PUL. Manages day-to-day IT operations, monitoring, and the Ansible automation team. Responsible for the Prometheus monitoring stack and AWX deployment. Professional and process-oriented, but her team's AWX verbose logging policy was never formally reviewed by security.

**Exercise Role:** Her name appears in AWX job launch metadata (`launched_by: priya.nair` for some historical jobs), the monitoring portal dashboard, and as the approver of the Ansible vault password file policy.

---

### Rajiv Menon - CISO / SOC Lead
**Employee ID:** EMP-003
**Department:** Security Operations Centre
**Email:** rajiv.menon@prabalurja.in
**LDAP DN:** cn=Rajiv Menon,ou=users,dc=prabalurja,dc=in

**Background:** Former CERT-In analyst, joined PUL 3 years ago to build the SOC. Has been pushing for LDAP ACL hardening and Vault production mode migration for over a year - both blocked by IT Infrastructure citing operational disruption risks. He is the primary Blue Team persona - the incident response actions described in solve_blue.md represent his SOC's playbook.

**Exercise Role:** Blue Team narrative anchor. INREP/SITREP reports are addressed to his office. Detection signatures in solve_blue.md reflect his SOC's detection capability. His email appears in escalation paths.

---

### Deepa Iyer - Grid Operations Engineer
**Employee ID:** EMP-004
**Department:** Grid Operations
**Email:** deepa.iyer@prabalurja.in
**LDAP DN:** cn=Deepa Iyer,ou=users,dc=prabalurja,dc=in

**Background:** Based in the Northern Regional Grid Control Centre. Her credentials exist in the LDAP directory as a non-IT account - she is a canary. If her account is accessed or enumerated during the exercise, it indicates the adversary has reached beyond the IT service accounts into operational staff data.

**Exercise Role:** Canary account. Her LDAP entry can be monitored for access. Appears in grid metrics data on the Prometheus dashboard (grid operations metrics reference her substation zone).

---

### Vikram Sethi - DevOps Engineer (fictionalised attacker persona alias)
**Note:** Not a real PUL employee - this is the alias used by KAAL CHAKRA operator Agni-1 when they authenticated to Gitea as `svc-cicd` from an unexpected IP. Investigators may find this alias in Gitea access logs attributed to the anomalous login session.

---

## 2.5 The Incident Timeline (OPERATION GRIDFALL)

```
Day 0   - Initial Access
         KAAL CHAKRA exploits HTTP Host Header injection in PUL NEXUS portal
         (RNG-IT-01 M1 - itgw-webportal). Password reset link hijacked.
         Adversary gains access to mail relay.

Day 1   - Credential Pivoting (RNG-IT-01)
         Mail relay → SSO JWT forgery → SNMP enumeration → Redis cache access.
         cn=svc-deploy:D3pl0y@PUL2024 extracted from Redis key.

Day 2   - IT-OPS Zone Entry (RNG-IT-02 begins)
         LDAP anonymous bind + svc-deploy enumeration → svc-cicd credential.
         Gitea pul-infra-config repo cloned → git history → Vault AppRole creds.

Day 3   - Secrets Platform Compromise
         Vault AppRole login. Root token extracted from systemd journal.
         secret/pul/ad read → svc-monitor:M0n!tor@PUL24 + pivot host.

Day 4   - Monitoring and CI/CD Breach
         Prometheus /metrics scraped unauthenticated → devops-admin credential.
         AWX portal accessed → deploy-dev-infra job output →
         Ansible vault password + SSH key extracted.

Day 5   - DEV Zone Pivot
         SSH to dev-jump.prabalurja.in (11.x.x.x) using extracted key.
         RNG-DEV-01 entry achieved - CI/CD zone under adversary control.

Day 6+  - (Exercise continues in RNG-DEV-01 and beyond)
         Adversary moves toward AD zone and OT-adjacent infrastructure.
```

---

# PART III - EXERCISE DESIGN CONTEXT

## 3.1 Exercise Objectives

**Red Team:** Demonstrate the complete credential chain from initial web access through IT operations infrastructure to the CI/CD and development zone. Each step must be earned through active exploitation - no brute force, no excluded techniques.

**Blue Team:** Detect the intrusion at each stage, contain the compromised credential, remediate the misconfiguration, and produce structured incident reports (INREP/SITREP) demonstrating depth of understanding.

**Purple Team Outcome:** Each machine produces a shared learning artefact - the paired solve_red.md + solve_blue.md - representing the full detection-exploitation picture for that vulnerability class.

## 3.2 Excluded Techniques (Global)
SQL Injection, IDOR on web applications, SSRF, OS Command Injection, File Upload Webshell, LFI, Credential Spraying, Shadow Credentials, DCSync, DLL Hijacking, Token Impersonation, LSASS Dumping.

## 3.3 Scoring Philosophy
No flags. Question-based assessment (3 MCQ + 2 FIB per machine). Answers are only achievable by actually exploiting the vulnerability - they cannot be guessed or found without doing the work.

---

*OPERATION GRIDFALL Universal Storyline | Classification: RESTRICTED | Version 1.0*
*Maintained by: Hacktify Cybersecurity | © 2026 Exercise Design - Learning Purposes Only*
