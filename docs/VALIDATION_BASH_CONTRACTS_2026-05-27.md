# Validation - Bash Contracts (2026-05-27)

Validation branch: `docs/post-convergence-validation-2026-05-27`  
Commit under test: `9ec89e44fb2fe24458dbdb799ac64d8b4f796bdf`  
Runtime shell: PowerShell on Windows (no `/bin/bash` present in this session)

## Commands run

```bash
bash deployment-audit/tests/test_hostname_availability_contracts.sh
bash deployment-audit/tests/test_autologon_assessment_contracts.sh
bash deployment-audit/tests/test_live_serial_probe_contracts.sh
bash tests/bash/test_registry_install_diff_wrapper_contracts.sh
```

## Results

| Script | Exit | Result | Evidence |
|---|---:|---|---|
| `deployment-audit/tests/test_hostname_availability_contracts.sh` | 1 | Failed before script execution | `_out/validation/deployment-audit_tests_test_hostname_availability_contracts.sh.log` |
| `deployment-audit/tests/test_autologon_assessment_contracts.sh` | 1 | Failed before script execution | `_out/validation/deployment-audit_tests_test_autologon_assessment_contracts.sh.log` |
| `deployment-audit/tests/test_live_serial_probe_contracts.sh` | 1 | Failed before script execution | `_out/validation/deployment-audit_tests_test_live_serial_probe_contracts.sh.log` |
| `tests/bash/test_registry_install_diff_wrapper_contracts.sh` | 1 | Failed before script execution | `_out/validation/tests_bash_test_registry_install_diff_wrapper_contracts.sh.log` |

Observed error in all four logs:

```text
<3>WSL (...) ERROR: CreateProcessCommon:735: execvpe(/bin/bash) failed: No such file or directory
```

## Known gaps

- Bash runtime was not available at `/bin/bash`; contracts did not run.
- Contract logic was not exercised, so no feature-level pass/fail evidence was produced.

## Risks

- Validation confidence remains low for Bash contract lanes.
- A merge based on this run would risk shipping without contract coverage.

## Targets

1. Re-run all four scripts in Git Bash/MSYS2 (or a CI runner with Bash available).
2. Capture each script's stdout/stderr and explicit PASS/FAIL assertions from the script body.
3. Add a Bash CI lane to prevent runtime mismatch (`/bin/bash` missing) from silently skipping contract intent.
