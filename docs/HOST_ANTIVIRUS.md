# Host antivirus

SysAdminSuite can run one installed scanner or its own optional SHA-256 matcher on the local machine.
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

## SysAdminSuite SHA-256 matcher

The optional first-party matcher checks exact contents against a list of approved
file fingerprints. Supply three global arguments on the existing launcher
before `inspect`, `run`, `schedule plan` or `schedule install`.

| Argument | Value |
| --- | --- |
| `--scan-directory` | An explicit local folder. The matcher reads immediate regular files and skips links, reparse points and nested directories. |
| `--signatures` | An approved local JSON file with `schema_version` equal to `sas-antivirus-sha256-signatures/v1` and a nonempty `sha256` array of unique lowercase 64-character hexadecimal digests. |
| `--signature-sha256` | The approved SHA-256 of the entire JSON file as lowercase hexadecimal. Base trust on your reviewed source for the list. |

`inspect` validates the configuration. `schedule plan` previews what will be
registered, and `schedule install` reuses the existing quiet job. The runner
manages one job per account. Install with the matcher options to select this
mode, or install with the standard options to select vendor discovery. The
job references a profile in private local state by fingerprint. The worker
receives the scan directory, signature file and signature pin through stdin.
The callback checks both fingerprints at every run. A changed list produces
`OWNED_POLICY_REJECTED` until you approve the exact replacement bytes and
update the job. Use `schedule remove` to remove the existing task.

The matcher applies per-run limits of 10,000 directory entries, 64 MiB per
file, 512 MiB of attempted file reads, and a 60-second processing budget.
An inaccessible file, hard link, directory change, or exhausted budget can
produce `SCAN_INCOMPLETE`. A confirmed match with incomplete coverage produces
`DETECTION_REPORTED_INCOMPLETE`. A no-match result applies to covered files
and the approved digests. A one-byte change creates a different fingerprint.

The matcher reads files in place and uses the existing private receipts for
normalized results. Scan paths, file contents, file names, and the approved
policy pin are omitted from the result. Matching outcomes stay off the
checkout queue. A rejected policy may create a fixed-code
`REVIEW_PINNED_SIGNATURE_POLICY` candidate. Configure scope and signatures
locally. Keep reviewed lists and sensitive evidence in local storage.

This first-party engine is a base for later reviewed signature sources and
broader detectors. Existing antivirus provides real-time and behavioral
protection. The matcher uses the same quiet cadence and leaves remediation
decisions with the operator.

Focused inclusion and privacy check: `python Tests/survey/test_sas_av_sha256.py`.

## Sources for provider interfaces

- [Defender scan invocation](https://learn.microsoft.com/en-us/powershell/module/defender/start-mpscan) and [completion fields](https://learn.microsoft.com/en-us/powershell/module/defender/get-mpcomputerstatus)
- [ESET scanner and return codes](https://help.eset.com/ees/11/en-US/advanced_cmd.html)
- [ClamAV CLI](https://docs.clamav.net/manual/Usage/Scanning.html) and [return codes](https://manpages.debian.org/trixie/clamav/clamscan.1.en.html)
- [Malwarebytes consumer Scan Scheduler](https://help.malwarebytes.com/hc/en-us/articles/31589496411291-Run-and-schedule-scans-in-Malwarebytes-for-Windows-and-Mac)
