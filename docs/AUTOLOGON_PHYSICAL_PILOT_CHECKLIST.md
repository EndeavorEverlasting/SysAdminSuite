# AutoLogon one-target physical pilot checklist

Use this checklist with `AUTOLOGON_DEPLOYMENT_WORKFLOW.md`. It is a gate sheet, not an alternate command authority.

## Repository and operator readiness

- [ ] Current `origin/main` contains the canonical AutoLogon deployment, deterministic routing, frozen proof contracts, and dedicated fixture E2E.
- [ ] Working tree is clean and the approved change references the intended commit.
- [ ] One exact authorized target FQDN is stored only in an ignored operator-local input.
- [ ] The package remains enabled in `configs/software-packages/approved-apps.json`.
- [ ] Current installer SHA-256 is pinned in the operator request.
- [ ] The catalog records `installer_and_no_arguments_confirmed`; no installer switches are supplied.
- [ ] Approver, request, change, and ticket references are present.
- [ ] Product-owner rollback/recovery steps are approved and a technician is available.
- [ ] No password, account identifier, private package root, hostname, or raw evidence will be committed.

## Static and fixture gate

- [ ] `python .\Tests\survey\test_autologon_deployment_workflow_contracts.py` passes.
- [ ] `python .\Tests\survey\test_autologon_admin_runtime_runbook_contracts.py` passes.
- [ ] Dedicated `autologon` E2E profile passes under Windows PowerShell 5.1.
- [ ] Fixture classification remains `contract_only` / `sanitized_fixture_contract`.
- [ ] Fixture output makes no live scheduled-task, SYSTEM, reboot, sign-in, access, or application claim.

## Plan and preflight gate

- [ ] Fresh one-target `kerberos_smb_task` preflight completed with explicit read-only network approval.
- [ ] Classification is `kerberos_smb_task_ready`.
- [ ] Selected transport is `kerberos_smb_task`; no WinRM fallback is accepted.
- [ ] Plan-only AutoLogon invocation returns `deployment_planned`.
- [ ] Plan output shows no target mutation.
- [ ] Operator reviewed the exact closed request and confirmation remains enabled.

## Administrator deployment gate

- [ ] AutoLogon is the final security-sensitive product mutation.
- [ ] Before snapshot succeeded for the target.
- [ ] Target was not skipped as baseline failed or already configured.
- [ ] Final-step gate passed with no bypass.
- [ ] Canonical front door was used.
- [ ] Scheduled task was created and executed as SYSTEM in the live result.
- [ ] Installer result was retrieved.
- [ ] SysAdminSuite cleanup was verified.
- [ ] Zero run-scoped SysAdminSuite remnants were verified.
- [ ] State result is expected and does not require review.
- [ ] `Inspect-LatestAutoLogon.cmd -RequireDeploymentSucceeded` returns `DEPLOYMENT_SUCCEEDED_RUNTIME_PENDING`.

## Controlled reboot and signed-in proof

- [ ] Technician remains present for the approved reboot; no unattended reboot command is used.
- [ ] Reboot completion is directly observed.
- [ ] Automatic sign-in is directly observed separately from current-session identity.
- [ ] Current session matches the expected AutoLogon account.
- [ ] Every required local, mapped, and UNC path passes current-token proof.
- [ ] Any write-probe marker was removed immediately; none remains.
- [ ] Approved application starts and reaches its configured ready surface.
- [ ] Technician performs only the approved disposable action.
- [ ] Concrete expected behavior is observed and recorded without personal data.
- [ ] Exact runtime proof level is recorded; a process ACK alone is not accepted.

## Failure and recovery gate

- [ ] Any blocked or failed stage stops expansion.
- [ ] Operator-local evidence is preserved before troubleshooting.
- [ ] No blind retry, transport broadening, gate bypass, or log clearing occurs.
- [ ] Cleanup recovery removes only identified run-scoped SysAdminSuite artifacts.
- [ ] Package-owner rollback is used when required; no improvised registry command is used.
- [ ] Post-recovery state and separately approved sign-in behavior are rechecked.

## Expansion decision

- [ ] All administrator, cleanup, state, reboot, sign-in, current-token, application, and technician gates passed.
- [ ] Proof ceiling and any remaining acceptance gap are documented.
- [ ] Product owner and change authority approved expansion beyond the one-target pilot.
