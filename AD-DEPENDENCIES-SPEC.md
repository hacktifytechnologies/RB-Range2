# Active Directory Zone Dependencies - OPERATION GRIDFALL

---

# OVERVIEW

This document is the handshake specification between the **RNG-IT-02 (Internal Operations Zone)** range and the **RNG-AD-01 (Windows Active Directory Zone)** range.

It is split into two sections:

- **Section A - What You Must Build:** Everything the AD zone teammate must implement so that the ranges connect correctly and challenge artefacts are consistent.
- **Section B - What You Must Provide Back to Us:** The specific values, credentials, and artefacts the AD zone must have so we can plant them correctly in our machines.

---

# SECTION A - WHAT THE AD ZONE MUST BUILD

## A.1 Forest and Domain Configuration

| Parameter | Required Value |
|---|---|
| Forest Root Domain | `corp.prabalurja.in` |
| NetBIOS Name | `CORPPUL` |
| Forest Functional Level | Windows Server 2019 (minimum) |
| Domain Functional Level | Windows Server 2019 (minimum) |
| Primary DC Hostname | `DC01-CORPUL` |
| Primary DC IP | `193.x.x.x` (v-Private zone) |
| Secondary DC Hostname | `DC02-CORPUL` (optional, for realism) |
| Secondary DC IP | `193.x.x.x` |
| DNS Zone | `corp.prabalurja.in` must resolve within the exercise network |
| AD Recycle Bin | Enabled (required for realism of deleted object challenges) |

---

## A.2 Organisational Unit (OU) Structure

The following OU structure must be created exactly as specified. RNG-IT-02 Vault secrets and LDAP sync artefacts reference these paths - mismatched OUs will break the credential chain.

```
DC=corp,DC=prabalurja,DC=in
│
├── OU=PUL-Users
│   ├── OU=IT-Infrastructure
│   ├── OU=IT-Operations
│   ├── OU=Security-Operations
│   ├── OU=Grid-Operations
│   └── OU=Finance
│
├── OU=PUL-Service-Accounts
│   ├── OU=IT-Automation       ← critical - all svc-* accounts live here
│   ├── OU=Monitoring
│   └── OU=Backup
│
├── OU=PUL-Computers
│   ├── OU=IT-Servers
│   ├── OU=Workstations
│   └── OU=Jump-Hosts           ← dev-jump.prabalurja.in managed here
│
├── OU=PUL-Groups
│   ├── OU=Security-Groups
│   └── OU=Distribution-Lists
│
└── OU=PUL-Admin               ← privileged admin accounts only
```

---

## A.3 User Accounts - Employee Accounts

The following employee accounts must be created and match the Linux LDAP entries in RNG-IT-02 M1. This is required for realistic cross-directory consistency (the exercise narrative states PUL uses AD-LDAP sync).

| Display Name | UPN | sAMAccountName | OU | Notes |
|---|---|---|---|---|
| Arun Sharma | arun.sharma@corp.prabalurja.in | asharma | OU=IT-Infrastructure,OU=PUL-Users | IT Infrastructure Lead |
| Priya Nair | priya.nair@corp.prabalurja.in | pnair | OU=IT-Operations,OU=PUL-Users | IT Operations Manager |
| Rajiv Menon | rajiv.menon@corp.prabalurja.in | rmenon | OU=Security-Operations,OU=PUL-Users | CISO / SOC Lead |
| Deepa Iyer | deepa.iyer@corp.prabalurja.in | diyer | OU=Grid-Operations,OU=PUL-Users | Grid Ops - canary account |

**Password Policy for Employee Accounts:** Minimum 12 characters, complexity enabled, 90-day expiry. Individual account passwords are at your discretion - just provide us the initial passwords for scenario documentation.

**Account Flags:** All accounts must have `Password Never Expires = False` and `Account is Disabled = False`.

---

## A.4 Service Accounts - Critical (Must Match RNG-IT-02 Exactly)

These service accounts are directly referenced in RNG-IT-02 challenge artefacts (Vault secrets, LDAP entries, solve guides). They **must** be created with the exact sAMAccountName and DN format specified. Passwords must match exactly.

### A.4.1 svc-monitor (PRIMARY - Pivot Credential)

This is the most critical account. It is planted in Vault `secret/pul/ad` on RNG-IT-02 M3. When participants read this Vault secret, they get this credential and use it to access the AD zone.

| Field | Value |
|---|---|
| Display Name | IT Operations Monitoring Agent |
| sAMAccountName | `svc-monitor` |
| UPN | `svc-monitor@corp.prabalurja.in` |
| DN | `CN=svc-monitor,CN=Users,DC=corp,DC=prabalurja,DC=in` |
| **Password** | `M0n!tor@PUL24` |
| OU | `OU=Monitoring,OU=PUL-Service-Accounts` |
| Description | IT Operations monitoring service account - read-only access to AD |
| Password Never Expires | True |
| Account Disabled | False |

**AD Permissions for svc-monitor:**
- Read access to all objects in `OU=PUL-Users` and `OU=PUL-Service-Accounts`
- Read access to `OU=PUL-Computers`
- **No** write permissions anywhere
- **No** group membership in privileged groups (Domain Admins, Account Operators, etc.)
- Member of: `PUL-Monitoring-Readers` (custom group - see A.5)

**What the RNG-AD-01 challenge must expose via this account:**
The `svc-monitor` credential is the entry point into the AD zone. After authenticating as `svc-monitor`, participants should be able to enumerate the domain to discover:
- The existence of more privileged accounts (especially `svc-ad-sync` or a misconfigured account per your AD challenge design)
- GPO paths and SYSVOL content that leads to the next stage of your challenge
- Or whatever your first AD machine challenge is - coordinate with us on what `svc-monitor` can reach

---

### A.4.2 svc-cicd (Reference Account)

This account exists in RNG-IT-02 M1 LDAP. Its AD equivalent must exist for consistency with the exercise narrative (LDAP-AD sync story).

| Field | Value |
|---|---|
| sAMAccountName | `svc-cicd` |
| UPN | `svc-cicd@corp.prabalurja.in` |
| DN | `CN=svc-cicd,CN=Users,DC=corp,DC=prabalurja,DC=in` |
| **Password** | `CICD@Deploy!2024` |
| OU | `OU=IT-Automation,OU=PUL-Service-Accounts` |
| Description | CI/CD pipeline service account |
| Password Never Expires | True |

**AD Permissions for svc-cicd:**
- Read-only access to `OU=PUL-Computers` only
- No privileged group membership

---

### A.4.3 svc-deploy (Reference Account)

Entry-point account pivoted from RNG-IT-01. AD equivalent for narrative consistency.

| Field | Value |
|---|---|
| sAMAccountName | `svc-deploy` |
| UPN | `svc-deploy@corp.prabalurja.in` |
| DN | `CN=svc-deploy,CN=Users,DC=corp,DC=prabalurja,DC=in` |
| **Password** | `D3pl0y@PUL2024` |
| OU | `OU=IT-Automation,OU=PUL-Service-Accounts` |
| Description | Deployment automation service account |
| Password Never Expires | True |

---

### A.4.4 svc-backup (Reference Account)

Exists in Linux LDAP for realism. AD equivalent.

| Field | Value |
|---|---|
| sAMAccountName | `svc-backup` |
| UPN | `svc-backup@corp.prabalurja.in` |
| Password | `Bkp@Secure2024!` |
| OU | `OU=Backup,OU=PUL-Service-Accounts` |
| Description | Backup automation service account |

---

## A.5 Security Groups

The following groups must be created. They are referenced in Vault secrets, LDAP groups, and monitoring artefacts planted in RNG-IT-02.

| Group Name | Type | Scope | Members | Purpose |
|---|---|---|---|---|
| PUL-IT-Admins | Security | Global | asharma, svc-deploy | IT Administrator group |
| PUL-DevOps-Team | Security | Global | svc-cicd, svc-deploy | DevOps automation team |
| PUL-SOC-Analysts | Security | Global | rmenon, svc-monitor | SOC access group |
| PUL-Monitoring-Readers | Security | Global | svc-monitor | Read access for monitoring agents |
| PUL-Grid-Operations | Security | Global | diyer | Grid operations staff |

---

## A.6 Group Policy Objects (GPOs)

Create the following GPOs. These may be leveraged as challenge artefacts in your AD zone machines or referenced from RNG-IT-02 artefacts.

| GPO Name | Linked OU | Purpose | Note |
|---|---|---|---|
| PUL-Workstation-Security | OU=Workstations | Standard workstation hardening | General |
| PUL-Server-Baseline | OU=IT-Servers | Server hardening baseline | General |
| PUL-ServiceAccount-Policy | OU=PUL-Service-Accounts | Restrict service account logon rights | logon locally=deny, logon as service=allow |
| PUL-Password-Policy | Domain root | Domain password policy | See A.3 password policy |
| PUL-Audit-Policy | Domain root | Enable advanced audit logging | Logon events, account management, DS access |

**Important:** The `PUL-Audit-Policy` GPO must enable `Audit Directory Service Access` - this is what participants use to detect LDAP enumeration from `svc-monitor` in your zone.

---

## A.7 Jump Host - dev-jump.prabalurja.in

This is the machine that RNG-IT-02 M5 pivots to. It must be provisioned and accessible.

| Parameter | Value |
|---|---|
| Hostname | `dev-jump` |
| FQDN | `dev-jump.prabalurja.in` |
| IP Address | `11.x.x.x` (v-DMZ zone) |
| OS | Ubuntu 22.04 LTS |
| AD Join | Not domain-joined - standalone Linux |
| DNS Record | A record in your DNS: `dev-jump.prabalurja.in` → `11.x.x.x` |
| SSH Port | `22` |
| SSH User | `devops` (local account - NOT AD account) |

**SSH Key Setup:**
The `devops` user on this host must have a specific SSH public key in `/home/devops/.ssh/authorized_keys`. This is the key whose private counterpart is planted in RNG-IT-02 M5 AWX job output.

**Action Required - Key Exchange:**
1. Generate a new Ed25519 SSH key pair for this exercise.
2. Send us the **public key** → we will embed the matching **private key** in the M5 AWX job output.
3. Place the **public key** in `/home/devops/.ssh/authorized_keys` on `dev-jump.prabalurja.in`.

```bash
# Generate on your side (or send us the public key and we generate the pair):
ssh-keygen -t ed25519 -f pul-gridfall-devjump -C "devops@dev-jump.prabalurja.in GridFall-2024-Ed25519" -N ""
# Send us the content of: pul-gridfall-devjump.pub
# Keep: pul-gridfall-devjump (private - we need this to embed in M5)
```

**What happens when participants SSH to dev-jump:**
This is the entry point to RNG-DEV-01. The `devops` account on `dev-jump` should have limited local access but be able to reach internal DEV zone resources (`11.x.x.x/24`). Coordinate with the RNG-DEV-01 team on what `devops` can do post-pivot.

---

## A.8 DNS Records Required

The following DNS A records must be created in your DNS infrastructure (which should be authoritative for `corp.prabalurja.in` and `prabalurja.in` within the exercise network):

| Hostname | Record Type | Value |
|---|---|---|
| `dc01-corpul.corp.prabalurja.in` | A | `193.x.x.x` |
| `dc02-corpul.corp.prabalurja.in` | A | `193.x.x.x` |
| `dev-jump.prabalurja.in` | A | `11.x.x.x` |
| `ldap.prabalurja.in` | A | `203.x.x.x` |
| `git.prabalurja.in` | A | `203.x.x.x` |
| `vault.prabalurja.in` | A | `203.x.x.x` |
| `monitor.prabalurja.in` | A | `203.x.x.x` |
| `ansible.prabalurja.in` | A | `203.x.x.x` |
| `ad.corp.prabalurja.in` | CNAME | `dc01-corpul.corp.prabalurja.in` |

---

## A.9 LDAP/AD Integration Notes

RNG-IT-02 M1 (Linux OpenLDAP) is the exercise's representation of the Linux-side directory. The AD zone is the Windows-side directory. In the exercise narrative, they are synchronised via the `CN=AADSync,CN=Users,DC=corp,DC=prabalurja,DC=in` account (which appears in the M1 AD Connector honeytrap UI).

**You do not need to implement real LDAP-AD sync.** The accounts just need to exist in both with matching credentials as documented above. The sync narrative is flavour - it explains why the same accounts appear in both directories without requiring actual DirSync infrastructure.

---

# SECTION B - WHAT YOU MUST PROVIDE BACK TO US

The following values are needed by the RNG-IT-02 team (and RNG-IT-01 team) to correctly plant artefacts in our challenges. Please provide these before range finalisation.

---

## B.1 SSH Public Key for dev-jump.prabalurja.in

**What we need:** The Ed25519 public key that you install in `/home/devops/.ssh/authorized_keys` on `dev-jump.prabalurja.in`.

**Format:**
```
ssh-ed25519 AAAA[base64-key-material] devops@dev-jump.prabalurja.in GridFall-2024-Ed25519
```

**Where we use it:** The matching private key is embedded in:
- RNG-IT-02 M5 AWX job output (JOB-20241115-018 `deploy-dev-infra` task output)
- RNG-IT-02 M5 file browser (`/group_vars/all/vault.yml` decrypted preview)

**Deadline:** Must be provided before final snapshot of M5.

---

## B.2 Confirmed DC IP and DNS Resolution

**What we need:** Confirmation that `193.x.x.x` is the DC01 IP **and** that DNS resolution for `corp.prabalurja.in` works from within `203.x.x.x/24` (our zone).

**Why:** Vault `secret/pul/ad` on M3 contains `dc_host: 203.x.x.x` as a placeholder. If your DC is at a different IP or DNS doesn't resolve cross-zone, we need to update this value before snapshot.

**Provide:** Confirmed DC01 IP, confirmed DNS server IP reachable from `203.x.x.x/24`.

---

## B.3 First AD Machine Entry Point Details

**What we need:** After participants pivot via `svc-monitor` credentials to your AD zone, what is the first machine/service they interact with?

We need:
- IP address of the first AD zone challenge target
- Port / service
- What `svc-monitor` can do there (e.g., LDAP bind to DC, SMB read to SYSVOL, WinRM login, etc.)

**Why:** RNG-IT-02 M3 Vault `secret/pul/ad` currently contains `pivot_note: "Prometheus metrics portal: 203.x.x.x:9090"` (pointing to M4 within our own range). After participants finish M4, they will use `svc-monitor` on the AD side. We need to know where to direct them from M3's Vault secret and from our assessment questions.

**Provide:** `pivot_note` value we should plant in `secret/pul/ad` pointing to your first AD target. Format: `"AD Domain Controller: 193.x.x.x:389"` or similar.

---

## B.4 svc-monitor Permitted Actions in AD Zone

**What we need:** Exact list of what `svc-monitor` (authenticating with `M0n!tor@PUL24`) can do in your zone that moves the kill chain forward.

Examples of what we're looking for:
- "svc-monitor can do anonymous LDAP bind to DC01 and enumerate OU=PUL-Users"
- "svc-monitor can read SYSVOL and find a GPP credentials file"
- "svc-monitor can authenticate to a web app on 193.x.x.x that leads to the next challenge"

**Why:** We need to confirm the pivot out of M3 (Vault secret read) actually reaches your challenge. If `svc-monitor` can't do anything in your zone, the credential chain breaks.

---

## B.5 AD Zone Assessment Questions for M3 Reference

**What we need:** Your first 1–2 AD zone assessment questions, so we can confirm our M3 solve guide correctly leads to the answers.

Our M3 solve guide currently ends with:
> "Pivot credential for AD zone: svc-monitor:M0n!tor@PUL24 → corp.prabalurja.in"

We want to make sure the solve path from M3 → AD Zone M1 is unambiguous for participants.

---

## B.6 Anything Planted in AD That References RNG-IT-02 Services

**What we need:** If your AD zone machines reference any RNG-IT-02 IPs, hostnames, or credentials (e.g., a discovered network map showing 203.0.2.x hosts, or a script that talks to our LDAP), please tell us so we can make sure those references are consistent.

---

# SECTION C - COORDINATION CHECKLIST

Use this checklist to confirm readiness before exercise execution:

| # | Item | Owner | Status |
|---|---|---|---|
| 1 | AD forest `corp.prabalurja.in` deployed at `193.x.x.x` | AD Team | ☐ |
| 2 | OU structure created per Section A.2 | AD Team | ☐ |
| 3 | All employee accounts created per A.3 | AD Team | ☐ |
| 4 | `svc-monitor` created with password `M0n!tor@PUL24` exactly | AD Team | ☐ |
| 5 | `svc-cicd`, `svc-deploy`, `svc-backup` created per A.4 | AD Team | ☐ |
| 6 | Security groups created per A.5 | AD Team | ☐ |
| 7 | GPOs created per A.6 | AD Team | ☐ |
| 8 | `dev-jump.prabalurja.in` at `11.x.x.x` deployed and SSH accessible | AD/DEV Team | ☐ |
| 9 | SSH key pair generated; public key on dev-jump; private key sent to IT-02 team | AD/DEV Team | ☐ |
| 10 | DNS records created per A.8 | AD Team | ☐ |
| 11 | DNS resolution for `corp.prabalurja.in` confirmed from `203.x.x.x/24` | AD Team | ☐ |
| 12 | `svc-monitor` pivot path confirmed (B.3 and B.4 answered) | AD Team | ☐ |
| 13 | `secret/pul/ad` in RNG-IT-02 M3 Vault updated with correct DC IP and pivot_note | IT-02 Team | ☐ |
| 14 | M5 AWX job output updated with real SSH private key material | IT-02 Team | ☐ |
| 15 | Cross-zone connectivity tested: `203.x.x.x` → `193.x.x.x:389` (Vault to DC) | Both Teams | ☐ |
| 16 | Cross-zone connectivity tested: `11.x.x.x:22` reachable from `203.x.x.x` | Both Teams | ☐ |

---

# SECTION D - QUICK REFERENCE CARD FOR AD TEAMMATE

> **Print this card and keep it during implementation.**

**Forest:** `corp.prabalurja.in` | **DC01 IP:** `193.x.x.x`

**Critical Password - DO NOT CHANGE:**
- `svc-monitor` → `M0n!tor@PUL24`
- `svc-cicd` → `CICD@Deploy!2024`
- `svc-deploy` → `D3pl0y@PUL2024`

**Jump Host:** `dev-jump.prabalurja.in` = `11.x.x.x` | User: `devops` | OS: Ubuntu 22.04

**What to Send Back to IT-02 Team:**
1. SSH public key for `devops@dev-jump.prabalurja.in`
2. Confirmed DC01 IP + DNS server IP
3. What `svc-monitor` can do in your zone (pivot_note text)
4. First AD zone machine IP + port

**Contact:** [IT-02 Team Lead - insert contact here]

---

*AD Dependencies Specification | OPERATION GRIDFALL | Version 1.0*
*Classification: RESTRICTED - Exercise Design Team Only*
*RNG-IT-02 Team | NEXUS-IT Purple Team Range*
