# AutoLogon Physical Pilot Readiness Checklist

## Purpose

This checklist defines what must be in place before a physical AutoLogon pilot runs on real shared workstations. It is the bridge between static contract tests (which prove the code is structurally correct) and live deployment (which proves the code works on real hardware).

## Pre-pilot prerequisites

### 1. Repository readiness

- [ ] PR #167 (autologon-state-delta) is merged to main
- [ ] PR #168 (autologon-deployment-workflow) is merged to main (or conflicts resolved)
- [ ] PR #175 (autodidact-install-capsule) is merged to main (or catalog adopted)
- [ ] This PR (autologon-final-step-gate) is merged to main
- [ ] All Pester tests pass on main
- [ ] All Python contract tests pass on main
- [ ] `Test-SasHostEligibility.ps1` exists on main (from Sprint 1)
- [ ] `configs/software-packages/approved-apps.json` exists on main with `autologon` entry

### 2. Target workstation readiness

- [ ] Target workstations are in the `Managed_Shared` OU
- [ ] AD user accounts exist for each target hostname (short name mapping)
- [ ] PostInstall registry key `HKLM\SOFTWARE\NSLIJHS\PostInstall` contains `SetAutoLogon` = `Autologon_YES`
- [ ] Target workstations are reachable via admin share (`\\HOST\c$`)
- [ ] Target workstations have been assessed (autologon_assessment.csv shows `intent_only` or `setup_incomplete`)

### 3. Operator readiness

- [ ] Operator is logged in with admin context
- [ ] `Run-AutoLogonStateDelta.cmd` launcher works on admin box
- [ ] `configs/software-packages/approved-apps.json` is present and valid
- [ ] `Config/host-eligibility-policy.local.json` includes target hostnames (or policy is absent for fail-closed test)
- [ ] Approved target CSV exists (e.g., `targets/local/autologon-pilot.csv`)
- [ ] Technician label is prepared (e.g., `pilot-wave-1`)

### 4. Package readiness

- [ ] `NW_AutoLogon_Setup_x64.exe` is pinned in `approved-apps.json`
- [ ] Package is accessible from the approved share (`\\nt2kwb972sms01\packages\AutoLogonSetup\`)
- [ ] Vendor-validated installer arguments are documented (or empty array is intentional)

## Pilot execution sequence

### Step 1: Capture Before state

```powershell
.\scripts\Start-SasAutoLogonStateDelta.ps1 `
  -Action Before `
  -TargetsCsv targets\local\autologon-pilot.csv `
  -TechnicianLabel pilot-wave-1
```

Verify:
- `run_manifest_before.json` exists in the output directory
- Phase is `before_complete`
- All target hostnames are in the `targets` array

### Step 2: Run final-step gate

```powershell
$gateResult = .\scripts\Invoke-SasAutoLogonFinalStepGate.ps1 `
  -Target TARGET_HOSTNAME `
  -RunId AUTLOGON_DELTA_RUNID `
  -BeforeSnapshotPath survey\output\autologon_state_delta\RUNID\run_manifest_before.json `
  -ApprovedAppsPath configs\software-packages\approved-apps.json `
  -OutputRoot survey\output\autologon_state_delta `
  -TechnicianLabel pilot-wave-1
```

Verify:
- `overall_pass` is `true`
- All 4 mandatory prerequisites passed
- `autologon_final_step_gate.json` is written

### Step 3: Execute approved software install

```powershell
.\scripts\Invoke-SasSoftwareInstall.ps1 `
  -ComputerName TARGET_HOSTNAME `
  -PackageName autologon `
  -InstallerRelativePath AutoLogonSetup\NW_AutoLogon_Setup_x64.exe `
  -SoftwareShareRoot \\nt2kwb972sms01\ `
  -InstallMode CopyThenInstall `
  -OutputRoot survey\output\software_install `
  -AllowTargetMutation
```

Verify:
- Install summary shows success
- No staging artifacts remain on target after cleanup

### Step 4: Capture After state

```powershell
.\scripts\Start-SasAutoLogonStateDelta.ps1 `
  -Action After `
  -ComputerName TARGET_HOSTNAME `
  -RunId AUTLOGON_DELTA_RUNID
```

Verify:
- `run_manifest_after.json` exists
- Phase is `after_complete`

### Step 5: Review state delta

```powershell
.\scripts\Invoke-SasAutoLogonStateDelta.ps1 `
  -Mode Assess `
  -ComputerName TARGET_HOSTNAME `
  -RunId AUTLOGON_DELTA_RUNID
```

Verify:
- Decision is `CONFIRMED_STATE_TRANSITION` (not `NO_MATERIAL_CHANGE` or `REGRESSION_REVIEW`)
- Before/After snapshots show expected registry changes

## Failure recovery

| Failure | Recovery |
|---|---|
| Gate `overall_pass` is false | Check which prerequisite failed; fix the issue; re-run gate |
| Before snapshot missing target | Re-run Before capture with correct target list |
| Install fails on target | Check target reachability, admin share, package availability |
| After snapshot shows no change | Installer may not have run; check install summary |
| State delta shows regression | Do NOT proceed; investigate; escalate |

## Post-pilot evidence

After the pilot, collect:

1. `autologon_final_step_gate.json` — gate result
2. `run_manifest_before.json` — Before state
3. `run_manifest_after.json` — After state
4. `software_install_summary.json` — install result
5. `autologon_assessment.csv` — pre-pilot assessment

These artifacts stay in gitignored local output. Do not commit them to the repository.
