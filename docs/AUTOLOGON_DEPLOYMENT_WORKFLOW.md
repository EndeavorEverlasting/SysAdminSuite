# Canonical AutoLogon administrator and runtime runbook

## Purpose and authority

This is the single launch-order runbook for an approved AutoLogon pilot. It keeps administrator deployment, post-install readiness, reboot observation, signed-in access, application behavior, and operator acceptance as separate proof stages.

Canonical surfaces:

| Purpose | Repository authority |
|---|---|
| Admin deployment | [`scripts\Invoke-SasAutoLogonDeployment.ps1`](../scripts/Invoke-SasAutoLogonDeployment.ps1) |
| Kerberos/SMB preflight | [`scripts\Test-SasSoftwareDeploymentTransport.ps1`](../scripts/Test-SasSoftwareDeploymentTransport.ps1) |
| Public-safe result review | [`Inspect-LatestAutoLogon.cmd`](../Inspect-LatestAutoLogon.cmd) → [`scripts\Show-SasAutoLogonResult.ps1`](../scripts/Show-SasAutoLogonResult.ps1) |
| Current-token access | [`scripts\Invoke-SasAutoLogonSessionAccessProof.ps1`](../scripts/Invoke-SasAutoLogonSessionAccessProof.ps1) |
| Technician application proof | [`scripts\Start-SasAutoLogonTechnicianRuntimeProof.cmd`](../scripts/Start-SasAutoLogonTechnicianRuntimeProof.cmd) |
| Dedicated fixture E2E | [`scripts\Invoke-SasEndToEndValidation.ps1`](../scripts/Invoke-SasEndToEndValidation.ps1) with `-Profile autologon` |

`Invoke-SasAutoLogonDeployment.ps1` routes only through `Invoke-SasValidatedSoftwareDeployment.ps1`, which selects the canonical Kerberos/SMB scheduled-task transport. The older `Invoke-SasSoftwareInstall.ps1` WinRM lane remains an internal compatibility implementation of the generic validated front door; it is not a direct AutoLogon entrypoint and must not be invoked for this workflow.

The application supports only catalog-approved `CopyThenInstall`. It does not permit silent fallback to WinRM, does not create Startup-folder persistence, does not reboot a target, and does not collect a credential.

## Security and evidence boundary

AutoLogon is the final security-sensitive mutation in the workstation configuration sequence. Before the installer can run, the application captures a Before snapshot and requires the final-step gate to pass. There is no `-Force` or undocumented bypass.

Password values are never collected or committed. The state collector may record only whether the configured password value name exists; it never reads the value data. Operator-local inputs and evidence must remain under ignored paths such as `targets\local\` and `survey\output\`.

Never put any of the following in a command, tracked file, screenshot, public receipt, or chat transcript:

- a password or credential;
- an account identifier;
- a real hostname outside the operator-local target input;
- the approved private package root;
- raw corporate evidence or machine-local evidence paths.

Use the repository-owned catalog for package identity and source resolution. The operator supplies only the approved target FQDN, current pinned SHA-256, vendor-validated silent arguments, the argument-validation reference, and non-secret authorization/change references.

## Inputs required before a live pilot

Prepare these operator-local values:

| Input | Requirement |
|---|---|
| Target | One exact authorized FQDN for the first pilot |
| Package digest | Current approved installer SHA-256, exactly 64 hexadecimal characters |
| Installer arguments | Vendor-validated silent arguments; the catalog intentionally has no default |
| Argument reference | Non-secret packaging/vendor validation record |
| Authorization | Approver, request, change, and ticket references |
| Host policy | Applicable eligibility policy when the default is not sufficient |
| Runtime config | Uncommitted copy of `docs\examples\autologon-runtime-proof.example.json` with approved local values |
| Recovery | Product-owner-approved rollback/recovery procedure and an available technician |

Do not begin a live pilot while the catalog readiness remains `installer_path_confirmed_arguments_pending` unless the required argument validation has been completed and referenced in the command.

## Proof stages

### Stage 1 — Plan only

The canonical application requires one fresh P02 preflight result for each target. The preflight is an authorized bounded read-only network observation; it does not mutate the target.

```powershell
$Preflight = .\scripts\Test-SasSoftwareDeploymentTransport.ps1 `
  -ComputerName '<AUTHORIZED_TARGET_FQDN>' `
  -TransportIntent kerberos_smb_task `
  -AllowNetworkActivity `
  -PassThru
```

Stop unless `$Preflight.result.decision.classification` is `kerberos_smb_task_ready` and the selected transport is `kerberos_smb_task`.

Use the same closed inputs for the application plan. This `-WhatIf` invocation performs no additional target read or mutation:

```powershell
$Plan = .\scripts\Invoke-SasAutoLogonDeployment.ps1 `
  -ComputerName '<AUTHORIZED_TARGET_FQDN>' `
  -InstallerSha256 '<APPROVED_SHA256>' `
  -InstallerArguments @('<VALIDATED_SILENT_ARGUMENT>') `
  -InstallerArgumentsReference '<NON_SECRET_ARGUMENT_VALIDATION_REFERENCE>' `
  -AuthorizedBy '<APPROVER_REFERENCE>' `
  -RequestReference '<REQUEST_REFERENCE>' `
  -ChangeReference '<CHANGE_REFERENCE>' `
  -TicketReference '<TICKET_REFERENCE>' `
  -Transport SmbScheduledTask `
  -TransportPreflightPath $Preflight.result_path `
  -WhatIf
```

Expected application classification: `deployment_planned`. Its proof ceiling is request and transport planning only.

### Stage 2 — Fixture proof

Run the dedicated zero-network profile before a pilot:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Invoke-SasEndToEndValidation.ps1 `
  -Profile autologon `
  -OutputRoot .\survey\output\e2e-validation
```

The profile builds and executes a harmless generated installer locally, crosses the real AutoLogon application composition, exercises the closed failure matrix, validates cleanup, and verifies a sanitized receipt digest. Its maximum classification is `contract_only` / `sanitized_fixture_contract`. It does not prove target contact, a real scheduled task, SYSTEM execution, Winlogon mutation, reboot, sign-in, file access, application behavior, or acceptance.

For a fast application-only fixture:

```powershell
.\scripts\Invoke-SasAutoLogonDeployment.ps1 `
  -ComputerName 'FIXTURE001' `
  -FixtureMode
```

Expected status: `FIXTURE_PASS`. Fixture execution cannot be combined with `-AllowTargetMutation`.

### Stage 3 — One-target administrator pilot

Re-run the preflight immediately before the change if the earlier result is outside `-PreflightMaxAgeMinutes`. Then run the same reviewed request with the mutation gate enabled:

```powershell
$Pilot = .\scripts\Invoke-SasAutoLogonDeployment.ps1 `
  -ComputerName '<AUTHORIZED_TARGET_FQDN>' `
  -InstallerSha256 '<APPROVED_SHA256>' `
  -InstallerArguments @('<VALIDATED_SILENT_ARGUMENT>') `
  -InstallerArgumentsReference '<NON_SECRET_ARGUMENT_VALIDATION_REFERENCE>' `
  -AuthorizedBy '<APPROVER_REFERENCE>' `
  -RequestReference '<REQUEST_REFERENCE>' `
  -ChangeReference '<CHANGE_REFERENCE>' `
  -TicketReference '<TICKET_REFERENCE>' `
  -Transport SmbScheduledTask `
  -TransportPreflightPath $Preflight.result_path `
  -AllowTargetMutation
```

Do not add `-Confirm:$false` to a field runbook command. The high-impact confirmation is intentional. The application will:

1. resolve the pinned catalog entry without exposing its private source;
2. validate the closed request and fresh preflight;
3. capture the Before state;
4. exclude a failed baseline or already-configured target;
5. require the final-step gate;
6. copy and execute through the canonical Kerberos/SMB scheduled-task front door;
7. retrieve the closed result;
8. clean SysAdminSuite-owned task/staging artifacts;
9. capture the After state and emit canonical deployment, gate, and state results.

### Stage 4 — Post-install readiness

Inspect immediately after the application returns and before deciding whether to reboot or expand:

```powershell
.\scripts\Show-SasAutoLogonResult.ps1 `
  -RunRoot $Pilot.output_root `
  -RequireDeploymentSucceeded
```

Technician shortcut:

```cmd
Inspect-LatestAutoLogon.cmd -RequireDeploymentSucceeded
```

Required public-safe result:

```text
Classification: DEPLOYMENT_SUCCEEDED_RUNTIME_PENDING
Cleanup verified: True
Zero remnants verified: True
Cleanup failures: 0
Repo-owned remnants: 0
Runtime proof pending: True
```

This proves only that authorized canonical deployment, result retrieval, cleanup, zero SysAdminSuite remnants, and the recorded state transition passed. It does not prove reboot, automatic sign-in, current-token access, or application behavior.

### Stage 5 — Reboot and automatic sign-in observation

The workflow does not reboot. A technician performs the approved controlled reboot during the change window and directly observes whether the expected AutoLogon session appears. Do not provide an unattended reboot command, do not leave the workstation unobserved, and do not infer automatic sign-in only from a matching current session.

Record reboot observation and automatic sign-in observation separately. A state delta remains configuration evidence, not runtime proof.

### Stage 6 — Signed-in session access

Run current-token proof from the actual AutoLogon desktop session. Do not use an administrator desktop, alternate credentials, `runas`, remoting, a service, or a scheduled task.

```powershell
$SessionProof = .\scripts\Invoke-SasAutoLogonSessionAccessProof.ps1 `
  -ExpectedUserName '<EXPECTED_AUTOLOGON_ACCOUNT>' `
  -Path @(
    '<APPROVED_LOCAL_APPLICATION_PATH>',
    '<APPROVED_MAPPED_OR_UNC_PATH>'
  ) `
  -RetryCount 3 `
  -RetryDelaySeconds 5 `
  -AllowWriteProbe `
  -Enforce
```

The current identity must match before any path is contacted. The optional write probe creates one unique zero-byte marker with `CreateNew` semantics and immediately removes it. Confirm that no `.sas-autologon-access-*.tmp` marker remains. This stage proves bounded access under the current token; it does not prove deployment history or application behavior.

### Stage 7 — Application behavior and acceptance

Copy the safe example to an ignored operator-local location and replace placeholders with approved values:

```powershell
Copy-Item `
  .\docs\examples\autologon-runtime-proof.example.json `
  .\targets\local\autologon-runtime.json
```

From the same signed-in session, run:

```cmd
scripts\Start-SasAutoLogonTechnicianRuntimeProof.cmd targets\local\autologon-runtime.json
```

Use only a product-owner-approved disposable action. Do not use patient, personal, account, or production-save data. A live pass requires observed reboot, automatic sign-in, expected-account match, session access, application start/readiness, concrete behavior observation, and technician confirmation. The existing runtime emitter remains operator-local; only a source-evidence object satisfying the frozen contract can support `acceptance_proven`.

## Failure review: preserve, classify, then decide

On any blocked, failed, incomplete, cleanup-review, state-review, access, or behavior result:

1. stop expansion and preserve the entire ignored run root;
2. run `Inspect-LatestAutoLogon.cmd` and record only its public-safe classification;
3. identify the failed stage and reason from operator-local evidence;
4. confirm whether target mutation occurred before choosing a recovery action;
5. do not blindly retry, broaden transport, bypass the final gate, clear logs, or delete evidence;
6. obtain a corrected request, fresh preflight, or product-owner decision as applicable.

If cleanup is incomplete, remove only the specifically identified run-scoped SysAdminSuite task/staging remnants using the approved transport recovery procedure. Do not remove installer-owned application state. A cleanup failure is not deployment success and blocks expansion.

## Rollback and recovery

SysAdminSuite does not implement an automated AutoLogon rollback. The live change must therefore have a product-owner-approved recovery procedure before Stage 3.

When rollback is required:

1. stop expansion and preserve deployment/runtime evidence;
2. keep the workstation attended and follow the approved security/change escalation;
3. use only the approved package-owner uninstall or Winlogon recovery procedure—do not invent registry commands from this runbook;
4. capture a new read-only state snapshot after recovery;
5. verify the intended non-AutoLogon sign-in posture during a separately approved controlled reboot;
6. re-run bounded access/application checks only if the recovery plan requires them;
7. close the change with the reached proof level and unresolved gaps.

If no approved rollback procedure exists, the live pilot is blocked. Fixture and plan-only work may continue.

## Proof matrix

| Stage | Positive classification or observation | Highest supported claim |
|---|---|---|
| Plan | `deployment_planned` | Closed request and canonical transport selection only |
| Fixture | `fixture_contract_pass` / `contract_only` | Sanitized fixture contract only |
| Deployment | `deployment_succeeded` | Canonical deployment execution, retrieval, cleanup, and state evidence |
| Readiness | `DEPLOYMENT_SUCCEEDED_RUNTIME_PENDING` | Public-safe confirmation that runtime proof is still pending |
| Reboot/sign-in | Direct technician observations | Reboot and automatic sign-in observations only |
| Session | `SESSION_ACCESS_CONFIRMED` | Expected-account current-token path access |
| Application | `TECHNICIAN_OBSERVED_LIVE_RUNTIME` | Observed signed-in application behavior |
| Acceptance | `acceptance_proven` source evidence plus operator confirmation | Operator-accepted runtime, subject to digest verification |

No single lower stage may be promoted to a later claim.

## Expansion gate

Expand beyond one target only when all of the following are true:

- the canonical transport preflight was fresh and selected Kerberos/SMB scheduled task;
- the final-step gate passed after a valid Before snapshot;
- `deployment_succeeded` was emitted;
- cleanup and zero-remnant checks passed with both counts at zero;
- the state result is expected and requires no review;
- a controlled reboot and automatic sign-in were directly observed;
- current-token access passed for every required path with no marker remaining;
- application readiness and approved behavior were observed;
- the technician recorded the exact proof level and any acceptance gap;
- product owner/change authority approved expansion.

Generated artifacts remain operator-local and ignored. Only the public-safe receipt or the public-safe inspector summary may leave that boundary.

Use the [one-target physical pilot checklist](AUTOLOGON_PHYSICAL_PILOT_CHECKLIST.md) as the go/no-go sheet for this runbook.
