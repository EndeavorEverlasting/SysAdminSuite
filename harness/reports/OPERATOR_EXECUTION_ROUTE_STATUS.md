# Operator Execution Route Status

## Working

- SysAdminSuite has repository freshness, command, outcome, deployment-state, artifact, and terminal-evidence authorities.
- A sealed `C:\SASAL` AutoLogon runtime is a bounded product runtime, not a full repository, and is not required to contain `harness\api\operator-execution-route-registry.json`.
- The operator route validates and decodes the target before execution, uses installed `sas repo` only to resolve the sealed runtime, then invokes `Bootstrap-SysAdminSuiteAutoLogon.cmd` directly.
- The sealed bootstrap verifies its staging manifest/runtime posture and enters `Invoke-SasAutoLogonCrashSafeFieldRun.ps1`, which owns the durable `%LOCALAPPDATA%\SysAdminSuite\field-runs\autologon` result/transcript/latest-pointer evidence.
- The installed universal product command is implemented by `scripts/Invoke-SasUniversalField.ps1`; current product code also routes AutoLogon Remote into `Bootstrap-SysAdminSuiteAutoLogon.cmd`, while Recover remains recovery-only.
- When installed `sas` is unavailable, the full-repository fallback uses `%LOCALAPPDATA%\SysAdminSuite\repo-root.txt`, verifies every declared `required_files` dependency, and invokes `harness/scripts/Invoke-SasOperatorExecutionRoute.ps1` through `powershell.exe -File`.
- The outer operator shell is preserved on child failure and `$LASTEXITCODE` retains the child disposition.

## Repaired boundary

The original route assumed that `sas repo` always identified a full repository. Field evidence disproved that assumption when it correctly resolved `C:\SASAL` and the wrapper then failed because it demanded a harness registry beneath the sealed runtime.

A first repair attempted to trust installed `sas autologon Remote` once a sealed runtime was recognized. Review exposed a second, more important boundary: installed universal launcher copies can lag the sealed runtime contract, and the prior universal AutoLogon Remote dispatcher used `Run-AutoLogonOnsite.cmd`, which called `Invoke-SasAutoLogonFieldDeployment.ps1` directly and bypassed the registered crash-safe wrapper.

The final design does not rely on that assumption. The operator route uses `sas repo` strictly as a runtime locator and invokes the sealed `Bootstrap-SysAdminSuiteAutoLogon.cmd` directly. The product universal launcher is also repaired so future/refreshed `sas autologon Remote` commands converge to the same crash-safe bootstrap. Windows route coverage explicitly fails if the route invokes a fake/stale `sas autologon` dispatcher instead of the sealed bootstrap.

Earlier review repairs remain intact: exact pushed-tip validation uses an isolated snapshot; route schema enforcement remains blocking even without the optional `jsonschema` package; raw target text is not interpolated into PowerShell source; full-repository fallback dependencies are proven before launch; hostile targets fail before execution; and the operator shell survives child failure.

## VPN-only field expectation

- The protected-network authority accepts an approved `DomainAuthenticated` Ethernet/LAN path or authenticated VPN/virtual adapter.
- VPN feedback is context, not a failure classification by itself.
- Interpret live runs from protected-network and transport evidence (`OK_NETWORK_POSTURE`, transport reason/classification, timeout stage, authorization result).
- Do not require an operator to disconnect an approved VPN or seek Ethernet solely because feedback identifies VPN.

## Missing / not proven

- CI cannot execute on the operator's Admin Box or protected target.
- Repository/CI proof does not prove live target reachability, AutoLogon mutation, restart, or sign-in.
- Those claims require the crash-safe field-run artifacts produced by the sealed bootstrap.

## Current AutoLogon route

- command id: `autologon-remote`
- installed locator: `sas repo`
- expected sealed runtime: `C:\SASAL`
- sealed route entrypoint: `Bootstrap-SysAdminSuiteAutoLogon.cmd HOST`
- installed universal product dispatcher: `scripts/Invoke-SasUniversalField.ps1`
- canonical product command: `sas autologon Remote HOST`
- durable crash-safe authority: `Invoke-SasAutoLogonCrashSafeFieldRun.ps1`
- full-repository fallback helper: `harness/scripts/Invoke-SasOperatorExecutionRoute.ps1`
- target transport: hostname/FQDN validation -> UTF-8 Base64 -> decode/revalidate -> sealed bootstrap/fallback argument
- required network: protected Northwell; approved DomainAuthenticated hardwire/LAN or authenticated VPN
- durable result: `%LOCALAPPDATA%\SysAdminSuite\field-runs\autologon\<run_id>\field-run-result.json`
- latest pointer: `%LOCALAPPDATA%\SysAdminSuite\last-autologon-field-run.json`

## Operator expectation

For target-mutating AutoLogon Remote, prefer the sealed crash-safe bootstrap over assumptions about the installed dispatcher revision. A route-and-run handoff may use installed `sas repo` to resolve the runtime, but it must call `Bootstrap-SysAdminSuiteAutoLogon.cmd` directly. A refreshed universal `sas autologon Remote HOST` now converges to that same bootstrap; Recover remains a separate recovery-only path. Durable field evidence, not wrapper text, is deployment truth.
