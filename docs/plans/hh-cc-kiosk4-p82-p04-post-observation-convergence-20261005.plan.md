# Kiosk4 P82/P04 Post-Observation Convergence Plan

Date: 2026-10-05
Repository: EndeavorEverlasting/SysAdminSuite
Base floor: `main@322cede1900ce4232d4f980e74d791dbe8acabeb`
Status: ACTIVE CONTINUATION
Owner: H&H CC-reader live firmware evidence lane
Mutation boundary: no firmware/device mutation

## Current reality

The operator reports that the authorized read-only Kiosk4 observation is finished.

That operator report is important continuity evidence, but this ChatGPT/provider runtime cannot read the resulting local private capture from GitHub or connected Drive. Therefore:

```text
FIELD_ACTION=REPORTED_COMPLETE
PRIVATE_EVIDENCE_INGEST=UNPROVEN
CURRENT_FIRMWARE=DO_NOT_INFER
VERSION_DOMAIN=VERSION_DOMAIN_UNRESOLVED
BASELINE_LOCKED=false
MUTATION_AUTHORIZED=false
```

Do not ask the operator to repeat an already-completed observation while recoverable local evidence may exist.

## P82 — Prototype / Measure / Refine

### Hypothesis

One authorized read-only same-Kiosk4 observation can supply enough labeled evidence to classify the current version domain and decide the baseline gate.

### Build

Integrated floor:

- PR #495: fail-closed capture contract + positive/negative classifier fixtures.
- PR #496: durable Iteration-1 checkpoint + stale local-input route retirement/regression.
- Canonical capture schema: `sas-hh-cc-reader-kiosk4-version-evidence-capture/v1`.
- Canonical classifier: `Classify-HHCCReaderVersionDomain.cmd`.
- Canonical baseline evaluator: `Evaluate-HHCCReaderFirmwareRoundtrip.cmd baseline`.

### Measure

The operator reports the read-only observation completed.

Provider readback from this runtime found no new private capture, classifier receipt, or baseline receipt in GitHub/connected Drive. That means the experiment action is complete but evidence ingestion remains open.

### Critique

The residual friction is not another firmware-discovery problem. It is a cross-runtime evidence handoff problem:

```text
operator/provider/physical observation
  -> local private capture
  -> classifier receipt
  -> private baseline input
  -> baseline receipt
  -> sanitized durable checkpoint
```

Do not solve that by replaying the field action. Recover the local evidence first.

### Decide

Advance only through:

```text
OBSERVATION_REPORTED_EVIDENCE_INGEST_PENDING
  -> recover private capture
  -> validate capture
  -> classify version domain
  -> build same-identity private baseline input
  -> evaluate baseline
  -> BASELINE_LOCKED or exact fail-closed blocker
```

Preserve the last known-good integrated floor and keep `mutation_authorized=false`.

## P04 factoring

### Parallel execution

`PARALLEL EXECUTION: NOT_APPLICABLE — dependency graph width is 1.`

The classifier, baseline, restore/package, and deployment branches all depend on recovery of the just-completed private observation. Parallelizing successor work before that value/domain is recovered would invite inference or duplicate work.

### Lane L0 — Recover completed observation and converge baseline

Runtime: LOCAL_AGENT_RUNTIME (Cursor/local Windows repo)
Dependencies: operator-reported observation complete; refreshed `origin/main`
Owned scope:

- private local capture/receipts only;
- classifier invocation;
- same-device private baseline input;
- baseline receipt;
- sanitized state/handoff after proof.

Forbidden scope:

- repeat field observation before local recovery is exhausted;
- copy live serial/MAC/IP, credentials, session material, or private evidence URLs into Git;
- invent `current_firmware_value`;
- treat tracker/history/target values as current;
- push/schedule/assign/reset/change settings;
- firmware mutation.

Expected private artifacts:

- original capture: `%TEMP%\hh-cc-kiosk4-labeled-firmware-observation.json` when present;
- version-domain evaluation: ignored `survey/output/hh-cc-reader/hh-cc-reader-version-domain-*.json` or explicit private output;
- baseline input: local/private JSON assembled from the existing Kiosk4 identity receipt + classified current value + governed target;
- baseline receipt: ignored `survey/output/hh-cc-reader/hh-cc-reader-firmware-roundtrip-baseline-*.json`.

Completion gate:

- capture is valid and identity-bound;
- classifier chooses an authoritative current-firmware observation/domain or fails closed with an exact reason;
- baseline evaluator returns `BASELINE_LOCKED` or a precise `BASELINE_INCOMPLETE` blocker;
- `mutation_authorized=false`;
- no private live values are committed.

### Exact local execution order

1. Refresh remote/provider truth and protect dirty work.
2. Resolve the repository default branch and use an isolated worktree if the current checkout is dirty or separately owned.
3. Recover the already-created private capture before asking the operator for anything.
4. Validate/classify:

```cmd
Classify-HHCCReaderVersionDomain.cmd --input "%TEMP%\hh-cc-kiosk4-labeled-firmware-observation.json" --output "%TEMP%\hh-cc-kiosk4-version-domain-iter2.json"
```

5. Read the classifier result. Do not manually choose a bare numeric string.
6. Build a private baseline input from the existing same-Kiosk4 identity evidence with these required fields:

```text
source_serial
expected_mac
current_firmware_value
target_firmware_value
identity_proof_state=UNIQUE_TARGET_RESOLVED
```

Preserve optional captured evidence references/timestamp when available. The baseline input remains private/local.

7. Evaluate:

```cmd
Evaluate-HHCCReaderFirmwareRoundtrip.cmd baseline --input "%TEMP%\hh-cc-kiosk4-baseline-input.json" --output "%TEMP%\hh-cc-kiosk4-baseline-iter2.json"
```

8. Read back the receipt. Accept only:
   - `BASELINE_LOCKED`; or
   - exact fail-closed `missing_fields` / identity blocker.
9. Run the focused owning contracts and patch hygiene if any tracked continuity file is changed.
10. Persist only sanitized state transition/proof references; keep raw/private values ignored.

### Return contract

Cursor/local agent returns:

```text
CAPTURE_RECOVERED=<true|false>
CAPTURE_VALID=<true|false>
CLASSIFICATION=<typed classifier result>
VERSION_DOMAIN=<typed domain>
CURRENT_FIRMWARE_BOUND=<true|false>
BASELINE_STATE=<BASELINE_LOCKED|BASELINE_INCOMPLETE>
BASELINE_MISSING_FIELDS=<list>
MUTATION_AUTHORIZED=false
PRIVATE_ARTIFACT_PATHS=<local paths only; do not paste secret/private contents>
SANITIZED_DURABLE_UPDATE=<commit/PR/path or none>
```

## P04 successor routing after L0

Do not pre-commit the successor lane until L0 returns.

If `BASELINE_LOCKED`:

1. package/version mapping for the classified domain;
2. live restore/rollback proof for the same starting value/package;
3. explicit selected-path mutation authority;
4. one controlled reader update;
5. authoritative post-update observation;
6. restoration/round-trip proof before fleet scale;
7. downstream H&H publication from canonical SAS firmware evidence event.

If `BASELINE_INCOMPLETE`:

- repair only the exact missing evidence/identity field;
- consume existing private raw evidence before requesting another field action;
- repeat the observation only when the original completion cannot yield a valid capture.

## Proof ceiling

This plan records the operator's completion report and prevents replay. It does not prove the observed firmware value, version domain, `BASELINE_LOCKED`, restore readiness, mutation authority, deployment, or runtime success. Those states require the local private classifier/baseline receipts.

## Copy-paste local-agent handoff

```text
CONTINUE Kiosk4 firmware evidence ingestion from SysAdminSuite main@322cede1900ce4232d4f980e74d791dbe8acabeb.

P82 disposition:
The operator reports the authorized read-only Kiosk4 observation is FINISHED.
Do NOT repeat the observation merely because Git/Drive does not contain the private local capture.
The experiment action is complete; evidence ingestion is the open gate.

P04 disposition:
Graph width is 1 until the private observation is recovered and baseline is decided.
Owned lane: recover -> validate -> classify -> baseline -> sanitized durable state.
No firmware/device mutation.

First recover:
%TEMP%\hh-cc-kiosk4-labeled-firmware-observation.json
and relevant registered ignored receipts under survey/output/hh-cc-reader/.

Do not ask the operator to restate recoverable data.
Do not copy live identity, credentials, sessions, or private URLs into Git.

Refresh origin/main first and preserve dirty/separately owned work.

Then run:
Classify-HHCCReaderVersionDomain.cmd --input "%TEMP%\hh-cc-kiosk4-labeled-firmware-observation.json" --output "%TEMP%\hh-cc-kiosk4-version-domain-iter2.json"

Read the receipt and bind current_firmware_value only from an authoritative classifier result.

Construct private %TEMP%\hh-cc-kiosk4-baseline-input.json from the existing SAME-KIOSK4 identity receipt plus:
- source_serial
- expected_mac
- classified current_firmware_value
- governed target_firmware_value
- identity_proof_state=UNIQUE_TARGET_RESOLVED

Then run:
Evaluate-HHCCReaderFirmwareRoundtrip.cmd baseline --input "%TEMP%\hh-cc-kiosk4-baseline-input.json" --output "%TEMP%\hh-cc-kiosk4-baseline-iter2.json"

Read back the baseline receipt.
Report BASELINE_LOCKED or exact BASELINE_INCOMPLETE missing_fields.
Keep mutation_authorized=false.

If BASELINE_LOCKED, next P04 factor is package/domain mapping -> live restore proof -> explicit authority -> one controlled update -> post-update observation -> restoration/roundtrip.
If incomplete, repair only the exact missing evidence and consume existing private raw evidence before requesting another field action.

Return exact private artifact paths, typed states, sanitized durable commit/PR if any, tests, git/provider state, and proof ceiling.
```
