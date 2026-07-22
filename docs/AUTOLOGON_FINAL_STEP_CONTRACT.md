# AutoLogon Final-Step Contract

## Purpose

AutoLogon is a **product-configuration mutation**, not a read-only survey. It modifies Winlogon registry keys to configure automatic logon on shared workstations. This contract defines the mandatory prerequisites that must be satisfied before the AutoLogon installer may execute.

The final-step gate exists because:

1. AutoLogon changes are **irreversible without manual intervention** — once Winlogon is configured, the workstation behaves differently on every reboot.
2. AutoLogon changes are **security-sensitive** — they affect who logs in automatically and how credentials are stored.
3. AutoLogon changes must be **traceable** — every mutation must have a corresponding Before snapshot, a technician label, and a run ID.

## When this gate applies

The final-step gate must be called before any of the following:

- the canonical `Invoke-SasAutoLogonDeployment.ps1` application before it reaches its validated deployment front door
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

The standalone gate writes operator-local detail beneath the ignored state-delta output. Canonical
deployment normalizes that detail to `artifacts/autologon_final_step_gate_result.json` with schema
`sas-autologon-final-step-gate-result/v1`. The normalized object exposes classification, reason codes,
prerequisite IDs and booleans, privacy flags, proof level, and proof ceiling without a target identifier.
Do not copy raw operator-local gate evidence into documentation or public reports.

## Standalone fixture and diagnostic usage

The normal live operator does not compose these commands; `Invoke-SasAutoLogonDeployment.ps1` owns the
Before capture and final-step gate. The standalone surface remains for focused fixture validation and
approved diagnosis.

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
1. Canonical request and fresh Kerberos/SMB preflight validation
2. Before snapshot (read-only)
3. Host eligibility and approved-catalog prerequisites
4. FINAL-STEP GATE (this script; overall_pass must be true)
5. Invoke-SasValidatedSoftwareDeployment.ps1 (canonical mutation front door)
6. Kerberos/SMB scheduled-task result retrieval and run-scoped cleanup
7. After snapshot and normalized state proof (read-only)
8. Public-safe result presentation (runtime remains pending)
```

The application owns this order. The older `Invoke-SasSoftwareInstall.ps1` surface may remain behind the
generic validated front door as compatibility code, but it is not a direct AutoLogon command authority.
The final-step gate is the **single point** where all prerequisites are validated before mutation.

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
| `scripts/Invoke-SasAutoLogonStateDelta.ps1` | Read-only state-delta collector |
| `scripts/Start-SasAutoLogonStateDelta.ps1` | Stateful technician launcher |
| `scripts/Test-SasHostEligibility.ps1` | Host eligibility gate (Sprint 1) |
| `configs/software-packages/approved-apps.json` | Approved software catalog |
| `docs/AUTOLOGON_ASSESSMENT.md` | AutoLogon assessment lifecycle |
| `docs/AUTOLOGON_STATE_DELTA.md` | State-delta workflow documentation |
| `docs/SOFTWARE_INSTALL_HARNESS.md` | Admin software install harness |
| `docs/AUTOLOGON_UNIQUE_BEHAVIOR_MATRIX.md` | Unique-behavior reconciliation |
| `docs/AUTOLOGON_PHYSICAL_PILOT_CHECKLIST.md` | Pre-pilot readiness checklist |

## Unique-Behavior Reconciliation

This gate reconciles the state-delta, deployment-workflow, and approved-catalog behavior. See `AUTOLOGON_UNIQUE_BEHAVIOR_MATRIX.md` for the full matrix.

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
