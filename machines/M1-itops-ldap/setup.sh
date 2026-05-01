#!/usr/bin/env bash
# =============================================================================
# M1 — itops-ldap | setup.sh
# Challenge: LDAP Anonymous Bind + Sensitive Attribute (userPassword-plain) Exposure
# Range: RNG-IT-02 | OPERATION GRIDFALL
# Ubuntu 22.04 LTS | No internet required — run deps.sh first.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LDAP_DOMAIN="prabalurja.in"
LDAP_BASE="dc=prabalurja,dc=in"
LDAP_ADMIN_DN="cn=admin,${LDAP_BASE}"
LDAP_ADMIN_PASS="PULAdmin@2024"
LOG_DIR="/var/log/pul-ldap"
SERVICE_NAME="slapd"

echo "============================================================"
echo "  RNG-IT-02 | M1-itops-ldap | Challenge Setup"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"

if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
command -v slapd >/dev/null 2>&1 || { echo "[!] slapd not found. Run deps.sh first." >&2; exit 1; }

mkdir -p "${LOG_DIR}"
chmod 750 "${LOG_DIR}"

# ── Reconfigure slapd ─────────────────────────────────────────────────────────
echo "[*] Reconfiguring slapd for prabalurja.in..."
dpkg-reconfigure -f noninteractive slapd 2>/dev/null || true
systemctl restart slapd
sleep 2

# ── Enable anonymous bind and logging ─────────────────────────────────────────
echo "[*] Enabling anonymous bind and LDAP access logging..."
cat > /tmp/pul-ldap-config.ldif << EOF
dn: cn=config
changetype: modify
replace: olcLogLevel
olcLogLevel: stats

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by anonymous read by self write by dn.base="${LDAP_ADMIN_DN}" write by * read
EOF

ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/pul-ldap-config.ldif 2>/dev/null || true

# ── Custom schema for userPassword-plain attribute ────────────────────────────
echo "[*] Adding custom attribute schema..."
cat > /tmp/pul-schema.ldif << 'EOF'
dn: cn=pul-custom,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: pul-custom
olcAttributeTypes: ( 1.3.6.1.4.1.99999.1.1
  NAME 'userPassword-plain'
  DESC 'PUL IT: Plaintext password cache - DEPRECATED - DO NOT USE IN PROD'
  EQUALITY caseExactMatch
  SYNTAX 1.3.6.1.4.1.1466.115.121.1.15
  SINGLE-VALUE )
olcObjectClasses: ( 1.3.6.1.4.1.99999.1.2
  NAME 'pulAccount'
  DESC 'PUL IT supplementary account attributes'
  SUP top AUXILIARY
  MAY ( userPassword-plain ) )
EOF

ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/pul-schema.ldif 2>/dev/null || true

# ── Seed LDAP directory ───────────────────────────────────────────────────────
echo "[*] Building PUL directory structure..."
LDAP_PASS_HASH=$(slappasswd -s "${LDAP_ADMIN_PASS}" 2>/dev/null)

cat > /tmp/pul-directory.ldif << EOF
# ── Organisational Units ──────────────────────────────────────────────────────
dn: ou=users,${LDAP_BASE}
objectClass: organizationalUnit
ou: users
description: PUL Employee Accounts

dn: ou=service,${LDAP_BASE}
objectClass: organizationalUnit
ou: service
description: PUL Service Accounts — IT Automation

dn: ou=groups,${LDAP_BASE}
objectClass: organizationalUnit
ou: groups
description: PUL Security Groups

# ── Service Accounts ──────────────────────────────────────────────────────────
dn: cn=svc-deploy,ou=service,${LDAP_BASE}
objectClass: inetOrgPerson
objectClass: pulAccount
cn: svc-deploy
sn: Deploy
mail: svc-deploy@prabalurja.in
userPassword: $(slappasswd -s "D3pl0y@PUL2024" 2>/dev/null)
description: Deployment automation service account - IT Infrastructure
employeeType: service

dn: cn=svc-cicd,ou=service,${LDAP_BASE}
objectClass: inetOrgPerson
objectClass: pulAccount
cn: svc-cicd
sn: CICD
mail: svc-cicd@prabalurja.in
userPassword: $(slappasswd -s "CICD@Deploy!2024" 2>/dev/null)
userPassword-plain: CICD@Deploy!2024
description: CI/CD pipeline service account - DevOps Division
employeeType: service

dn: cn=svc-monitor,ou=service,${LDAP_BASE}
objectClass: inetOrgPerson
objectClass: pulAccount
cn: svc-monitor
sn: Monitor
mail: svc-monitor@prabalurja.in
userPassword: $(slappasswd -s "M0n!tor@PUL24" 2>/dev/null)
description: Monitoring agent service account - IT Operations
employeeType: service

dn: cn=svc-backup,ou=service,${LDAP_BASE}
objectClass: inetOrgPerson
cn: svc-backup
sn: Backup
mail: svc-backup@prabalurja.in
userPassword: $(slappasswd -s "Bkp@Secure2024!" 2>/dev/null)
description: Backup automation service account - IT Operations
employeeType: service

# ── Employee Accounts ─────────────────────────────────────────────────────────
dn: cn=Arun Sharma,ou=users,${LDAP_BASE}
objectClass: inetOrgPerson
cn: Arun Sharma
sn: Sharma
givenName: Arun
mail: arun.sharma@prabalurja.in
userPassword: $(slappasswd -s "PUL@Admin!2024" 2>/dev/null)
employeeNumber: EMP-001
departmentNumber: IT-Infrastructure
title: IT Infrastructure Lead

dn: cn=Priya Nair,ou=users,${LDAP_BASE}
objectClass: inetOrgPerson
cn: Priya Nair
sn: Nair
givenName: Priya
mail: priya.nair@prabalurja.in
userPassword: $(slappasswd -s "PrN@PUL!77" 2>/dev/null)
employeeNumber: EMP-002
departmentNumber: IT-Operations
title: IT Operations Manager

dn: cn=Rajiv Menon,ou=users,${LDAP_BASE}
objectClass: inetOrgPerson
cn: Rajiv Menon
sn: Menon
givenName: Rajiv
mail: rajiv.menon@prabalurja.in
userPassword: $(slappasswd -s "SOC@Prabal!77" 2>/dev/null)
employeeNumber: EMP-003
departmentNumber: Security-Operations
title: SOC Analyst

dn: cn=Deepa Iyer,ou=users,${LDAP_BASE}
objectClass: inetOrgPerson
cn: Deepa Iyer
sn: Iyer
givenName: Deepa
mail: deepa.iyer@prabalurja.in
userPassword: $(slappasswd -s "Grid@Ops2024" 2>/dev/null)
employeeNumber: EMP-004
departmentNumber: Grid-Operations
title: Grid Operations Engineer

# ── Groups ────────────────────────────────────────────────────────────────────
dn: cn=it-admins,ou=groups,${LDAP_BASE}
objectClass: groupOfNames
cn: it-admins
member: cn=Arun Sharma,ou=users,${LDAP_BASE}
member: cn=svc-deploy,ou=service,${LDAP_BASE}
description: IT Administrators Group

dn: cn=devops-team,ou=groups,${LDAP_BASE}
objectClass: groupOfNames
cn: devops-team
member: cn=svc-cicd,ou=service,${LDAP_BASE}
member: cn=svc-deploy,ou=service,${LDAP_BASE}
description: DevOps Automation Team

dn: cn=soc-analysts,ou=groups,${LDAP_BASE}
objectClass: groupOfNames
cn: soc-analysts
member: cn=Rajiv Menon,ou=users,${LDAP_BASE}
member: cn=svc-monitor,ou=service,${LDAP_BASE}
description: Security Operations Centre Team
EOF

ldapadd -x -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PASS}" \
    -H ldap://127.0.0.1 -f /tmp/pul-directory.ldif 2>/dev/null || \
    echo "[~] Some entries may already exist — continuing."

# ── Remove temp files ─────────────────────────────────────────────────────────
rm -f /tmp/pul-ldap-config.ldif /tmp/pul-schema.ldif /tmp/pul-directory.ldif

# ── Firewall ──────────────────────────────────────────────────────────────────
if command -v ufw &>/dev/null; then
    ufw allow 389/tcp comment "LDAP M1 challenge" >/dev/null 2>&1 || true
fi

systemctl enable "${SERVICE_NAME}" --quiet
systemctl restart "${SERVICE_NAME}"
sleep 2

if systemctl is-active --quiet "${SERVICE_NAME}"; then
    echo "[+] slapd running on port 389."
else
    echo "[!] slapd failed. Check: journalctl -u slapd -n 20" >&2; exit 1
fi

echo ""
echo "============================================================"
echo "  M1 Setup Complete"
echo "  LDAP Host    : $(hostname -I | awk '{print $1}'):389"
echo "  Base DN      : ${LDAP_BASE}"
echo "  Admin DN     : ${LDAP_ADMIN_DN}"
echo "  Anon Bind    : ENABLED"
echo "  Key Attr     : userPassword-plain on cn=svc-cicd"
echo "  Test cmd     : ldapsearch -x -H ldap://<IP> -b '${LDAP_BASE}' '(objectClass=*)'"
echo "============================================================"
