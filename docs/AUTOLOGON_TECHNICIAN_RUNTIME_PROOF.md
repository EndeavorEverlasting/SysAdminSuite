# AutoLogon technician runtime proof

## Mission

This is the field-execution lane that turns repository contracts into live workstation evidence.
It must run after the AutoLogon deployment and administrative before/after captures, from the actual
signed-in AutoLogon desktop session.

A passing static test, successful installer exit, process launch, route issuance, or command ACK is
not enough. The runner records the exact proof level reached and reports live runtime proof only when:

1. the current Windows identity matches the approved AutoLogon account;
2. required local, mapped-drive, and UNC paths pass current-token access checks;
3. any stale application process is absent or explicitly and safely stopped;
4. the repo-owned launcher returns a process ACK;
5. the configured target surface becomes ready within a bounded wait;
6. the technician performs the approved disposable trigger;
7. the expected behavior is actually observed;
8. final JSON and chain-log artifacts are written.

## Repo-owned surfaces

```text
scripts\Start-SasAutoLogonTechnicianRuntimeProof.cmd
scripts\Invoke-SasAutoLogonTechnicianRuntimeProof.ps1
scripts\Invoke-SasAutoLogonSessionAccessProof.ps1
docs\examples\autologon-runtime-proof.example.json
```

Do not replace these with a Startup-folder command, scheduled task, service, remote PowerShell
session, `runas`, or an ad hoc terminal command.

## Dependency gate

Before a technician starts:

- the target must be one of the approved pilot workstations;
- AutoLogon deployment staging must be clean;
- state and administrative file-access captures must exist;
- the approved AutoLogon account must be expected to sign in;
- the application owner must identify a disposable/non-persistent validation action;
- the evidence directory must be an approved location writable by the AutoLogon account;
- the site owner must decide whether stopping a stale application process is safe.

The historical state-classifier dependency is resolved on current `main`: missing password-value-name
presence is fail-closed, and canonical deployment is routed through the Kerberos/SMB scheduled-task
front door. Runtime execution still requires a successful current deployment result, clean teardown,
an understood state result, and the separate controlled reboot observation described in
`AUTOLOGON_DEPLOYMENT_WORKFLOW.md`.

## Prepare one config per workstation or site pattern

Copy the committed example to an uncommitted local or approved share location:

```powershell
Copy-Item `
  .\docs\examples\autologon-runtime-proof.example.json `
  .\targets\local\autologon-runtime-WORKSTATION001.json
```

Edit only the site-approved values:

- `expected_user_name`: normally the hostname-based AutoLogon account;
- `access_paths`: exact local application directories, mapped drives, and UNC roundabouts;
- `evidence_directory`: approved evidence share or accessible evidence root;
- `application_path`: exact installed executable;
- `expected_process_name`: executable process name without `.exe`;
- `surface_ready_mode`: `ProcessAlive`, `RespondingWindow`, or `WindowTitle`;
- `window_title_pattern`: required only for `WindowTitle` mode;
- `trigger_description`: exact approved disposable action the technician will perform;
- `expected_behavior`: concrete visible behavior that counts as success.

Do not put passwords, secrets, tokens, credentials, patient data, account data, or personal paths in
the config. The runner rejects secret-like JSON property names and does not record application
arguments in evidence, only their count.

## Stop/safe-start policy

The runner checks for the configured process before launch.

Default example posture:

```json
"stop_existing_process": false,
"safe_to_stop_existing_process": false
```

That means a stale process blocks the proof instead of being killed.

Set both values to `true` only when the application owner explicitly confirms that force-stopping the
exact configured process cannot mutate personal data, corrupt a save/account, or interrupt production
work. The wait for process exit is bounded by `stop_timeout_seconds`.

## Technician execution

1. Reboot the workstation.
2. Directly observe the expected AutoLogon account sign in.
3. Do not switch to an administrator account.
4. From that desktop session, open the approved tooling share or approved local copy.
5. Run:

```cmd
scripts\Start-SasAutoLogonTechnicianRuntimeProof.cmd targets\local\autologon-runtime-WORKSTATION001.json
```

The launcher invokes PowerShell directly and does not depend on terminal focus to start or attach to
the application process.

After the target surface is ready, the terminal displays:

```text
Trigger: <approved action>
Expected behavior: <concrete expected result>
```

The technician then performs only that action, returns to the terminal, and records:

- the application/route/command ACK, or `N/A` when no separate ACK exists;
- the behavior actually observed, without personal data;
- `Pass` or `Fail`.

## Required proof chain

The final JSON contains a `stages` object with:

```text
repo_floor
session_attach
safe_start
launcher_attach
target_surface_ready
trigger_issued
command_ack
behavior_observed
runtime_artifact
```

Every wait is bounded:

- stale-process exit: 1 to 120 seconds;
- application readiness: 1 to 180 seconds;
- access retry count: 0 to 5;
- access retry delay: 1 to 30 seconds.

No continuous watcher or background retry process is created.

## Proof levels

| Proof level | Meaning |
|---|---|
| `TECHNICIAN_OBSERVED_LIVE_RUNTIME` | Current identity/access, safe start, process ACK, target readiness, technician-observed behavior, and artifacts all succeeded live. |
| `LIVE_RUNTIME_BEHAVIOR_FAILED` | The live chain reached observation, but the expected behavior was not observed. |
| `LIVE_RUNTIME_INCOMPLETE` | The live chain stopped before behavior proof, such as identity, access, stale process, launch, or readiness failure. |
| `FIXTURE_ONLY` | Offline synthetic contract proof only. Never counts as live behavior. |
| `FIXTURE_FAILED` | Offline fixture did not satisfy its contract. |

The field report must name the exact proof level. Never rewrite a process ACK or static/fixture result
as live application behavior.

## Artifacts

Each run creates one unique directory under `evidence_directory`:

```text
autologon-runtime-YYYYMMDD-HHMMSS-xxxxxxxx\
  runtime-proof-summary.json
  runtime-proof-chain.log
```

The summary records:

- expected and actual session identity;
- session access proof results;
- safe-start state;
- process ID ACK;
- readiness mode and observed window title when available;
- trigger and expected behavior;
- technician-entered ACK and observed behavior;
- exact proof level and failure reason.

`technician_label` is assignment metadata. It does not cryptographically prove which human typed the
observation.

## Failure handling

Do not retry blindly.

- `IDENTITY_MISMATCH`: stop; the proof was not run under the AutoLogon account.
- access failure: inspect the failed local/mapped/UNC path and share/NTFS authentication posture.
- stale-process blocker: close the app normally or obtain explicit safe-stop approval.
- launch failure: verify the installed executable path and application dependencies.
- readiness timeout: inspect process exit, window mode, title pattern, and startup timing.
- behavior failure: preserve the artifacts and record the exact visible result.
- artifact-directory failure: the run cannot satisfy the evidence chain; capture the console failure
  through the normal incident/ticket process and repair evidence-share access before rerunning.

## Offline validation

The dedicated GitHub Actions fixture creates a synthetic config and proves:

- current-session identity and access are fixture-only;
- no real application is launched;
- no real marker file is created;
- process ACK and target-surface stages are simulated and labeled;
- the final proof level is `FIXTURE_ONLY` with `runtime_proof: false`;
- final JSON and log artifacts are generated.

Local fixture command:

```powershell
.\scripts\Invoke-SasAutoLogonTechnicianRuntimeProof.ps1 `
  -ConfigPath .\targets\local\autologon-runtime-fixture.json `
  -FixtureMode `
  -NonInteractive `
  -ObservedAck 'fixture-ack' `
  -ObservedBehavior 'Synthetic expected behavior observed.' `
  -ObservationResult Pass
```

Fixture success validates the runner only. It does not prove a workstation, AutoLogon session, file
share, application, browser, service, command, or user-visible behavior.
