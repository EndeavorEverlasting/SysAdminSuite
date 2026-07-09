# Latest Harness Evidence

This folder is a pointer for reviewed, human-readable summaries.

For PR #142, generated harness output is expected under local output folders first:

- `survey/output/harness-validator/`
- `survey/output/english-log/`
- `survey/output/runs/`

Do not treat this folder as a dumping ground. Add only reviewed summaries that are safe to track.

Current local validation commands:

```bash
git diff --check
bash Tests/bash/test_english_log_artifact_contracts.sh
bash Tests/bash/test_sysadmin_harness_validator_contracts.sh
```

```powershell
.\scripts\validate-sysadmin-harness.ps1
```
