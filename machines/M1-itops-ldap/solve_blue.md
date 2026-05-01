# solve_blue.md — M1 · itops-ldap
## Blue Team Solution Writeup
**Range:** RNG-IT-02 · Internal Operations Zone
**Machine:** M1 — OpenLDAP Directory Service
**Vulnerability:** Anonymous Bind + Plaintext Credential Attribute
**Kill Chain Stage:** Detection → Containment → Eradication → Recovery

---

## Detection

### 1 — LDAP Access Log (syslog)
```bash
grep "slapd" /var/log/syslog | grep -E "BIND|SEARCH|conn=" | tail -50
```

**Indicator — Anonymous bind from external IP:**
```
slapd[XXXX]: conn=1001 op=0 BIND dn="" method=128
slapd[XXXX]: conn=1001 op=0 RESULT tag=97 err=0 text=
slapd[XXXX]: conn=1001 op=1 SRCH base="dc=prabalurja,dc=in" scope=2 filter="(objectClass=*)"
```

**Indicator — Full subtree search from svc-deploy:**
```
slapd[XXXX]: conn=1002 BIND dn="cn=svc-deploy,ou=service,dc=prabalurja,dc=in"
slapd[XXXX]: conn=1002 SRCH base="ou=service,dc=prabalurja,dc=in" scope=2
```
A SEARCH with `scope=2` (subtree) from a non-admin bind DN is enumeration.

### 2 — Identify userPassword-plain Attribute
```bash
ldapsearch -Y EXTERNAL -H ldapi:/// \
  -b "ou=service,dc=prabalurja,dc=in" \
  "(userPassword-plain=*)" dn userPassword-plain
```
Any account with this attribute populated is a critical misconfiguration finding.

---

## Containment
```bash
# 1. Remove plaintext password attribute from svc-cicd
ldapmodify -Y EXTERNAL -H ldapi:/// << 'EOF'
dn: cn=svc-cicd,ou=service,dc=prabalurja,dc=in
changetype: modify
delete: userPassword-plain
EOF

# 2. Disable anonymous bind
cat > /tmp/disable-anon.ldif << 'LDIF'
dn: cn=config
changetype: modify
replace: olcAllows
olcAllows: bind_v2
LDIF
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/disable-anon.ldif

# 3. Restrict ACL — svc-deploy cannot read service OU password attributes
cat > /tmp/fix-acl.ldif << 'LDIF'
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to attrs=userPassword,userPassword-plain by self write by dn.base="cn=admin,dc=prabalurja,dc=in" write by anonymous auth by * none
olcAccess: {1}to * by dn.base="cn=admin,dc=prabalurja,dc=in" write by users read by anonymous auth by * none
LDIF
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/fix-acl.ldif

# 4. Block attacker IP
ufw deny from <ATTACKER_IP> to any port 389 comment "M1 LDAP recon"
```

## Eradication
- Rotate `svc-cicd` credential immediately — notify M2 (Gitea) team.
- Audit all LDAP accounts for custom plaintext-storing attributes.
- Implement strict ACL: only `cn=admin` can read password-related attributes.
- Enforce authenticated-only LDAP — no anonymous binds in production.
- Enable LDAP over TLS (STARTTLS / LDAPS on 636) to prevent passive interception.

## IOCs
| Type | Value |
|---|---|
| Attacker Source IP | `203.0.2.X` |
| Attack Vector | LDAP authenticated bind + full subtree SEARCH |
| Compromised Attribute | `userPassword-plain` on `cn=svc-cicd` |
| Compromised Credential | `svc-cicd:CICD@Deploy!2024` |
| Log Signature | `SRCH base="ou=service" scope=2` from non-admin DN |
