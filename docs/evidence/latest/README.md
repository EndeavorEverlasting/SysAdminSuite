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

The private H&H Drive guide owns protected operational context and raw field evidence. The public derivative now records the superseding sanitized decision contract: the local menu inventory is complete; Connectivity Test, Netstat, and Network Settings are closed branches; numeric security prompts restrict alphabetic input; the USB keyboard is functional; and Ping/Trace diagnostic host fields establish alphanumeric text capability. The remaining technical path is authoritative source ownership plus current version/package evidence, not another input-method or menu-discovery pass.

Current local validation commands:

```bash
git diff --check
bash Tests/bash/test_english_log_artifact_contracts.sh
bash Tests/bash/test_sysadmin_harness_validator_contracts.sh
```

```powershell
.\scripts\validate-sysadmin-harness.ps1
```


### Accepted presentation checkpoint — 2026-10-05

`Kiosk4 Firmware Gate — Executive Cinematic v2 — 2026-10-05.pptx` is the accepted presentation checkpoint.

The operator explicitly accepted the current state as a solid checkpoint. P111 therefore treats presentation synchronization as closed until new technical evidence changes the story or the operator explicitly requests another deck pass.

Current technical return point:

```text
authorized source owner
  -> current installed version evidence
  -> package/version-domain evidence
  -> restore/rollback proof
  -> update authority
  -> one controlled reader update
  -> post-update verification
```

### Kiosk4 firmware discovery Iteration 1 — 2026-10-05

Integrated implementation floor:

- PR #495 merged to `main` as `4aa474946f283882874d837673c3bb964fd879d1`.
- capture contract is fail-closed and operator-minimal;
- synthetic positive/negative classifier fixtures are integrated;
- the local menu/input branch is closed;
- live `current_firmware_value` remains unobserved;
- `BASELINE_LOCKED=false` and `mutation_authorized=false`.

Durable checkpoint:

- `docs/evidence/hh-cc-reader/kiosk4/2026-10-05/iteration-1-firmware-gate-checkpoint.md`

Next critical path: obtain one authorized read-only labeled current-version observation for the same private Kiosk4 identity, classify its version domain, then attempt the baseline freeze. Do not substitute tracker/history firmware values or reopen the closed local menu branch.

### Kiosk4 P82/P04 post-observation convergence — 2026-10-05

Local recovery of the canonical private capture completed on 2026-10-05. The file exists and matches the capture schema, but `capture_state=AWAITING_FIELD_OBSERVATION` with zero labeled rows. Classifier primary is unbound. Same-Kiosk4 identity remains `UNIQUE_TARGET_RESOLVED`. Baseline evaluator returned `BASELINE_INCOMPLETE` missing only `current_firmware_value`. This does not promote live firmware, version domain, or `BASELINE_LOCKED`.

Canonical continuation plan:

- `docs/plans/hh-cc-kiosk4-p82-p04-post-observation-convergence-20261005.plan.md`

Next transition is one authorized read-only labeled installed-firmware observation written into the same private capture, then classifier + baseline evaluation. Do not invent a numeric version, campaign target, tracker history, or PAXSTORE fixture observe as current.

### Kiosk4 P97 Android / remote capability frontier — 2026-10-06

P97 exhaustively mapped Android/remote-management/capability potential beyond the firmware label gate. Firmware observation remains a parallel critical path; it does not block capability-frontier follow-on.

Canonical research artifact:

- `docs/research/hh-cc-kiosk4-p97-android-remote-capability-frontier-20261006.md`

Successor phase map:

- `docs/plans/hh-cc-kiosk4-p97-capability-successor-map-20261006.plan.md`

Proof ceiling: research prioritization only. Does not prove AirViewer enrollment, Device Owner state, live firmware, or mutation authority.
