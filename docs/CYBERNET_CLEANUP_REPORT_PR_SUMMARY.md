# Cybernet Cleanup Report PR Summary

## Scope

This change adds the offline cleanup/reporting layer after the serial-first identity resolver.

## Added files

- `survey/sas-build-cybernet-cleanup-report.sh`
  - Reads `live_serial_probe_results.csv` from `survey/sas-live-serial-probe.sh`.
  - Writes a tracker cleanup CSV.
  - Writes a revisit priority CSV.
  - Does not call WMI, AD, DNS, ping, or endpoints.

- `tests/survey/test_cybernet_cleanup_report.py`
  - Synthetic/offline tests for hostname drift, manual-review conflicts, AD/Vision lookup candidates, hostname-only serial-field safety, and hostname-drift rows without serial/MAC evidence.

- `tests/survey/run_offline_survey_tests.sh`
  - Runs the serial-first identity tests plus cleanup report tests.

- `docs/CYBERNET_SERIAL_FIRST_SURVEY.md`
  - Runbook for serial-first identity, offline cleanup, on-network collection, and priority buckets.

## Known gaps and risks

- This report is only as good as the resolver CSV it receives. Bad tracker exports, stale AD/Vision data, or incomplete WMI evidence can still produce review work.
- The script does not write back to the tracker, AD, Vision, or any endpoint. It produces recommended actions only.
- Hostname-only evidence is treated as insufficient. A row cannot be cleared as no-revisit-needed or tracker-cleanup-only unless serial or MAC evidence is present.
- Serial/MAC conflicts are intentionally not resolved automatically. They are sent to manual review.
- Empty or very incomplete resolver files will produce low-value output. Operators should confirm the resolver input came from the expected run folder before using the reports.
- Generated CSVs may contain real hostnames, serials, and MACs. Keep them in ignored runtime folders and do not commit them.

## Next steps after merge

1. Run the offline test runner after pulling `main`.
2. Run a small approved WMI/live identity sample from the admin box.
3. Build cleanup and revisit reports from that sample.
4. Spot-check all P0 and P1 rows against tracker/AD/Vision before using the recommendations operationally.
5. Only schedule physical revisits after AD/Vision/WMI/network paths are exhausted.

## Validation command

```bash
bash tests/survey/run_offline_survey_tests.sh
```

Expected output includes:

```text
offline serial-first identity tests passed
offline cybernet cleanup report tests passed
```

## Safety

Generated outputs should stay in ignored runtime locations such as `logs/mini-probe/` or `survey/output/`.
