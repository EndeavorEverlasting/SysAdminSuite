# Active Directory OU Move Pilot

## Purpose

`ActiveDirectory/Move-Computers-To-OU.ps1` is the bounded administrator workflow for moving computer objects into an approved managed workstation OU. It is intentionally separate from `Add-Computers-To-PrintingGroup.ps1`: OU placement and security-group membership are different operations with different rollback and proof requirements.

This document is an administrator pilot runbook, **not** the eventual non-technical tutorial. Do not publish a one-click/CMD operator surface until the single-host move + rollback and a bounded batch have both been observed successfully in the real environment.

## Safety contract

- Default execution is plan-only; no `Move-ADObject` occurs unless `-Apply` is present.
- `-Apply` requires a `-ChangeReference` for audit/traceability. SysAdminSuite does **not** validate an external ticket/change system and that string is not an authorization boundary.
- The operator must obtain approval through the real organizational change/authorization process before any `-Apply` or rollback action. AD delegation/permissions remain the technical privilege boundary.
- The target must resolve to a real OU beneath `_Workstations\Managed` or `_Workstations\Managed_Shared`, matched on complete DN component boundaries.
- Legacy `_Workstations\Workstations` and `_Workstations\Shared_Workstations` targets are rejected.
- The default `-MaxChanges` is `1`.
- More than one planned move requires both a deliberately raised `-MaxChanges` and `-ConfirmBatch`.
- Any failed lookup or expected-source mismatch blocks the entire apply before mutation.
- The object is re-read immediately before mutation so source-OU drift fails closed.
- Every move is verified from AD before the next object is touched.
- After the first move/verification failure, later planned mutations are skipped.
- Local run evidence lives under `%LOCALAPPDATA%\SysAdminSuite\Cache\ActiveDirectory\OUMove` by default and is not repository data.
- `Undo-OUMove.ps1` is generated only for objects whose forward move was verified. Undo refuses to overwrite a later OU change: the object must still be in the expected pilot target OU before it can be restored.

## Gate 0 — establish the exact approved target

Do **not** reconstruct or guess the OU from memory. Obtain the approved distinguished name from the authoritative directory/change record and keep it operator-local, for example:

```powershell
$TargetOU = 'OU=ApprovedChild,OU=Managed,OU=_Workstations,DC=example,DC=com'
$ChangeReference = 'CHANGE-OR-TICKET-REFERENCE'
```

The example is synthetic. `ChangeReference` is recorded so the run can be reconciled to the real approval record; entering it does not cause SysAdminSuite to validate or grant that approval. Do not commit the real OU, ticket, hostname, or run artifacts.

## Gate 1 — read-only identity and source snapshot

Run from an administrator workstation with RSAT ActiveDirectory available:

```powershell
Import-Module ActiveDirectory
$PilotComputer = $env:COMPUTERNAME
$Pilot = Get-ADComputer -Identity $PilotComputer -Properties DistinguishedName,CanonicalName,ObjectGUID,OperatingSystem
$Pilot | Select-Object Name,ObjectGUID,OperatingSystem,DistinguishedName,CanonicalName
$SourceOU = ($Pilot.DistinguishedName -split '(?<!\\),',2)[1]
$SourceOU
```

Record the intended pilot hostname, `ObjectGUID`, and source OU in the approved operational record. The repository must remain free of those live values.

## Gate 2 — repository-owned plan

From the current SysAdminSuite repository root:

```powershell
.\ActiveDirectory\Move-Computers-To-OU.ps1 `
  -ComputerName $PilotComputer `
  -ExpectedSourceOU $SourceOU `
  -TargetOU $TargetOU
```

Expected result: `OU MOVE PLAN: 1 change(s) would be attempted.` (or `0` if the object is already there), plus local `Preflight.csv`, `Plan.json`, and result artifacts. **Stop** if the source, target, hostname, object GUID, or planned change is not exactly what was approved.

`-WhatIf` is an even narrower simulation and suppresses artifact writes:

```powershell
.\ActiveDirectory\Move-Computers-To-OU.ps1 `
  -ComputerName $PilotComputer `
  -ExpectedSourceOU $SourceOU `
  -TargetOU $TargetOU `
  -Apply `
  -ChangeReference $ChangeReference `
  -WhatIf
```

## Gate 3 — one-computer apply

Only after Gate 2 is correct and organizational approval exists:

```powershell
.\ActiveDirectory\Move-Computers-To-OU.ps1 `
  -ComputerName $PilotComputer `
  -ExpectedSourceOU $SourceOU `
  -TargetOU $TargetOU `
  -Apply `
  -ChangeReference $ChangeReference `
  -Confirm:$false
```

Acceptance requires all of the following:

1. terminal result reports exactly one `Moved` and zero failed;
2. `Results.json` records `moved_count = 1` and the operator-supplied change reference;
3. a fresh `Get-ADComputer` read places the same `ObjectGUID` in `$TargetOU`;
4. `Undo-OUMove.ps1` exists in that run directory.

A successful PowerShell process or a populated change-reference field alone is not proof of approval or OU placement.

## Gate 4 — rollback the pilot

An AD computer object cannot be left “outside an OU”; rollback means moving it back to the exact source OU captured before the pilot. Obtain any rollback approval required by the organization before executing the generated mutator.

Locate the just-completed run directory and execute its generated undo:

```powershell
$Run = Get-ChildItem "$env:LOCALAPPDATA\SysAdminSuite\Cache\ActiveDirectory\OUMove" -Directory |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

& (Join-Path $Run.FullName 'Undo-OUMove.ps1') `
  -ChangeReference $ChangeReference `
  -Confirm:$false
```

The generated undo prints the supplied change reference for traceability; it does not validate an external approval system.

Then independently verify:

```powershell
$AfterRollback = Get-ADComputer -Identity $PilotComputer -Properties DistinguishedName,ObjectGUID
$AfterRollback | Select-Object Name,ObjectGUID,DistinguishedName
(($AfterRollback.DistinguishedName -split '(?<!\\),',2)[1]) -eq $SourceOU
```

Acceptance: the same `ObjectGUID` is back under `$SourceOU`. If the object has moved somewhere else since the pilot, the undo script intentionally blocks rather than overwriting that newer placement.

## Gate 5 — bounded batch certification

Do not run this gate until Gates 1–4 have been observed successfully and recorded.

Create an operator-local host file with a deliberately small batch (recommended first batch: 2–3 machines). Plan it first:

```powershell
.\ActiveDirectory\Move-Computers-To-OU.ps1 `
  -HostListPath .\operator-local-hosts.txt `
  -TargetOU $TargetOU
```

Review every preflight row. Then apply with an explicit ceiling that exactly matches the approved batch size:

```powershell
.\ActiveDirectory\Move-Computers-To-OU.ps1 `
  -HostListPath .\operator-local-hosts.txt `
  -TargetOU $TargetOU `
  -Apply `
  -ChangeReference $ChangeReference `
  -MaxChanges 3 `
  -ConfirmBatch `
  -Confirm:$false
```

Do not set `-MaxChanges` higher than the approved batch. Any verification failure stops later mutations. Reconcile `Results.json` against fresh AD reads before increasing batch size.

## Gate 6 — technician CMD and tutorial

Only after the batch workflow is proven in the live environment should SysAdminSuite expose this mutation to non-technical users. That later sprint should follow the existing technician-front-door pattern:

1. repository-owned CMD launcher;
2. target/OU selection from approved local assignment or proven history instead of retyping;
3. plan shown before mutation;
4. explicit production confirmation and a change reference for traceability;
5. bounded local evidence and visible outcome;
6. rollback front door;
7. tutorial wired into SysAdminSuite discoverability;
8. no weakening of the engine's managed-OU, change-ceiling, verification, drift, or organizational-approval requirements.

## Proof ceilings

- Repository/Pester/CI proof: syntax and safety contracts only; **no live AD mutation and no external approval validation**.
- Gate 2: live directory lookup + plan evidence; **no OU mutation**.
- Gate 3: one-host forward OU placement proof.
- Gate 4: one-host reversible move proof.
- Gate 5: bounded batch OU placement proof.
- Gate 6: technician/operator UX proof after the engine is already field-proven.
