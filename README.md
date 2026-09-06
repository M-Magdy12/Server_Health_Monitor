# Server Health Monitor

A lightweight Bash tool that connects to a fleet of remote servers over SSH, checks their resource health (RAM, disk, load, uptime, Docker status), and emails an alert when something crosses a warning or critical threshold. Failed connections are logged and reported separately.

## Features

- **Parallel health checks** — servers are checked concurrently (bounded by `MAX_SERVERS`) using background jobs, instead of one at a time.
- **Threshold-based status** — RAM and disk usage are classified as `OK` / `WARNING` / `CRITICAL` against configurable thresholds.
- **Single SSH connection per server** — connectivity test and health check happen in one SSH session.
- **Non-interactive & fault-tolerant** — `BatchMode` + `ConnectTimeout` mean one unreachable host can't hang the whole run.
- **Conditional email alerts** — an alert email is sent only when a `WARNING`/`CRITICAL` is actually found, and failed connections are reported separately, via `msmtp`.
- **Concurrency-safe logging** — `flock` serializes writes to the shared log files so parallel jobs don't interleave or corrupt output.
- **CSV-driven server list** — no hardcoded hosts; add/remove servers by editing a config file.

## Requirements

- Bash 4+ (uses associative arrays)
- `ssh` access to every target server, key-based (no password prompts)
- [`msmtp`](https://marlam.de/msmtp/) configured on the machine running the script, for email delivery
- On each **remote** server: the connecting user must be able to run `docker ps` without a password prompt (add the user to the `docker` group — see [Notes](#notes))

## Configuration

Create a CSV file with one server per line:

```
username,hostname,/path/to/private_key
deploy,10.0.0.12,~/.ssh/prod_key
deploy,10.0.0.13,~/.ssh/prod_key
ubuntu,web01.example.com,~/.ssh/web_key
```

| Column | Meaning |
|---|---|
| 1 | SSH username |
| 2 | Hostname or IP |
| 3 | Path to the SSH private key for that server |

Windows-style line endings (`\r\n`) are stripped automatically, so the file can be edited on any OS.

## Usage

```bash
chmod +x monitor.sh
./monitor.sh -c /path/to/servers.csv -e you@example.com
```

| Flag | Description |
|---|---|
| `-c` | Path to the CSV config file (required) |
| `-e` | Email address to receive alerts (required) |

### Sample output

```
Trying to connect to deploy@10.0.0.12...
Trying to connect to deploy@10.0.0.13...
Trying to connect to ubuntu@web01.example.com...

connected succesfully to deploy@10.0.0.12
DATA at /home/user/26-09-06__15-27_LOGS
===================================

couldnt connect to ubuntu@web01.example.com
check failed logs at /home/user/26-09-06__15-27_FAILED_LOGS
===================================
```

Results print as soon as each server's check completes, so the order won't match the order connections were started in — that's expected with parallel execution.

## Output files

Two timestamped files are created in the current working directory on every run:

- `YY-MM-DD__HH-MM_LOGS` — full health report per server (load average, uptime, memory, disk, Docker container counts)
- `YY-MM-DD__HH-MM_FAILED_LOGS` — one entry per server that couldn't be reached, with the SSH error

## How it works

1. `get_key()` parses the CSV into an associative array keyed by `user@host`, mapping each server to its private key path.
2. For every server, `run_check()` is launched as a background job (`&`), capped at `MAX_SERVERS` concurrent jobs via a `jobs -rp | wc -l` / `wait -n` throttle.
3. `server_check()` opens a single SSH session, runs a remote health-check script over a heredoc, and returns its output.
4. On success, `report()` appends the result to the main log; on failure, `failed_logs()` appends to the failed log. Both use `flock` to serialize writes across concurrent jobs.
5. After all jobs finish (`wait`), the main log is scanned for `WARNING`/`CRITICAL` markers; if any are found, an alert email is sent. If the failed-connections log is non-empty, a separate email is sent.
