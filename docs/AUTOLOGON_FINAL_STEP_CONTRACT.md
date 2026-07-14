# AutoLogon Final-Step Contract

## Purpose

AutoLogon is a **product-configuration mutation**, not a read-only survey. It modifies Winlogon registry keys to configure automatic logon on shared workstations. This contract defines the mandatory prerequisites that must be satisfied before the AutoLogon installer may execute.

The final-step gate exists because:

1. AutoLogon changes are **irreversible without manual intervention** — once Winlogon is configured, the workstation behaves differently on every reboot.
2. AutoLogon changes are **security-sensitive** — they affect who logs in automatically and how credentials are stored.
3. AutoLogon changes must be **traceable** — every mutation must have a corresponding Before snapshot, a technician label, and a run ID.

## When this gate applies

The final-step gate must be called before any of the following:

- `Invoke-SasSoftwareInstall.ps1` with the `autologon` package
- `Start-SasAutoLogonStateDelta.ps1` in `After` mode
- Any direct Winlogon registry mutation for auto-logon configuration
- `NW_AutoLogon_Setup_x64.exe` execution on a target workstation

The gate does **not** apply to:

- Read-only AutoLogon assessment (`Invoke-SasAutoLogonStateDelta.ps1` in `Before` or `Assess` mode)
- Read-only state-delta comparison
- Fixture-mode synthetic tests (unless explicitly opted in)

## Mandatory prerequisites

| # | Prerequisite | ID | Check |
|---|---|---|---|
| 1 | **Run ID format** | `run_id_format` | Run ID matches `autologon-delta-YYYYMMDD-HHMMSS-XXXXXXXX` |
| 2 | **Host eligibility** | `host_eligibility` | Target hostname passes `Test-SasHostEligibility.ps1` for `local` execution context |
| 3 | **Approved catalog** | `approved_catalog` | `autologon` package exists in `configs/software-packages/approved-apps.json` with `install_enabled=true` and a pinned `installer_file` |
| 4 | **Before snapshot** | `before_snapshot` | State-delta Before snapshot exists for this run ID and contains the target hostname |

## Recommended prerequisites

| # | Prerequisite | ID | Check |
|---|---|---|---|
| 5 | **Runtime proof** | `runtime_proof` | Technician runtime proof JSON exists for this run |
| 6 | **File access posture** | `file_access_posture` | File access posture verified (delegated to deployment workflow) |

Recommended prerequisites do **not** block execution. They are recorded in the gate result for audit purposes.

## Failure classifications

| Prerequisite | Failure mode | Classification | Recovery |
|---|---|---|---|
| `run_id_format` | Malformed or missing run ID | **BLOCKED** — operator error | Generate a valid run ID |
| `host_eligibility` | Host not in policy, policy missing, policy malformed | **BLOCKED** — safety gate | Add host to eligibility policy or choose eligible target |
| `approved_catalog` | Package not in catalog, `install_enabled=false`, no pinned installer | **BLOCKED** — package not approved | Add package to catalog or pin installer filename |
| `before_snapshot` | Snapshot missing, wrong run ID, target not in snapshot | **BLOCKED** — evidence missing | Capture Before snapshot first |
| `runtime_proof` | Proof file missing | **WARN** — not blocking | Capture runtime proof (recommended) |
| `file_access_posture` | Posture not verified | **WARN** — not blocking | Verify file access posture (recommended) |

## Gate result structure

The gate produces a JSON result at `survey/output/autologon_state_delta/<run_id>/autologon_final_step_gate.json`:

```json
{
  "gate_id": "autologon-final-step",
  "gate_version": "1.0.0",
  "target": "SAMPLE301MSO001",
  "run_id": "autologon-delta-20260714-143000-1a2b3c4d",
  "timestamp_utc": "2026-07-14T14:30:00.0000000Z",
  "technician_label": "pilot-wave-1",
  "fixture_mode": false,
  "prerequisites": [
    {
      "id": "run_id_format",
      "description": "Run ID matches autologon-delta format",
      "passed": true,
      "mandatory": true,
      "detail": "Run ID 'autologon-delta-20260714-143000-1a2b3c4d' is valid"
    },
    {
      "id": "host_eligibility",
      "description": "Target host is eligible for package execution",
      "passed": true,
      "mandatory": true,
      "detail": "Host 'SAMPLE301MSO001' is eligible for local execution context"
    },
    {
      "id": "approved_catalog",
      "description": "Autologon package exists in approved software catalog",
      "passed": true,
      "mandatory": true,
      "detail": "Package 'autologon' found: NW AutoLogon Setup x64, installer=NW_AutoLogon_Setup_x64.exe"
    },
    {
      "id": "before_snapshot",
      "description": "State-delta Before snapshot captured for this run",
      "passed": true,
      "mandatory": true,
      "detail": "Before snapshot validated for run 'autologon-delta-20260714-143000-1a2b3c4d', target 'SAMPLE301MSO001'"
    }
  ],
  "overall_pass": true,
  "blocked_reason": null
}
```

## Usage

### Prerequisite check (before installer)

```powershell
.\scripts\Invoke-SasAutoLogonFinalStepGate.ps1 `
  -Target SAMPLE301MSO001 `
  -RunId autologon-delta-20260714-143000-1a2b3c4d `
  -BeforeSnapshotPath survey\output\autologon_state_delta\autologon-delta-20260714-143000-1a2b3c4d\run_manifest_before.json `
  -ApprovedAppsPath configs\software-packages\approved-apps.json `
  -OutputRoot survey\output\autologon_state_delta `
  -TechnicianLabel pilot-wave-1
```

### With recommended checks

```powershell
.\scripts\Invoke-SasAutoLogonFinalStepGate.ps1 `
  -Target SAMPLE301MSO001 `
  -RunId autologon-delta-20260714-143000-1a2b3c4d `
  -BeforeSnapshotPath survey\output\autologon_state_delta\autologon-delta-20260714-143000-1a2b3c4d\run_manifest_before.json `
  -ApprovedAppsPath configs\software-packages\approved-apps.json `
  -OutputRoot survey\output\autologon_state_delta `
  -TechnicianLabel pilot-wave-1 `
  -RequireRuntimeProof `
  -RequireFileAccessPosture
```

### Fixture mode (CI testing)

```powershell
.\scripts\Invoke-SasAutoLogonFinalStepGate.ps1 `
  -Target SAMPLE001 `
  -RunId autologon-delta-20260714-143000-1a2b3c4d `
  -BeforeSnapshotPath tests\fixtures\autologon_before_snapshot.json `
  -ApprovedAppsPath configs\software-packages\approved-apps.json `
  -HostEligibilityPolicyPath tests\fixtures\host-eligibility-policy-test.json `
  -ExecContext fixture `
  -OutputRoot survey\output\autologon_state_delta `
  -FixtureMode
```

## Integration sequence

The full AutoLogon deployment sequence is:

```
1. Assessment (read-only)
   survey/sas-assess-autologon.sh --manifest targets.csv
   -> autologon_assessment.csv
   -> identifies intent_only, setup_incomplete, autologon_ready

2. Host eligibility check
   scripts/Test-SasHostEligibility.ps1 -Target HOSTNAME -ExecContext local
   -> eligible / not_eligible

3. Before snapshot (read-only)
   scripts/Start-SasAutoLogonStateDelta.ps1 -Action Before -ComputerName HOSTNAME
   -> run_manifest_before.json

4. FINAL-STEP GATE (this script)
   scripts/Invoke-SasAutoLogonFinalStepGate.ps1 -Target HOSTNAME -RunId RUNID
   -> autologon_final_step_gate.json
   -> overall_pass must be true

5. Approved software install (mutation)
   scripts/Invoke-SasSoftwareInstall.ps1 -ComputerName HOSTNAME -InstallerRelativePath ...
   -> install execution

6. After snapshot (read-only)
   scripts/Start-SasAutoLogonStateDelta.ps1 -Action After -ComputerName HOSTNAME
   -> run_manifest_after.json

7. State delta comparison (read-only)
   scripts/Invoke-SasAutoLogonStateDelta.ps1 -Mode Assess -ComputerName HOSTNAME
   -> delta decision: CONFIRMED_STATE_TRANSITION, NO_MATERIAL_CHANGE, etc.
```

The final-step gate (step 4) is the **single point** where all prerequisites are validated before the mutation (step 5) occurs.

## Safety

- The gate is **fail-closed** — when mandatory prerequisites fail, execution is blocked.
- There is **no override** — no `-Force`, environment variable, or undocumented path bypasses a failed gate.
- The gate **never reads DefaultPassword** — it only checks catalog and snapshot existence.
- The gate **never contacts the target** — it only validates local evidence and configuration.
- Gate results are written to **gitignored local output** only.

## Related files

| File | Role |
|---|---|
| `scripts/Invoke-SasAutoLogonFinalStepGate.ps1` | Prerequisite validator |
| `scripts/Invoke-SasAutoLogonStateDelta.ps1` | Read-only state-delta collector (PR #167) |
| `scripts/Start-SasAutoLogonStateDelta.ps1` | Stateful technician launcher (PR #167) |
| `scripts/Test-SasHostEligibility.ps1` | Host eligibility gate (Sprint 1) |
| `configs/software-packages/approved-apps.json` | Approved software catalog (PR #175) |
| `docs/AUTOLOGON_ASSESSMENT.md` | AutoLogon assessment lifecycle |
| `docs/AUTOLOGON_STATE_DELTA.md` | State-delta workflow documentation |
| `docs/SOFTWARE_INSTALL_HARNESS.md` | Admin software install harness |
| `docs/AUTOLOGON_UNIQUE_BEHAVIOR_MATRIX.md` | Reconciliation of PRs #167, #168, #175 |
| `docs/AUTOLOGON_PHYSICAL_PILOT_CHECKLIST.md` | Pre-pilot readiness checklist |

## Unique-Behavior Reconciliation

This gate reconciles unique behavior from PRs #167, #168, and #175. See `AUTOLOGON_UNIQUE_BEHAVIOR_MATRIX.md` for the full matrix.

**Key invariants:**
1. AutoLogon is the **final mutation** — no other mutations after AutoLogon
2. Package validation and application acceptance must pass before AutoLogon mutation
3. Required reboots must complete before AutoLogon baseline is captured
4. Post-reboot proof is required — technician must observe and record AutoLogon behavior

## Refusal Classifications

| Refusal | Classification | Recovery |
|---------|---------------|----------|
| `run_id_format` invalid | **BLOCKED** — operator error | Generate valid run ID |
| `host_eligibility` failed | **BLOCKED** — safety gate | Add host to policy or choose eligible target |
| `approved_catalog` missing | **BLOCKED** — package not approved | Add package to catalog or pin installer |
| `before_snapshot` missing | **BLOCKED** — evidence missing | Capture Before snapshot first |
| `application_acceptance` not confirmed | **BLOCKED** — prerequisite incomplete | Complete application acceptance extraction |
| `required_reboot` pending | **BLOCKED** — reboot required | Complete required reboot and verify |
| `runtime_proof` missing | **WARN** — not blocking | Capture runtime proof (recommended) |
| `file_access_posture` not verified | **WARN** — not blocking | Verify file access posture (recommended) |
