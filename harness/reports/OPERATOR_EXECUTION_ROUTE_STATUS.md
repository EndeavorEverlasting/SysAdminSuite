# Operator Execution Route Status

## Working

- SysAdminSuite has repository freshness, command, outcome, deployment-state, artifact, and terminal-evidence authorities.
- AutoLogon already has a sealed-runtime product path: installed `sas autologon Remote HOST` resolves `%LOCALAPPDATA%\SysAdminSuite\autologon-short-runtime.json`, selects the prepared runtime (normally `C:\SASAL`), and invokes its protected AutoLogon bootstrap.
- The protected bootstrap enters the crash-safe field transaction and leaves durable evidence under `%LOCALAPPDATA%\SysAdminSuite\field-runs\autologon`.
- The operator-execution route validates the target before either execution path and keeps raw target text out of rendered PowerShell source by transporting it as UTF-8 Base64.
- Installed `sas` is now the first-class AutoLogon execution adapter. A sealed `C:\SASAL` runtime is not required to contain the full harness registry/tree.
- When installed `sas` is unavailable, the existing full-repository fallback still resolves `sas repo` / `repo-root.txt`, verifies every declared `required_files` dependency, and invokes `harness/scripts/Invoke-SasOperatorExecutionRoute.ps1` through `powershell.exe -File`.
- The outer operator shell is preserved on child failure; `$LASTEXITCODE` retains the child disposition and the route raises an error rather than closing the operator shell.

## Repaired boundary

The original execution-route harness assumed that the path returned by `sas repo` was always a complete repository. Live field evidence disproved that assumption: installed SAS legitimately resolved `C:\SASAL`, the bounded sealed AutoLogon runtime, and the wrapper failed before product execution because `C:\SASAL\harness\api\operator-execution-route-registry.json` does not exist.

That failure was a harness/runtime-topology mismatch, not a VPN, target, or AutoLogon product failure. The repaired route delegates to installed SAS before requiring a full repository. The fallback repository helper remains available only when installed SAS is absent. Windows PowerShell regression coverage explicitly models a sealed runtime with no harness registry so this boundary cannot silently regress.

Earlier review repairs remain intact: pushed-tip validation uses an isolated snapshot, the route registry receives Draft 2020-12 validation, raw target text is not interpolated into child PowerShell source, full-repository fallback dependencies are proven before launch, target rejection has deterministic dispositions, and the operator shell survives child failure.

## VPN-only field expectation

- The existing protected-network authority accepts an approved `DomainAuthenticated` Ethernet/LAN path or authenticated VPN/virtual adapter.
- VPN feedback is context, not a failure classification by itself.
- Interpret the run from live protected-network and transport evidence (`OK_NETWORK_POSTURE`, transport classification/reason codes, timeout stage, and authorization result).
- Do not tell the operator to disconnect an approved VPN or seek Ethernet solely because feedback identifies VPN.
- If the protected-network gate or transport authorization fails, stop at that exact network/authorization boundary and use the durable field result for the next decision.

## Missing / not proven

- CI cannot execute the command on the operator's Admin Box or protected target.
- Route validation does not prove protected-network authorization, target reachability, AutoLogon mutation, restart, or sign-in.
- Those claims require the crash-safe field-run artifacts produced by the installed SAS / sealed-bootstrap product path.

## Current AutoLogon route

- command id: `autologon-remote`
- first execution adapter: installed `sas`
- installed command: `sas autologon Remote HOST`
- prepared runtime authority: `%LOCALAPPDATA%\SysAdminSuite\autologon-short-runtime.json`
- expected sealed runtime: `C:\SASAL`
- sealed product bootstrap: `Bootstrap-SysAdminSuiteAutoLogon.cmd`
- durable crash-safe authority: `Run-AutoLogonCrashSafe.cmd HOST` / `Invoke-SasAutoLogonCrashSafeFieldRun.ps1`
- full-repository fallback helper: `harness/scripts/Invoke-SasOperatorExecutionRoute.ps1`
- target transport: hostname/FQDN validation -> UTF-8 Base64 in route -> decode/revalidate -> product/fallback argument
- required network: protected Northwell; approved DomainAuthenticated hardwire/LAN or authenticated VPN
- durable result: `%LOCALAPPDATA%\SysAdminSuite\field-runs\autologon\<run_id>\field-run-result.json`
- latest pointer: `%LOCALAPPDATA%\SysAdminSuite\last-autologon-field-run.json`

## Operator expectation

A correct handoff uses the strongest proven execution surface already present on the workstation. If installed SAS and its prepared AutoLogon runtime are proven, the exact field command may be `sas autologon Remote HOST`; installed SAS owns sealed-runtime selection and the crash-safe bootstrap. If installed SAS is unavailable, use the registered full-repository route helper instead. In either case, preserve the operator shell and treat durable field evidence—not wrapper text—as deployment truth.
