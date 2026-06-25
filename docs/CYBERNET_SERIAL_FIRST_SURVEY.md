# Cybernet Serial-First Survey Workflow

This workflow treats the Cybernet workstation serial number as the stable device identity. Hostnames are useful probe hints, but they are mutable and should not be treated as the final identity.

## Identity rules

- Cybernet serial is the primary workstation identity.
- Hostname is a transport/probe hint only.
- MAC address is supporting evidence.
- Neuron serial is a linked asset, not a replacement for the Cybernet workstation serial.
- Hostname drift is not a failed identity when the observed serial matches the expected Cybernet serial.

## Offline work

These steps do not require the hospital network:

1. Build the serial-first manifest from source tracker/export data.
2. Run resolver logic against existing/offline evidence CSVs.
3. Build tracker cleanup and revisit priority reports.
4. Review generated CSVs for tracker updates, manual-review conflicts, and remote-lookup candidates.

## On-network work

These steps require the approved network and approved credentials/permission:

- Ping/preflight checks.
- DNS resolution.
- WMI identity collection.
- Port checks.
- Live observed serial/MAC collection.

Start with 2-3 known Cybernets, then scale to 10, 25, and 50 only after the small batch produces expected serial matches.

## Cleanup report

Generate cleanup and revisit reports from resolver output:

```bash
bash survey/sas-build-cybernet-cleanup-report.sh \
  --resolver-csv logs/mini-probe/<run>/live_serial_probe_results.csv \
  --output-cleanup logs/mini-probe/<run>/cybernet_tracker_cleanup.csv \
  --output-revisit logs/mini-probe/<run>/cybernet_revisit_priority.csv
```

The cleanup report is for tracker/data updates. The revisit report is for deciding what needs AD/Vision lookup, WMI/network retry, manual review, or possible physical revisit.

## Priority buckets

| Bucket | Meaning | Action |
| --- | --- | --- |
| `P0_manual_review` | Serial or MAC conflict | Stop automation; verify source data and physical evidence. |
| `P1_tracker_cleanup_only` | Identity resolved, tracker needs updates | Update hostname/MAC/serial fields; no physical revisit from this evidence alone. |
| `P2_no_revisit_needed` | Identity confirmed | No revisit needed based on supplied evidence. |
| `P3_ad_vision_lookup_needed` | Missing remote evidence | Check AD/Vision/tracker mapping before physical revisit. |
| `P3_wmi_or_network_retry` | No usable live identity evidence | Retry from approved network or enrich with AD/Vision. |
| `P4_remote_paths_exhausted` | Remote evidence still unresolved | Physical revisit only after AD/Vision/network paths are exhausted. |

## Safety

- Do not commit live WMI logs, mini-probe outputs, resolver CSVs, tracker exports, hostnames, serials, or MAC evidence.
- Keep run outputs under ignored runtime folders such as `logs/mini-probe/` or `survey/output/`.
- Do not use hostname-only evidence to confirm a workstation when serial/MAC is missing.
- Treat conflicts as manual review, not automatic tracker updates.

## Offline validation

Run both offline tests:

```bash
python tests/survey/test_serial_first_identity.py
python tests/survey/test_cybernet_cleanup_report.py
```

Expected output:

```text
offline serial-first identity tests passed
offline cybernet cleanup report tests passed
```
