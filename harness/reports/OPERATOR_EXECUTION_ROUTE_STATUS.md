# Operator Execution Route Status

## Working

- SysAdminSuite already has repository freshness, command, outcome, deployment-state, artifact, and terminal-evidence authorities.
- AutoLogon already has a tracked crash-safe operator front door: `Run-AutoLogonCrashSafe.cmd HOST`.
- Persistent operator state exposes `sas repo`, and the launcher caches the resolved repo root under `%LOCALAPPDATA%\SysAdminSuite\repo-root.txt`.
- The operator-execution route contract requires path resolution before any repository-relative operator command.
- The route freshness dependency and every declared `required_files` entry must be tracked/proven before execution.
- Raw target text is validated, UTF-8 Base64 encoded, and passed as positional data to the tracked `powershell.exe -File` helper; it is not interpolated into PowerShell source.
- The helper decodes/revalidates the target, re-reads the route registry, re-verifies dependencies, and only then invokes the crash-safe front door.
- The outer operator shell is preserved on child failure; `$LASTEXITCODE` remains the launcher disposition and the route raises an error rather than calling `exit` in the operator shell.
- When the current environment can execute on the operator workstation, safe authorized execution continues in the same turn.
- When it cannot, the handoff is one copy-paste route-and-run command that resolves the path, proves dependencies, invokes the helper/front door, and preserves the exit disposition.

## Repaired boundary

Previously, a fresh agent could select the correct product command (`sas autologon Remote HOST`) yet still hand it to the operator without resolving where to run it. That forced the operator to reacquire repository context and bypassed the stronger crash-safe launcher already registered elsewhere in the harness.

Review also exposed three failure modes in the first route implementation: mutable working-tree state could affect pre-push proof, malformed registry documents were not fully schema-validated, and raw target interpolation/partial dependency checks could make the generated one-liner unsafe or late-failing. The current route makes pushed-tip validation, Draft 2020-12 schema enforcement, encoded target transport, complete dependency proof, deterministic target-rejection dispositions, and operator-shell preservation executable contracts.

## VPN-only field expectation

- The existing protected-network authority accepts a live Windows `DomainAuthenticated` non-Wi-Fi path supplied by either approved Ethernet/LAN or an authenticated VPN adapter.
- For this field run, VPN is the expected access path. Feedback that says the operator is on VPN is therefore context, not a failure classification by itself.
- Interpret the run from the live protected-network and transport evidence (`OK_NETWORK_POSTURE`, transport classification/reason codes, timeout stage, and authorization result) rather than requiring an on-site Ethernet path.
- Do not tell the operator to disconnect an approved VPN or switch to guest/off-network connectivity to make the command run.
- If the protected-network gate or transport authorization fails on VPN, stop at that exact network/authorization boundary and use the durable field result for the next decision.

## Missing / not proven

- CI cannot execute a live command on an Admin Box or protected Northwell workstation.
- Route validation does not prove protected-network authorization, target reachability, AutoLogon deployment, restart, or sign-in.
- Those claims require the crash-safe field-run artifacts produced by the operator front door.

## Current AutoLogon route

- command id: `autologon-remote`
- execution root: resolved at runtime via `sas repo`, then bounded cache fallback
- operator helper: `harness/scripts/Invoke-SasOperatorExecutionRoute.ps1`
- target transport: validated hostname/FQDN -> UTF-8 Base64 -> positional `-File` argument -> decode/revalidate
- operator front door: `Run-AutoLogonCrashSafe.cmd HOST`
- inner product command: `sas autologon Remote HOST`
- required network: protected Northwell; authenticated `DomainAuthenticated` VPN is an approved path when that is the live protected interface
- durable result: `%LOCALAPPDATA%\SysAdminSuite\field-runs\autologon\<run_id>\field-run-result.json`
- latest pointer: `%LOCALAPPDATA%\SysAdminSuite\last-autologon-field-run.json`

## Operator expectation

A correct handoff does not say only “run this command.” It either runs the registered route from the proven location, or gives one command that resolves the location and runs the tracked helper/front door without asking the operator to reconstruct the path. A failed child command leaves the operator shell available for evidence and recovery work. For VPN-confined execution, report VPN as the expected path type and let the live `DomainAuthenticated` network/transport evidence decide authorization.
