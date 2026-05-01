# solve_blue.md — M5 · itops-ansible
## Blue Team Solution Writeup
**Range:** RNG-IT-02 · Internal Operations Zone
**Machine:** M5 — Ansible AWX Job Runner Portal

---

## Detection

### 1 — AWX Access Log (Job Output Access)
```bash
grep "JOB_OUTPUT_ACCESS" /var/log/pul-ansible/awx.log
```
**Indicator:**
```
JOB_OUTPUT_ACCESS | user=devops-admin | job=JOB-20241115-018 | from=203.0.2.X
```
Any access to the verbose deployment job output from a non-standard IP is a critical signal.

### 2 — File Browser Access
```bash
grep "FILE_BROWSE" /var/log/pul-ansible/awx.log | grep vault.yml
```
**Indicator:**
```
FILE_BROWSE | user=devops-admin | path=/group_vars/all/vault.yml | from=203.0.2.X
```

### 3 — SSH Activity on Jump Host
On `dev-jump.prabalurja.in (11.x.x.x)` — check auth log:
```bash
grep "Accepted publickey" /var/log/auth.log | grep devops
# Look for logins from unexpected source IPs (not 203.x.x.x or internal ranges)
```

---

## Containment
```bash
# 1. Revoke the compromised SSH key
# On dev-jump.prabalurja.in — remove from authorized_keys
sed -i '/GridFall-2024-Ed25519/d' /home/devops/.ssh/authorized_keys

# 2. Disable devops-admin AWX account
# Edit USERS dict in app.py — set role to locked, or remove from dict
systemctl restart pul-awx

# 3. Block attacker IP
ufw deny from <ATTACKER_IP> to any port 8080 comment "M5 AWX breach"
ufw deny from <ATTACKER_IP> to any port 22 on dev-jump

# 4. Rotate Ansible vault password
echo "$(openssl rand -base64 32)" > /etc/ansible/.vault_pass
# Re-encrypt all vault files with new password
find /opt/pul-infra-config -name 'vault.yml' -exec \
    ansible-vault rekey --new-vault-password-file=<(openssl rand -base64 32) {} \;
```

## Eradication
- **Job output verbosity:** Never log `--vault-password-file` contents. Use `no_log: true` in tasks handling secrets. Strip vault password from any debug/verbose output at the AWX level.
- **SSH key in job output:** SSH key provisioning should use Ansible's `vault` lookup — never echo raw key material to stdout.
- **File browser access:** `vault.yml` should not be accessible via browser in plaintext. Use secret management integration (Vault backend) instead of static vault files.
- **Principle of least privilege:** `devops-admin` account should not have access to historical job outputs from other teams' deployments.

## IOCs
| Type | Value |
|---|---|
| Attacker IP | `203.0.2.X` |
| Compromised Account | `devops-admin` |
| Exposed Secret 1 | Ansible vault password: `Ansibl3Vault@PUL!GridFall2024` |
| Exposed Secret 2 | SSH private key for `devops@dev-jump.prabalurja.in` |
| Pivot Achieved | SSH to `11.x.x.x` (RNG-DEV-01) |
| Log Signal | `JOB_OUTPUT_ACCESS` + `FILE_BROWSE vault.yml` from unexpected IP |
