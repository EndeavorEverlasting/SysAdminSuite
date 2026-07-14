# AutoLogon deployment workflow

## Purpose

This workflow deploys the approved auto-logon package from the approved read-only software share while preserving a reviewable before/install/after evidence chain on the admin box.

The pilot also uses `Invoke-SasAutoLogonFileAccessPosture.ps1` to inspect bounded NTFS ACL signals, the expected AutoLogon profile, shell-folder redirection, and mapped-drive metadata before and after deployment. That companion lane is required because correct registry state does not prove that the resulting user can use required local application directories or the intended file-share roundabout.

The final access gate uses `Invoke-SasAutoLogonSessionAccessProof.ps1` inside the real signed-in AutoLogon session. That current-token proof opens the exact required local/share paths and, when explicitly authorized, creates and immediately removes one unique marker in each path.

Canonical package:

```text
\\nt2kwb972sms01\packages\AutoLogonSetup\NW_AutoLogon_Setup_x64.exe
```

Entrypoint:

```text
scripts\Invoke-SasAutoLogonDeployment.ps1
```

Companion access-posture entrypoint:

```text
scripts\Invoke-SasAutoLogonFileAccessPosture.ps1
```

Current-token runtime proof entrypoint:

```text
scripts\Invoke-SasAutoLogonSessionAccessProof.ps1
```

The workflow composes existing SysAdminSuite contracts instead of creating another installer engine:

```text
explicit target list
  -> request-only approved-source and relative-path preflight
  -> read-only baseline snapshot
  -> skip baseline failures
  -> skip workstations already configured
  -> install eligible targets through Invoke-SasSoftwareInstall.ps1
  -> read-only after snapshot
  -> per-workstation state delta
  -> combined local JSONL, JSON, and operator handoff
```

The pilot evidence sequence adds:

```text
same explicit target list
  -> read-only file-access Before capture
  -> AutoLogon deployment workflow
  -> read-only file-access After capture
  -> ACL/profile/redirection/mapped-drive delta
  -> reboot and visible AutoLogon sign-in
  -> current-token local/share open and write/cleanup proof
  -> real application read/write/save test
```

The package preflight uses the existing software-install wrapper with `-WhatIf`. It validates the approved UNC root, relative installer path, target ceiling, and local output boundary before the state-delta collector can contact a workstation. A typo or unapproved source therefore fails locally instead of creating avoidable target reads.

## Why this does not use the Startup folder

A command in a Startup folder is a persistence mechanism and leaves a target-side script until a user logs on. It also makes execution identity, timing, cleanup, and administrative evidence less predictable.

This workflow uses the existing `CopyThenInstall` mode by default:

- the admin box reads the approved share;
- the installer is copied into a run-specific `%ProgramData%\SysAdminSuite\SoftwareInstall\<run_id>` directory;
- the existing install wrapper launches the installer;
- SysAdminSuite-owned staging is removed after the installer exits;
- cleanup failures and possible remnants are reported;
- installer-owned changes and normal Windows, endpoint, and application evidence are preserved.

No Startup-folder CMD, Run key, scheduled task, service, hidden listener, or background agent is created.

## Safety gates

- Explicit target names only.
- Maximum 25 targets per invocation.
- Approved source and relative installer path are validated locally before any baseline target read.
- No install when baseline collection fails.
- No reinstall when baseline already reports `autologon_ready`.
- Live execution requires `-AllowTargetMutation`.
- Live execution requires explicit vendor-validated `-InstallerArguments`.
- The source root must match the approved root in `harness/api/sas-harness-api.json`.
- `-WhatIf` performs request validation only: no share read, target read, remote session, copy, or installer execution.
- `-FixtureMode` performs offline end-to-end contract proof with synthetic state and a planned install.
- File-access posture accepts at most 12 operator-supplied absolute target-local directories.
- File-access posture rejects UNC paths, wildcards, relative paths, and parent traversal.
- File-access posture records share redirection and mapped-drive metadata without contacting those shares or enumerating directory contents.
- ACL signals do not claim effective access; actual user-session access remains a runtime gate.
- Session access proof accepts at most 12 explicit drive-rooted or complete UNC paths.
- Session access proof verifies the current Windows identity before contacting a path and never impersonates another account.
- Session write proof requires `-AllowWriteProbe`, uses `FileMode.CreateNew`, and immediately removes its unique marker.
- Session access retries are bounded; no continuous monitor, scheduled task, service, or background agent is created.
- SysAdminSuite evidence remains under the gitignored admin-box output root.
- `DefaultPassword` data is never collected.
- Event logs, monitoring, endpoint tooling, and installer evidence are not suppressed or cleared.

## Target CSV

Create a local, uncommitted file such as `targets\local\autologon-pilot.csv`:

```csv
ComputerName
WORKSTATION001
WORKSTATION002
```

Start with two approved pilot workstations. Do not put credentials or passwords in the CSV.

## 1. Offline end-to-end proof

This does not contact the share or any workstation:

```powershell
.\scripts\Invoke-SasAutoLogonDeployment.ps1 `
  -ComputerName SAMPLE001 `
  -FixtureMode
```

Expected status:

```text
FIXTURE_PASS
```

Also prove the file-access companion offline:

```powershell
$accessBefore = .\scripts\Invoke-SasAutoLogonFileAccessPosture.ps1 `
  -Mode Before `
  -ComputerName SAMPLE001 `
  -PermissionPath 'C:\ProgramData\VendorApp' `
  -FixtureMode

.\scripts\Invoke-SasAutoLogonFileAccessPosture.ps1 `
  -Mode After `
  -RunId $accessBefore.run_id `
  -ComputerName SAMPLE001 `
  -PermissionPath 'C:\ProgramData\VendorApp' `
  -FixtureMode
```

The synthetic access delta should report `ACCESS_POSTURE_IMPROVED`, one UNC shell-folder redirection, and one mapped drive while recording:

```text
path_contents_enumerated: false
share_paths_contacted: false
effective_access_proven: false
```

Also prove the current-token session contract offline:

```powershell
$sessionFixture = .\scripts\Invoke-SasAutoLogonSessionAccessProof.ps1 `
  -ExpectedUserName SAMPLE001 `
  -Path @('C:\ProgramData\VendorApp', '\\fileserver\roundabout') `
  -AllowWriteProbe `
  -FixtureMode `
  -Confirm:$false
```

Expected fixture posture:

```text
decision: SESSION_ACCESS_CONFIRMED
runtime_proof: false
path_contents_recorded: false
credentials_collected: false
impersonation_used: false
```

Expected local deployment artifacts:

```text
survey\output\autologon_deployment\<workflow_id>\
  autologon_deployment_events.jsonl
  autologon_deployment_summary.json
  operator_handoff.txt
  state\
  install\
```

The summary includes `request_preflight`, which records the no-network package-plan result completed before the synthetic baseline.

## 2. Request-only dry run for the real pilot manifest

This validates target intake, approved source resolution, relative-path safety, output boundaries, and install planning without contacting the share or workstations:

```powershell
.\scripts\Invoke-SasAutoLogonDeployment.ps1 `
  -TargetsCsv .\targets\local\autologon-pilot.csv `
  -InstallerRelativePath 'packages\AutoLogonSetup\NW_AutoLogon_Setup_x64.exe' `
  -InstallMode CopyThenInstall `
  -WhatIf
```

Expected status:

```text
PLANNED_WHATIF
```

An unapproved `-SoftwareShareRoot`, rooted installer path, or `..` traversal is rejected here and is also revalidated before baseline collection during fixture and live modes.

## 3. Verify silent installer arguments

Before live execution, validate the executable's supported silent switches from the approved package owner, vendor documentation, or a controlled local test. Do not assume that `/quiet /norestart` is accepted by every EXE.

The live workflow deliberately refuses to run when `-InstallerArguments` is omitted.

## 4. Two-workstation approved pilot

### Capture file-access Before posture

Use the same approved manifest and name the local directories the AutoLogon user actually needs:

```powershell
$accessBefore = .\scripts\Invoke-SasAutoLogonFileAccessPosture.ps1 `
  -Mode Before `
  -TargetsCsv .\targets\local\autologon-pilot.csv `
  -PermissionPath @(
    'C:\ProgramData\VendorApp',
    'C:\Northwell'
  ) `
  -TechnicianLabel 'AutoLogon pilot'

$accessRunId = $accessBefore.run_id
```

Do not put file shares in `-PermissionPath`. The collector inspects target-local ACL metadata only. Existing user-shell-folder redirects and mapped drives are recorded from the loaded profile registry without contacting the remote path.

### Run the deployment

Replace the example arguments with the validated switches:

```powershell
.\scripts\Invoke-SasAutoLogonDeployment.ps1 `
  -TargetsCsv .\targets\local\autologon-pilot.csv `
  -InstallerRelativePath 'packages\AutoLogonSetup\NW_AutoLogon_Setup_x64.exe' `
  -InstallerArguments @('<validated-silent-switch-1>', '<validated-silent-switch-2>') `
  -InstallMode CopyThenInstall `
  -TechnicianLabel 'AutoLogon pilot' `
  -AllowTargetMutation `
  -Confirm:$false
```

The workflow will:

1. validate the approved source and relative path without contacting a workstation;
2. capture baseline evidence;
3. exclude failed baselines and already-configured workstations;
4. install only eligible workstations;
5. clean and report SysAdminSuite-owned staging;
6. capture after evidence;
7. emit the combined summary and per-workstation delta.

### Capture file-access After posture

Reuse the same file-access run ID, target manifest, and path list:

```powershell
.\scripts\Invoke-SasAutoLogonFileAccessPosture.ps1 `
  -Mode After `
  -RunId $accessRunId `
  -TargetsCsv .\targets\local\autologon-pilot.csv `
  -PermissionPath @(
    'C:\ProgramData\VendorApp',
    'C:\Northwell'
  ) `
  -TechnicianLabel 'AutoLogon pilot'
```

Review the file-access summary and each target delta before rebooting:

```text
survey\output\autologon_file_access\<access_run_id>\autologon_file_access_summary.json
survey\output\autologon_file_access\<access_run_id>\delta\<target>.json
```

### Prove access from the real AutoLogon session

Reboot each pilot workstation and directly observe the expected AutoLogon account sign in. Open
PowerShell inside that exact session. Do not use an administrator session, `runas`, alternate
credentials, PowerShell remoting, a service, or a scheduled task.

Run the proof against the exact local application locations and file-share roundabouts required by
the workflow:

```powershell
$sessionProof = & '\\approved-server\approved-tools\scripts\Invoke-SasAutoLogonSessionAccessProof.ps1' `
  -Path @(
    'C:\ProgramData\VendorApp',
    'Z:\OperationalData',
    '\\approved-fileserver\approved-share\OperationalData'
  ) `
  -RetryCount 3 `
  -RetryDelaySeconds 5 `
  -AllowWriteProbe `
  -Enforce `
  -Confirm:$false

$sessionProof | ConvertTo-Json -Depth 12
```

The proof must report:

```text
identity_match: true
decision: SESSION_ACCESS_CONFIRMED
runtime_proof: true
failed_path_count: 0
credentials_collected: false
impersonation_used: false
```

Confirm that no `.sas-autologon-access-*.tmp` marker remains in any tested location. Then run the
real application and complete its required open/read/write/save workflow.

## 5. Review before expansion

Open:

```text
survey\output\autologon_deployment\<workflow_id>\operator_handoff.txt
survey\output\autologon_deployment\<workflow_id>\autologon_deployment_summary.json
survey\output\autologon_file_access\<access_run_id>\operator_handoff.txt
survey\output\autologon_file_access\<access_run_id>\autologon_file_access_summary.json
```

Expansion gates:

- request preflight succeeded under the approved source root;
- no baseline collection failures;
- no install failures;
- no cleanup failures;
- no SysAdminSuite-owned target remnants;
- expected `CONFIRMED_STATE_TRANSITION` or justified `ALREADY_CONFIGURED_BEFORE`;
- no `PARTIAL_CHANGE_REVIEW`, `REGRESSION_REVIEW`, or `INCONCLUSIVE`;
- file-access Before and After captures succeeded for the same targets and path list;
- no unexpected `explicit_deny_review`, missing required path, or `acl_unavailable` result;
- expected profile and required local application directories have understood ACL grant signals;
- intended shell-folder redirection and mapped-drive metadata are present when the design relies on file shares;
- at least one real reboot and observed successful auto-logon on each pilot workstation;
- current-session identity matches the expected hostname-based AutoLogon account;
- every required local, mapped-drive, and UNC path reports `ACCESS_CONFIRMED`;
- session-level decision is `SESSION_ACCESS_CONFIRMED` with `runtime_proof: true`;
- no `.sas-autologon-access-*.tmp` marker remains;
- the real AutoLogon session can open the application and complete the required read/write/save workflow.

The registry and installed-software delta proves workstation configuration state. The ACL/profile snapshot proves recorded access posture. The current-token proof establishes directory and share authentication under the actual AutoLogon identity. The application test establishes the real user workflow. None of these alone proves the identity of the technician who performed the deployment.

## Operational notes

- `CopyThenInstall` avoids the common remote UNC second-hop problem while retaining the server as the approved package source.
- `UncDirect` is available when target-side access to the share is already proven.
- The administrative file-access collector does not test share availability because its remote token is not the AutoLogon user's token and may encounter second-hop behavior.
- The session access proof intentionally contacts only its explicit paths under the current signed-in token; it accepts no credentials and performs no impersonation.
- Mapped drives and UNC paths may become available after logon delay. Use only the bounded retry controls; do not create a continuous watcher.
- The installer may create its own files, logs, services, tasks, registry values, caches, or reboot requirements. Those are installer-owned and outside SysAdminSuite staging cleanup.
- The workflow does not reboot targets automatically.
- A completed install exit code, registry delta, ACL allow signal, or mapped-drive registry entry is not a substitute for the current-token proof and the real application workflow.
