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
  - Synthetic/offline tests for hostname drift, manual-review conflicts, AD/Vision lookup candidates, and hostname-only serial-field safety.

- `tests/survey/run_offline_survey_tests.sh`
  - Runs the serial-first identity tests plus cleanup report tests.

- `docs/CYBERNET_SERIAL_FIRST_SURVEY.md`
  - Runbook for serial-first identity, offline cleanup, on-network collection, and priority buckets.

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
