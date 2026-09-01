# AutoLogon Windows PowerShell 5.1 module-path handoff — 2026-09-01

## Proven field boundary

The sealed completion runtime at `f3bed6add7df2fa479289e7e0bed5eb5dea09eec` passed the completion admission and entered the canonical crash-safe AutoLogon transaction. The live protected run proved:

- sealed runtime verification passed for 1672 tracked files;
- the active `DomainAuthenticated` protected path passed;
- exact explicit-host eligibility passed;
- the 15-second read-only transport admission returned `kerberos_smb_task_ready` with timeout stage `none`;
- the deployment engine's mandatory stage-1 transport preflight passed;
- canonical software-source resolution passed;
- the source CIFS ticket passed;
- stage 4 baseline capture then failed before AutoLogon apply with `KERBEROS_S4U_BASELINE_BLOCKED` / `AUTOLOGON_FIELD_PRE_APPLY_ENGINE_BLOCKED`.

The exact baseline error was that `Get-FileHash` was not recognized in the Windows PowerShell 5.1 controller process. No AutoLogon apply, restart handoff, or reboot was reached by this transaction.

## Root cause and repair boundary

The field command was initiated from PowerShell 7.6.3, while the protected AutoLogon bootstrap intentionally executes Windows PowerShell 5.1. A parent PowerShell 7 process can provide a `PSModulePath` that omits Windows PowerShell's inbox module root. The AutoLogon controller then loses normal command discovery for `Microsoft.PowerShell.Utility`, including `Get-FileHash`, even though the deployment scripts correctly target Windows PowerShell 5.1.

`Bootstrap-SysAdminSuiteAutoLogon.cmd` now repairs that process boundary before manifest resolution or target-capable work:

1. resolve `%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules`;
2. require the inbox `Microsoft.PowerShell.Utility` module directory;
3. prepend that Windows PowerShell module root to the process-scoped `PSModulePath`;
4. execute a local `Get-Command Get-FileHash -ErrorAction Stop` proof under Windows PowerShell 5.1;
5. fail before target contact if utility command discovery is still unavailable;
6. otherwise continue into the unchanged sealed manifest, runtime audit, network, target, S4U, apply, restart, and evidence owners.

No global environment variable, profile, registry, package, credential, target policy, S4U principal, or network rule is changed by this repair.

## Regression proof

`Tests/Pester/AutoLogonWindowsPowerShellCompatibility.Tests.ps1` deliberately replaces `PSModulePath` with a nonexistent path, prepends the canonical Windows PowerShell inbox-module root, and requires Windows PowerShell 5.1 with `-NoProfile` to successfully compute a SHA-256 digest using `Get-FileHash`. A second test executes the real `Bootstrap-SysAdminSuiteAutoLogon.cmd` with isolated operator-local state, requires the compatibility PASS marker, and then requires the launcher to stop at missing sealed-manifest authority before target-capable bootstrap. The tests also pin ordering so module-path normalization and the hash-command proof happen before manifest resolution.

## Field continuation gate

Do not rerun the failed `f3bed6a` runtime. After this repair is integrated into `main`, refresh the sealed runtime on Guest/Internet and require the new sealed HEAD before returning to the approved protected Northwell path.

Then use only:

`C:\SASAL\Complete-SysAdminSuiteAutoLogon.cmd HOST`

where `HOST` is the exact operator-authorized target from machine-local field evidence. Live target identifiers remain operator-local and are not tracked in this handoff.

A subsequent pre-apply failure remains a stop-and-inspect state. Deployment completion is not proven until durable evidence reaches `AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED`, followed by field confirmation that the target returns and automatic sign-in behaves as intended.
