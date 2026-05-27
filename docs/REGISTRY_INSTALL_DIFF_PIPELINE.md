# Registry Install Diff Pipeline

## Purpose

The Registry Install Diff Pipeline defines an **evidence-first** workflow for measuring Windows registry changes associated with software installation activity. Its primary goal is to produce reviewable evidence bundles, not to perform blind registry editing.

This contract supports:

- Selecting a single target or a target batch.
- Checking target readiness before action.
- Reading installer metadata from the repository software source posture, including `Config/sources.yaml`.
- Capturing registry state before install.
- Running tracked installer actions in dry-run or execution mode.
- Capturing registry state after install.
- Diffing before/after registry state.
- Classifying useful changes versus noise.
- Exporting evidence in JSON, CSV, Markdown, and log formats.
- Preserving evidence even when installer execution fails.

## Core Workflow

The mandatory operational sequence is:

**Recon -> Decide -> Act -> Log -> Export**

### 1) Recon

- Resolve targets (single target or batch).
- Validate local prerequisites and target readiness.
- Resolve software installer metadata from `Config/sources.yaml`.
- Confirm run mode and safety posture.
- Confirm default registry watch areas.

### 2) Decide

- Choose mode (`ReconOnly`, `SnapshotOnly`, `AnalyzeInstall`, `DiffOnly`, `ExportOnly`).
- Decide dry-run vs execution behavior for installer activity.
- Decide whether the run is localhost-first validation or explicitly gated future remote/batch behavior.
- Confirm that registry behavior remains read-only unless an explicitly gated future remediation lane is used.

### 3) Act

Main use case execution path:

1. Capture `registry_before` snapshot.
2. Run tracked installer from software source configuration.
3. Capture `registry_after` snapshot.
4. Diff before/after snapshots.
5. Classify diffs and produce evidence artifacts.

### 4) Log

- Log readiness checks, resolved software metadata, selected mode, and execution flags.
- Log installer invocation outcome, including failures and partial progress.
- Log snapshot timing and diff scope.
- Log classification summary and export paths.

### 5) Export

- Emit evidence bundle artifacts for review.
- Preserve artifacts even on partial failure.
- Support downstream auditing and human verification without requiring registry mutation.

## Main Use Case (Contract)

The baseline contract is:

**Registry before snapshot -> tracked install -> registry after snapshot -> diff -> evidence export**

The pipeline is not complete unless evidence artifacts are exported or explicitly preserved for a failed run.

## Default Registry Watch Areas

The first implementation documents and prioritizes these registry areas:

- `HKLM:\Software`
- `HKLM:\Software\WOW6432Node`
- `HKLM:\System\CurrentControlSet\Services`
- `HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall`

Additional paths may be added later, but this baseline scope must remain explicit in logs and summary output.

## Run Modes

### ReconOnly

- Resolve targets and software metadata.
- Perform readiness checks.
- No installer execution.
- No registry mutation.

### SnapshotOnly

- Capture registry snapshots according to configured scope.
- No installer execution.
- Useful for baseline collection and troubleshooting.

### AnalyzeInstall

- Full evidence pipeline mode.
- Snapshot before install, execute tracked installer (dry-run or execution mode), snapshot after install, diff and classify.

### DiffOnly

- Operate on existing snapshots.
- Perform comparison and classification.
- Useful for re-analysis and tuning noise filters.

### ExportOnly

- Export precomputed or cached run artifacts into standard evidence bundle layout.
- No installer execution.

### ApprovedRemediation (future gated mode)

- Not default.
- Not required to be implemented in this sprint.
- Must remain explicitly gated behind approved remediation controls if implemented later.

## Software Source Integration

The pipeline must integrate with existing repository posture for software source tracking.

- `Config/sources.yaml` is the canonical integration point for tracked installer metadata in this sprint.
- The pipeline must not introduce a competing parallel software source tracker unless unavoidable and explicitly documented.
- Resolved software identifiers and installer metadata must be logged into run evidence artifacts.

## Localhost-First Implementation Posture

The first implementation should prioritize localhost workflows:

- Validate read-only snapshot/diff/export behavior on localhost first.
- Validate dry-run installer path before execution path.
- Preserve evidence on both success and failure outcomes.

Remote and batch operation is future or explicitly gated work:

- Do not assume remote batch installs are production-ready in first implementation.
- Any remote/batch mode must be explicitly gated and documented with readiness constraints.

## Expected Evidence Bundle Layout

```text
exports/
  registry-install-diff/
    <timestamp>_<software_id>/
      run_manifest.json
      summary.md
      summary.csv
      targets/
        <target>/
          readiness.json
          registry_before.json
          registry_after.json
          registry_diff.json
          installer_result.json
          transcript.log
```

Evidence bundles are required for successful review and must be preserved for partial failures.

## Acceptance Criteria

The Registry Install Diff Pipeline contract is accepted when:

1. Workflow is documented as **Recon -> Decide -> Act -> Log -> Export**.
2. Main use case explicitly covers before snapshot, tracked install, after snapshot, diff, and evidence export.
3. Run modes are documented (`ReconOnly`, `SnapshotOnly`, `AnalyzeInstall`, `DiffOnly`, `ExportOnly`, and future-gated `ApprovedRemediation`).
4. Software source integration references existing repository posture and `Config/sources.yaml`.
5. Localhost-first posture is explicit.
6. Remote/batch behavior is treated as future or explicitly gated.
7. Evidence bundle structure is explicit and review-oriented.
8. Safety posture remains evidence-first and non-mutating by default.
