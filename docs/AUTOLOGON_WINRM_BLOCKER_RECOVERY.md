# AutoLogon WinRM Blocker Recovery

## Purpose

Use this recovery only for a preserved, one-target AutoLogon run that stopped because the state-delta collector could not open a WinRM session **before any software-install, SMB adapter, validated-deployment, or finalization result was emitted**.

The observed blocker is a repository contract mismatch: canonical AutoLogon installation uses Kerberos SMB plus Remote Task Scheduler, while the legacy Before/After state collector uses PowerShell remoting. A target can therefore be ready for the approved deployment transport while TCP 5985 and WSMan remain unavailable.

Do **not** run `winrm quickconfig`, enable PowerShell remoting, change firewall rules, or open ports to work around this condition. The repository-owned recovery uses the already approved Kerberos SMB scheduled-task boundary.

## Technician entrypoint

From the repository root, double-click:

```text
Recover-AutoLogonWinRmBlocker.cmd
```

Choose **Recover interrupted one-target run**, select the preserved run when prompted, verify the target shown from the stored validated request, and type:

```text
RECOVER
```

The technician does not compose PowerShell commands, re-enter the RunId, or supply credentials.

## Recovery sequence

The launcher delegates this closed sequence to `scripts/Invoke-SasAutoLogonWinRmRecovery.ps1`:

1. Validate that the selected run is under `survey/output/runs/autologon-proof`.
2. Require exactly one preserved validated deployment request, one exact FQDN, and the approved AutoLogon package identity.
3. Refuse automatic recovery if software-install or SMB deployment evidence already exists; this prevents an unclassified duplicate install.
4. Run a fresh, narrow `kerberos_smb_task` P02 preflight.
5. Run the harmless SMB/Task Scheduler live certification.
6. Stage one hash-verified, read-only state worker and run it once as LocalSystem.
7. Retrieve a nonce-bound closed state result.
8. Delete the task and staging root and verify both are absent.
9. If the new baseline is already `autologon_ready`, stop without reinstalling.
10. Otherwise, build a fresh Before manifest from the successful SMB baseline and rerun the canonical AutoLogon final-step gate.
11. Require the final-step gate to prove host eligibility, approved package identity, and the fresh Before state. A missing, malformed, unmatched, shared/user-login, or otherwise ineligible local policy fails closed.
12. Only after the gate passes, execute the preserved request through `Invoke-SasValidatedSoftwareDeployment.ps1 -Transport SmbScheduledTask`. Because recovery accepts exactly one request and that request must be AutoLogon, AutoLogon remains the final mutating package in this recovery sequence.
13. Require validated deployment completion and zero repo-owned remnants.
14. Capture After state through the same transient SMB task boundary and verify teardown again.
15. Emit an English summary and structured recovery result under the preserved run's ignored `recovery/` directory.

## Safety boundaries

The recovery:

- accepts no username, password, or credential parameter;
- never reads or exports the `DefaultPassword` value data;
- never enables or modifies WinRM or WSMan;
- never changes firewall rules or opens ports;
- never performs an automatic reboot;
- never silently falls back to another transport;
- never installs when prior deployment evidence exists;
- never installs unless the canonical AutoLogon final-step gate passes against the fresh SMB baseline;
- fails closed when the operator-local host-eligibility policy is missing, malformed, ambiguous, unmatched, or disallows remote package execution;
- uses one run-scoped scheduled task and one run-scoped staging directory for each state capture;
- requires task deletion, task-absence verification, staging deletion, and zero-remnant verification;
- preserves the original interrupted run and writes new evidence only under its ignored recovery root.

The transient state worker and scheduled task are target mutations. They are explicitly authorized by the technician's `RECOVER` acknowledgement and are not configuration or software mutations.

## Terminal classifications

- `ALREADY_CONFIGURED_RUNTIME_PENDING` — current state is already complete; no recovery installation was run.
- `RECOVERED_DEPLOYMENT_SUCCEEDED_RUNTIME_PENDING` — final-step gate, canonical SMB deployment, post-install state, and teardown succeeded.
- `RECOVERED_DEPLOYMENT_STATE_REVIEW` — deployment completed, but final AutoLogon registry posture is not fully ready.
- `RECOVERY_BLOCKED_EXISTING_DEPLOYMENT_EVIDENCE` — automatic recovery stopped to avoid duplicate installation.
- `RECOVERY_FINAL_GATE_BLOCKED` — the canonical final-step gate did not prove eligibility or prerequisites; no installation was attempted.
- `RECOVERY_TRANSPORT_BLOCKED` — fresh SMB preflight or harmless live certification did not pass.
- `RECOVERY_CLEANUP_REVIEW_REQUIRED` — a transient task or staging root could not be proven absent.
- `RECOVERY_FAILED` — another bounded recovery gate failed.

Only the first two classifications are successful recovery terminals. Both still require separately authorized runtime observation.

## Evidence location

Recovery output is written beneath the preserved run:

```text
survey/output/runs/autologon-proof/<original-run>/recovery/autologon-recovery-*/
```

Important artifacts include:

```text
artifacts/autologon_winrm_recovery_result.json
actions/autologon_final_step_gate_input.json
actions/final-gate/<gate-run>/autologon_final_step_gate.json
reports/english_summary.txt
evidence/baseline_snapshot.json
evidence/after_snapshot.json
```

Some evidence is operator-local and may contain the authorized target identity. Do not commit it.

## Proof ceiling

Successful recovery can prove:

- fresh Kerberos SMB scheduled-task transport readiness;
- harmless SYSTEM task execution and teardown;
- read-only AutoLogon registry and software state captured without password data;
- canonical final-step gate disposition against the fresh Before state;
- canonical validated deployment execution when required;
- package validation and repo-owned deployment teardown;
- post-install AutoLogon registry posture.

It does **not** prove reboot behavior, automatic sign-in, expected current-token access, application behavior, technician acceptance, or human actor identity. Those remain separate, post-reboot runtime-proof gates.

## Updating the technician clone

```powershell
& {
    $RepoRoot = 'C:\Users\pa_aperales\SysAdminSuite'

    Set-Location -LiteralPath $RepoRoot
    git switch main
    git pull --ff-only origin main
}
```

After the recovery PR is merged and the pull completes, double-click `Recover-AutoLogonWinRmBlocker.cmd`.
