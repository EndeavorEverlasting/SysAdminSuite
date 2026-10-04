# Latest Harness Evidence

This folder is a pointer for reviewed, human-readable summaries.

For PR #142, generated harness output is expected under local output folders first:

- `survey/output/harness-validator/`
- `survey/output/english-log/`
- `survey/output/runs/`

Do not treat this folder as a dumping ground. Add only reviewed summaries that are safe to track.

## Latest reviewed H&H evidence

PAXSTORE access-discovery evidence synchronized under P111 on 2026-10-04:

- `docs/HH_CC_READER_PAXSTORE_ACCESS_DISCOVERY.md`
- `docs/evidence/hh-cc-reader/paxstore/2026-10-04/README.md`
- `docs/evidence/hh-cc-reader/paxstore/2026-10-04/manifest.json`
- `docs/evidence/hh-cc-reader/paxstore/2026-10-04/presentation-source-index.md`
- `docs/evidence/hh-cc-reader/paxstore/2026-10-04/paxstore-access-discovery-sanitized-review-pack.pdf`

Raw screenshots remain in the private H&H Drive evidence workspace; the public repo tracks the reviewed 19-page sanitized appendix plus its manifest and source index.

### Kiosk4 local-access / input-method continuity

The current local firmware-baseline continuation was synchronized under P111 on 2026-10-04:

- `docs/HH_CC_READER_KIOSK4_LOCAL_ACCESS_FIELD_GUIDE.md`
- `docs/plans/hh-cc-p111-kiosk4-local-access-sync-20261004.plan.md`

The private H&H Drive guide owns credentials, live identity binding, and raw field evidence. The public derivative records only the sanitized decision contract: native alphanumeric entry on the observed Kiosk4 path is retired as proved-blocked; the remaining local branch is one bounded input-method-selector check plus one wired-HID classification before pivoting to an authorized management surface. The firmware gate remains `BASELINE_LOCKED / BLOCKED_EVIDENCE` until a labeled, identity-bound current value is captured and classified.

Current local validation commands:

```bash
git diff --check
bash Tests/bash/test_english_log_artifact_contracts.sh
bash Tests/bash/test_sysadmin_harness_validator_contracts.sh
```

```powershell
.\scripts\validate-sysadmin-harness.ps1
```
