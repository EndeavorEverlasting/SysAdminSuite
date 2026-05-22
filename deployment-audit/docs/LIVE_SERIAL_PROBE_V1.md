# Live Serial Probe V1

## Productization Contract

This document converts the Replit live serial probe concept into clean SysAdminSuite implementation work.

Source branch:

- `feature/2026-05-21-live-serial-probe`

Source files to inspect before code extraction:

- `deployment-audit/docs/LIVE_SERIAL_PROBE_SPRINT.md`
- `survey/sas-live-serial-probe.sh`
- `survey/fixtures/live_serial_manifest.sample.csv`
- `survey/fixtures/live_serial_identity.sample.csv`
- `deployment-audit/tests/test_live_serial_probe_contracts.sh`
- `deployment-audit/sas-render-live-serial-dashboard.py`

The source branch is reference material, not a direct merge target.

## Non-Negotiables

- Bash means Bash-on-Windows, usually Git Bash or MSYS2.
- Do not treat Bash as Linux.
- Do not rewrite tooling for Replit/Linux just because Windows executables are missing there.
- Do not delete, truncate, or deprecate PowerShell files.
- Keep live probing scoped, read-only, and explicit.
- Offline/test mode must work before live probing is trusted.
- Generated CSV/HTML output with real hostnames, serials, MACs, users, rooms, departments, or locations must not be committed.

---

# Live Serial Probe Sprint

## Objective

Probe live Cybernet and Neuron workstation targets for serial and MAC evidence, then classify each target into a clear operational lane.

The audit report is the triage lens. The live probe is the confirmation layer.

## Why This Exists

Duplicate reports can show repeated serials, MACs, or hostnames. That does not automatically mean a real deployment duplicate exists.

The next field question is sharper:

- Which live devices can confirm their serials and MACs?
- Which tracker rows are missing data we can now populate?
- Which devices are unreachable and should be marked off until located in AD or Vision?
- Which rows have conflicting evidence and need human review?

## Required Runtime

Use Bash on Windows, usually Git Bash or MSYS2 Bash.

Do not default to PowerShell.
Do not use Linux-only networking commands.

## Primary Command

```bash
bash survey/sas-live-serial-probe.sh \
  --manifest survey/output/remote_survey_manifest.csv \
  --output survey/output/live_serial_probe_results.csv \
  --dashboard survey/output/live_serial_probe_dashboard.html
```

## Safe Offline/Test Mode

Use `--identity-csv` to test classification and dashboard rendering without touching live endpoints.

```bash
bash survey/sas-live-serial-probe.sh \
  --manifest survey/fixtures/live_serial_manifest.sample.csv \
  --identity-csv survey/fixtures/live_serial_identity.sample.csv \
  --output survey/output/live_serial_probe_results.csv \
  --dashboard survey/output/live_serial_probe_dashboard.html
```

## Output CSV

`live_serial_probe_results.csv` includes:

| Column | Purpose |
|---|---|
| `target` | Hostname or identifier probed |
| `source_row` | Source row from tracker or manifest when available |
| `device_type` | Cybernet, Neuron, Workstation, or Unknown |
| `expected_hostname` | Hostname expected from tracker/manifest |
| `expected_cybernet_serial` | Tracker Cybernet serial, when present |
| `expected_neuron_serial` | Tracker Neuron serial, when present |
| `expected_mac` | Tracker MAC, when present |
| `observed_hostname` | Hostname observed live, when available |
| `observed_serial` | Serial observed live, when available |
| `observed_mac` | MAC observed live, when available |
| `reachability_status` | reachable, unreachable, dns_only_no_ping, reachable_wmic_only, or not_checked |
| `serial_probe_status` | serial_observed, identity_observed_no_serial, serial_probe_blocked, serial_probe_failed, etc. |
| `classification` | Operational lane for action |
| `follow_up_system` | Tracker update, AD, Vision, or manual review route |
| `already_had_serial` | yes/no flag showing tracker already had serial data |
| `already_had_mac` | yes/no flag showing tracker already had MAC data |
| `can_populate_serial` | yes/no flag showing live evidence can fill a missing serial |
| `can_populate_mac` | yes/no flag showing live evidence can fill a missing MAC |
| `log_status` | Compact logging posture for downstream reporting |
| `notes` | Probe details or conflict notes |
| `probed_at` | Timestamp |

## Classifications

| Classification | Meaning | Action |
|---|---|---|
| `live_serial_confirmed` | Live probe found serial or MAC evidence | Populate missing fields or confirm tracker values |
| `reachable_no_serial` | Host responds but serial/MAC was not collected | Try approved stronger identity path or Vision |
| `unreachable_mark_off` | Host is unreachable | Mark off and route to AD/Vision before treating as error |
| `needs_ad_lookup` | Target or DNS posture is weak | Locate object in AD |
| `needs_vision_lookup` | Asset inventory lookup needed | Locate in Northwell Vision or equivalent inventory |
| `manual_review` | Observed values conflict with tracker values | Human review before tracker update |

## HTML Dashboard

The dashboard shows:

- total rows
- live confirmed rows
- rows where serials can be populated
- rows where MACs can be populated
- rows where tracker already had serials/MACs
- unreachable/off rows
- manual review rows
- category panels with filters
- follow-up routing counts
- dashboard summary JSON

The dashboard is a local operational artifact. Do not commit generated dashboards or CSVs containing real Northwell hostnames, serials, MACs, or locations.

## Field Rule

Unreachable does not mean duplicate error.

Unreachable means:

1. mark off for now
2. locate in AD or Vision
3. only escalate after external lookup fails or conflicts

No ghosts. No panic. No theatrical red cells.

---

## Implementation Sequence

1. Commit this contract.
2. Add sample fixtures.
3. Add the offline contract test.
4. Add the probe script in offline mode first.
5. Add the dashboard renderer after the CSV contract is stable.
6. Run the offline contract test.
7. Review live probe behavior only after offline mode passes.
8. Keep any live endpoint probing explicitly scoped and read-only.

## Definition of Done for V1

- Contract doc exists.
- Sample fixtures exist and contain no real protected data.
- Offline contract test passes.
- Probe script emits the expected CSV.
- Dashboard renderer emits the expected HTML.
- Generated output files are ignored or kept out of commits.
- No production branch mutation.
