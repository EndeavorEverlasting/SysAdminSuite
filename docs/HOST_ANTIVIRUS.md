# Host antivirus

SysAdminSuite can run one installed, supported scanner on the local machine.
The weekly job is opt-in and uses Windows Task Scheduler on Windows or the
current user's crontab on native Linux. Use the Windows entrypoint for a
Windows host that happens to run WSL.

| Discovery result | Scan behavior |
| --- | --- |
| Microsoft Defender in normal, enabled mode | Quick scan via the Defender module. A fresh start/end pair records completion of a Defender quick scan. The timestamps are shared across Defender, and the receipt leaves detection assessment to Defender. |
| ESET Security or ESET Endpoint scanner in an expected Program Files directory | Command-line scan of the current user's home directory, with explicit detection-only switches. |
| Root-owned ClamAV executable in a standard Linux binary directory | Recursive scan of the current user's home directory, without following symlinks or crossing filesystems. The provider's existing signature database is required. |
| Consumer Malwarebytes installed, with no eligible automatic adapter selected | Receipt directs the operator to Malwarebytes Scan Scheduler. |
| Windows reports another registered provider | Receipt directs development to add a documented adapter. SysAdminSuite never invokes a registry-supplied command. |
| No supported scanner can be discovered on the host | Receipt records the provider gap. Install and bootstrap are outside this feature. |

Defender has first priority on Windows when enabled in normal mode. If it is
inactive or passive, the runner considers ESET and then the native Malwarebytes
scheduler. A failed or timed-out scan leaves a receipt and does not dispatch a
second scanner. Existing vendor, OS or managed-device protection settings still
apply.

## Use

Use Python 3.10 or newer. After refreshing the authorized development checkout,
use the following actions with `Manage-HostAntivirus.cmd` on Windows or
`python3 scripts/sas_antivirus.py` on native Linux:

| Action | Effect |
| --- | --- |
| `inspect` | Read provider availability. With no arguments, the Windows launcher runs this action. |
| `schedule plan` | Render the native scheduler definition without installing a job. The preview contains local paths. |
| `schedule install` | Register one job for the current account. Defaults to Sunday at 03:30 local time. Set `--day Friday --at 06:30` (or another day/time) on this action to update it. |
| `run` | Explicitly run a local scan now. |
| `sync` | Rebuild actionable checkout candidates from retained private receipts, without running a scan. |
| `schedule remove` | Remove the owned job while keeping existing receipts and other users' jobs. |

The Windows job uses noninteractive S4U under the current account at least
privilege, with a weekly calendar trigger. The task requests missed-run catch-up from Windows. Windows
keeps this scan off battery power. The account needs the **Log on as a batch
job** right and access to Python without an interactive session. Host policy
may deny task registration or scanner access. Use a
local checkout and local state. The Linux job needs an active cron service and
runs only while it is up. The job launches the stable checkout path captured
at installation. Reinstall the job if the checkout or Python moves.

## Receipts and repository sync

The silent job writes `latest.json` and a rolling history of 32 private scan
outcomes under `%LOCALAPPDATA%\SysAdminSuite\Antivirus` on Windows or
`~/.local/state/SysAdminSuite/Antivirus` on Linux. Receipt status distinguishes
completion, no detections reported, detections, incomplete scans, provider
gaps, and unconfirmed or interrupted runs. The runner discards scanner stdout
and stderr. To inspect a detection, use the scanner directly and review it
locally. Existing real-time, scan, and remediation settings remain vendor-owned.

The runner reconstructs reusable development actions from fixed codes and
syncs them into `evidence/antivirus-queue/` in the local checkout. Git must
confirm that the destination is untracked and ignored. One file per gap
deduplicates repeats. Candidate fields are the schema version, a fixed gap
code, a fixed action code and the review state. Provider, OS, timestamps,
paths, host identifiers, detection status, and raw scan output stay out of
this queue. The job never pushes or stages Git data. Review a queued action
and contribute generalized behavior or a synthetic regression via the
repository's existing review process.

Schema: `schemas/harness/host-antivirus-receipt.schema.json`. Acceptance:
`python Tests/survey/test_sas_antivirus.py`.

## Sources for provider interfaces

- [Defender scan invocation](https://learn.microsoft.com/en-us/powershell/module/defender/start-mpscan) and [completion fields](https://learn.microsoft.com/en-us/powershell/module/defender/get-mpcomputerstatus)
- [ESET scanner and return codes](https://help.eset.com/ees/11/en-US/advanced_cmd.html)
- [ClamAV CLI](https://docs.clamav.net/manual/Usage/Scanning.html) and [return codes](https://manpages.debian.org/trixie/clamav/clamscan.1.en.html)
- [Malwarebytes consumer Scan Scheduler](https://help.malwarebytes.com/hc/en-us/articles/31589496411291-Run-and-schedule-scans-in-Malwarebytes-for-Windows-and-Mac)
