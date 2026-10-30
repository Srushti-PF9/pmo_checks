# PMO Management Plane Upgrade – Pre/Post Check Tool

A Bash script that captures the health of a PCD DU (Deployment Unit) before and after a management plane upgrade/migration, and compares the two snapshots to highlight regressions.

---

## Prerequisites

**Local machine (where you run the script)**
- `bash`, `ssh`, `curl`, `jq`, `diff`, `awk`, `sed`
- SSH access to the DU with **passwordless sudo**

**On the DU (used remotely by the script)**
- `/root/admin_admin.rc` (OpenStack admin credentials)
- `du_ctl` at `/opt/pf9/du-tools/du-ctl/du_ctl`
- `mysql` client with access to the `resmgr` DB
- `openstack` and `cinder` CLIs, `openssl`

---

## Setup

Before first use, replace the SSH username in **both** the Pre-Check and Post-Check sections:

```bash
ssh -o StrictHostKeyChecking=no -T "srushti@$SERVER" << 'EOF'   # Replace with your actual username
```

Then make the script executable:

```bash
chmod +x pmo_upgrade_check.sh
```

---

## Usage

```bash
./pmo_upgrade_check.sh
```

You will be prompted to choose:

| Option | Action | When to run |
|---|---|---|
| `1` | Pre-Check | Before the upgrade/migration starts |
| `2` | Post-Check | After the upgrade/migration completes |
| `3` | Compare | After both checks exist for the DU |

Enter the DU FQDN when prompted (e.g. `sbux-s0003.platform9.net`).

### Typical workflow

1. Run **Option 1** → save pre-check.
2. Perform the upgrade/migration.
3. Run **Option 2** → save post-check.
4. Run **Option 3** → review the comparison report and Executive Summary.
5. Review the **Upgrade Caveats** page (printed in the post-check) for any CMs/workarounds to reapply.

---

## Output Layout

All reports are stored per DU under `reports/`:

```
reports/
└── <DU_FQDN>/
    ├── precheck_<DU_FQDN>_<YYYY-MM-DD>.log
    ├── postcheck_<DU_FQDN>_<YYYY-MM-DD>.log
    └── comparison_report_<DU_FQDN>_<YYYY-MM-DD_HHMMSS>.log
```

---

## Checks Performed

| # | Check | Source |
|---|---|---|
| – | DU release version | `https://<DU>/clarity/features.json` |
| 1 | Host status & responsiveness | `du_ctl host list`, `resmgr.hosts` |
| 2 | HAProxy certificate expiry (latest version) | `/etc/pf9/haproxy-certs/*-vN.pem` |
| 3 | Hostagent version | `http://localhost:8082/v1/hosts` |
| 4 | Nova compute services (DOWN only) | `openstack compute service list` |
| 5 | Neutron network agents (DOWN only) | `openstack network agent list` |
| 6 | Cinder services (DOWN only) | `cinder service-list` |
| 7 | Non-ACTIVE servers | `openstack server list --all` |
| 8 | Host roles not in `applied` state | `resmgr.host_role_map` |
| 9 | Upgrade caveats reminder *(post-check only)* | Confluence link |

---

## Comparison Statuses

| Status | Meaning |
|---|---|
| `MATCH` | Pre and post output identical |
| `CHANGED` | Expected change (DU version, hostagent version, cert version) |
| `DIFF DETECTED` | Unexpected difference – a detailed diff is printed below the section |

Sections 4–9 ignore table padding/whitespace when deciding the status.

---

## Notes & Limitations

- **Same-day re-runs overwrite** the pre/post log for that DU (filename uses date only).
- **Compare uses the latest logs** in `reports/<DU_FQDN>/`; if none are found, it prompts for file paths.
- **DOWN service rows include timestamps** (`Updated At`), so a still-DOWN service may show as `DIFF DETECTED`. Check the diff before treating it as a regression.
- **HAProxy cert detection** only matches single-digit versions (`v1`–`v9`).
- `StrictHostKeyChecking=no` is used to avoid prompts; use only against known DUs.

---

## Reference

- Upgrade Caveats: https://platform9.atlassian.net/wiki/spaces/SUP/pages/1390018598/Upgrade+Caveats
