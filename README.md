# Multi-Server Infrastructure Health Monitor

A lightweight, robust Bash-based monitoring utility designed to automate system health checks across remote Linux servers via SSH, evaluate resource usage against defined threshold limits, and send targeted email alerts.

---

##  Key Features

- **Dynamic Server Management:** Parses server SSH endpoints and private key paths from an external CSV configuration file.
- **System Metrics Extraction:**
  - **CPU Load:** Real-time system load average (`1m`, `5m`, `15m`).
  - **Uptime:** Human-readable server running time.
  - **Memory Health:** Calculates percentage used vs. total available RAM (MB).
  - **Storage Usage:** Tracks primary root partition space (`/`).
  - **Container Operations:** Audits active vs. total Docker containers.
- **Threshold Alerting System:** Automatically flags resource metrics with `[OK]`, `[WARNING]`, or `[CRITICAL]` indicators based on predefined capacity limits.
- **SSH Error Handling:** Catches failed connectivity attempts and outputs verbose connection errors into a dedicated log file.
- **Automated Incident Emails:** Uses `msmtp` to send incident summaries containing full server context blocks whenever critical thresholds are breached or connections fail.

---

##  Prerequisites

Ensure the control node has the following installed and configured:

- **Bash 4.0+** (Required for associative arrays and process substitution)
- **OpenSSH Client** (Configured with SSH key-based access to target nodes)
- **msmtp** (Or an equivalent local mail transfer agent)
- **Standard Linux Utilities:** `awk`, `grep`, `df`, `free`, `uptime`, `sed`

---

##  Configuration

Create a CSV configuration file (e.g., `servers.csv`) containing target server details in the following format:

```csv
user@ip,key_path

```

**Example:**

```csv
ubuntu@3.88.71.1,/home/user/Desktop/ubuntuKey.pem

```

---

## 🚀 Usage

1. Grant execution permissions:
```bash
chmod +x monitor.sh

```


2. Run the script:
```bash
./monitor.sh

```


3. When prompted:
* Enter the relative or absolute path to your `servers.csv` file.
* Enter the destination email address for monitoring alerts.



---

## 📊 Output Log Format

Reports generated inside `${DATE}_LOGS` follow a structured key-value layout:

```text
===================================================================
  SERVER  : ubuntu@3.88.71.71
===================================================================
  Load Average       : 0.15 (1m), 0.08 (5m), 0.02 (15m)
  Uptime             : up 2 weeks, 3 days, 5 hours
  Memory             : [OK] 42% used (1850MB available)
  Storage (/)        : [WARNING] 82% used (8.5G free)
  Docker Status      : 4 running / 6 total
===================================================================

```

---