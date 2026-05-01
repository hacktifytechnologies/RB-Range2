# Incident Notification Report (INREP)
**Classification:** RESTRICTED — Internal Use Only
**Report ID:** INREP-IT02-M01
**Version:** 1.0
**Date:** [Date of Detection]
**Time:** [Time of Detection — IST]

---

## 1. Current Situation
The PUL LDAP directory service (`203.x.x.x:389`) permits anonymous binds and has an ACL misconfiguration allowing authenticated service accounts to read all attributes on other directory entries. An adversary using the `svc-deploy` credential pivoted from RNG-IT-01 M5 performed a full subtree SEARCH across `ou=service`, retrieving the custom attribute `userPassword-plain: CICD@Deploy!2024` from the `svc-cicd` account. This credential grants access to the internal Gitea CI/CD repository (M2).

**Threat Level:** `HIGH`

**Areas of Concern:**
- Anonymous bind enabled — directory structure visible to any unauthenticated host on v-Public.
- `userPassword-plain` attribute stores plaintext credential — violates PUL credential storage policy.
- LDAP connections are unencrypted — passive interception possible on the subnet.
- `svc-cicd` credential now compromised — pivot to M2 imminent.

---

## 2. Threat Intelligence
**IOCs:**

| Type | Value |
|---|---|
| Attacker Source IP | `203.0.2.X` (pivoting from RNG-IT-01) |
| Bind DN Used | `cn=svc-deploy,ou=service,dc=prabalurja,dc=in` |
| Targeted Attribute | `userPassword-plain` on `cn=svc-cicd` |
| Exfiltrated Credential | `svc-cicd:CICD@Deploy!2024` |

**Log entry:**
```
slapd: conn=1002 BIND dn="cn=svc-deploy,ou=service,dc=prabalurja,dc=in" ...
slapd: conn=1002 SRCH base="ou=service,dc=prabalurja,dc=in" scope=2 filter="(objectClass=*)"
```

---

## 3. Vulnerability Identification
- **Vuln 1:** Anonymous bind enabled (`olcAllows: bind_anon`).
- **Vuln 2:** ACL allows any authenticated user to read all attributes including custom password attributes.
- **Vuln 3:** `userPassword-plain` non-standard attribute storing credential in cleartext.
- **CWE:** CWE-522 (Insufficiently Protected Credentials)

---

## 4. Security Operations
- Disable anonymous bind immediately.
- Restrict ACLs: password attributes readable only by `cn=admin` and `self`.
- Delete `userPassword-plain` attribute from all accounts.
- Enable LDAPS (port 636, TLS).
- Rotate `svc-cicd` credential across all consuming systems.

---

## 5. POC
> **[Attach: ldapsearch command output showing `userPassword-plain` attribute visible]**
> **[Attach: syslog grep confirming full subtree search from svc-deploy]**

---

## 6. Submission
**Prepared By:** Blue Team — [Team Name]
**Incident Reference:** GRIDFALL-RNG-IT02-M01
