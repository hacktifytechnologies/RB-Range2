# Assessment Questions — RNG-IT-02 · Internal Operations Zone
## OPERATION GRIDFALL | Question Format: 3 MCQ + 2 FIB per Machine

---

## M1 — itops-ldap (OpenLDAP)

**MCQ-1:** What LDAP operation mode allows a client to connect to the directory without providing any credentials?
- A) Anonymous bind
- B) Simple bind
- C) SASL bind
- D) Kerberos bind
**Answer:** A

**MCQ-2:** Which LDAP search scope covers an entire subtree starting from the base DN?
- A) base (scope=0)
- B) one (scope=1)
- C) sub (scope=2)
- D) children (scope=3)
**Answer:** C

**MCQ-3:** The custom attribute on the `svc-cicd` account that exposed its credential is non-standard. What OpenLDAP mechanism was used to define this attribute?
- A) Dynamic backend (dyndb)
- B) olcSchemaConfig extension in cn=config
- C) LDIF flat file schema
- D) SASL attribute mapping
**Answer:** B

**FIB-1:** The username of the service account whose plaintext password was stored in the custom attribute is `_____________`.
**Answer:** `svc-cicd`

**FIB-2:** The credential extracted from the `userPassword-plain` attribute, used to pivot to M2, is `_____________`.
**Answer:** `CICD@Deploy!2024`

---

## M2 — itops-git (Gitea)

**MCQ-1:** Which git command is used to display the full diff of a specific past commit, including file contents that were later deleted?
- A) `git diff HEAD~1`
- B) `git show <commit-hash>:<filepath>`
- C) `git log --follow`
- D) `git stash show`
**Answer:** B

**MCQ-2:** What is the MITRE ATT&CK technique ID for "Data from Code Repositories"?
- A) T1087.002
- B) T1552.001
- C) T1213.003
- D) T1046
**Answer:** C

**MCQ-3:** An attacker "deletes" a file from a git repository using `git rm` and commits. The credential in that file is:
- A) Permanently removed from all clones
- B) Only retained on the remote server
- C) Still recoverable from the commit history
- D) Overwritten in the `.git/objects` directory
**Answer:** C

**FIB-1:** The Vault AppRole `VAULT_ROLE_ID` found in the git history of `pul-infra-config` is `_____________`.
**Answer:** `pul-cicd-role-7a3f9b2c1d4e`

**FIB-2:** The name of the file containing the Vault AppRole secrets, committed in the second commit of the `pul-infra-config` repository, is `_____________`.
**Answer:** `.env`

---

## M3 — itops-vault (HashiCorp Vault)

**MCQ-1:** When HashiCorp Vault is started with the `-dev` flag, which statement is true?
- A) All data is encrypted at rest using AES-256
- B) Vault is sealed and requires an unseal key on every restart
- C) Vault runs in-memory with a root token printed to stdout
- D) AppRole auth is disabled by default
**Answer:** C

**MCQ-2:** Which Linux command can be used to read environment variables of a running process via the `/proc` filesystem?
- A) `env -p <pid>`
- B) `cat /proc/<pid>/environ | tr '\0' '\n'`
- C) `lsof -p <pid> -e environ`
- D) `strace -e environ -p <pid>`
**Answer:** B

**MCQ-3:** What Vault path contains the AD monitoring service account credential?
- A) `secret/pul/monitor`
- B) `secret/pul/cicd`
- C) `secret/pul/ad`
- D) `auth/approle/role/pul-cicd`
**Answer:** C

**FIB-1:** The Vault root token leaked in the systemd journal is `_____________`.
**Answer:** `pul-vault-root-s3cr3t-2024-gridfall`

**FIB-2:** The AD service account password read from `secret/pul/ad` is `_____________`.
**Answer:** `M0n!tor@PUL24`

---

## M4 — itops-monitor (Prometheus Portal)

**MCQ-1:** Which Prometheus metric label in the `/metrics` output contained embedded basic-auth credentials?
- A) `pul_scrape_target_up`
- B) `pul_scrape_target_url`
- C) `pul_http_requests_total`
- D) `pul_alert_count`
**Answer:** B

**MCQ-2:** URL encoding encodes the `@` character as which sequence?
- A) `%40`
- B) `%64`
- C) `%2F`
- D) `%20`
**Answer:** A

**MCQ-3:** What is the primary security control missing from the `/metrics` endpoint in this challenge?
- A) Rate limiting
- B) TLS encryption
- C) Authentication / authorisation
- D) Input validation
**Answer:** C

**FIB-1:** The username embedded (URL-encoded) in the `ansible-metrics` scrape URL label is `_____________`.
**Answer:** `devops-admin`

**FIB-2:** The decoded password for the `devops-admin` account found in the `/metrics` output is `_____________`.
**Answer:** `DevOps@PUL!24`

---

## M5 — itops-ansible (Ansible AWX)

**MCQ-1:** Which Ansible task attribute should always be set when a task handles sensitive data (passwords, keys) to prevent it from appearing in logs?
- A) `sensitive: true`
- B) `no_log: true`
- C) `log_level: none`
- D) `vault_encrypted: true`
**Answer:** B

**MCQ-2:** The Ansible vault password was leaked because it appeared in job output. Which argument to `ansible-vault` caused the password to be echoed?
- A) `--ask-vault-pass`
- B) `--vault-password-file` combined with verbose mode echoing file content
- C) `--vault-id`
- D) `--output=-`
**Answer:** B

**MCQ-3:** What AWX/Tower job in the history (by job name) contains the leaked credentials?
- A) `sync-ldap-groups`
- B) `rotate-vault-approle`
- C) `deploy-dev-infra`
- D) `backup-config`
**Answer:** C

**FIB-1:** The Ansible vault password found in the verbose job output is `_____________`.
**Answer:** `Ansibl3Vault@PUL!GridFall2024`

**FIB-2:** The username and host of the DEV zone jump host accessible via the extracted SSH key is `_____________@_____________`.
**Answer:** `devops@dev-jump.prabalurja.in`

---

*Assessment Questions — GRIDFALL RNG-IT-02 | Classification: RESTRICTED — White Team Only*
