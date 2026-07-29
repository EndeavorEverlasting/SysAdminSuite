# AutoLogon Deployment Orchestration Capability

## Contract

Route current authorized AutoLogon field deployment through the repository-registered restart-complete deployment surfaces. Resolve the desired state from `harness/api/deployment-state-registry.json` before selecting the command:

- when the five Cybernet clinical-core applications are already proven installed/accepted, preserve them and use `sas autologon Remote HOST`;
- when the clinical core is unproven and the requested goal is the full Cybernet software profile, use `sas cybernet Deploy HOST`.

`sas cybernet Deploy HOST` owns its one-target low-noise Kerberos SMB plus Task Scheduler readiness gate before mutation. Do not require the technician to run a separate readiness command first. When the requested goal is explicit read-only diagnosis rather than deployment, use `sas cybernet Probe HOST` and stop at its artifact ceiling.

Do not route ordinary field deployment through `scripts/Invoke-SasAutoLogonDeployment.ps1` while canonical LocalSystem AutoLogon remains blocked.

## Inputs and preconditions

- Require one explicit authorized Cybernet target, target/change authority, and the current package/source authority registered by the deployment-state harness.
- Require evidence or an explicit operator fact for whether the five-package clinical core is already installed/accepted; fail closed when that state is ambiguous.
- Default network activity and target mutation remain false until the selected product entrypoint receives its explicit authority.
- The integrated full-deployment readiness stage must prove `CYBERNET_DEPLOYMENT_READINESS_READY`, `kerberos_smb_task_ready`, and no WinRM port observations before any application mutation.
- A standalone readiness probe grants no mutation authority and cannot replace the deployment command when product deployment is the requested goal.
- Confirm `canonical_system_install_enabled=false` does not get bypassed by the field route: the current field AutoLogon lane is Kerberos/S4U named-admin execution followed by the required restart.
- Preserve AutoLogon as the final software step.

## Outputs and ceiling

- Consume `cybernet_deployment_readiness_result.json` only as read-only admission evidence. `CYBERNET_DEPLOYMENT_READINESS_READY` is never product deployment completion.
- Consume `autologon_s4u_deployment_result.json` for AutoLogon-only deployment and require `AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED` with the registered restart observations.
- Consume `cybernet_software_deployment_result.json` for full Cybernet software deployment and require `CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED`, the linked readiness fields, and AutoLogon last.
- `KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING` is only an internal pre-reboot apply gate and is never a terminal field-deployment result.
- Restart-complete deployment proves the registered software state and observed restart cycle. It does not prove direct visual automatic sign-in, current-token access, application behavior, or technician acceptance.
- Runtime proof is optional higher-ceiling evidence after deployment and must not delay product deployment completion.

## Guardrails

- Never route current field AutoLogon through the disposable package-VM lane, direct legacy WinRM, the blocked historical six-package LocalSystem path, or an interactive-token substitute.
- Never substitute Naabu, Nmap, a subnet scan, WinRM, or `auto` transport discovery for the one-target software deployment readiness chain.
- Never reproduce target resolution, request validation, package execution, Task Scheduler creation, restart execution, result retrieval, or teardown logic in prompts or this capability.
- Never request or render password data, `DefaultPassword`, live hostnames, account identifiers, private package paths, or raw runtime evidence.
- Do not reinstall a clinical core that is already proven installed/accepted merely to reach AutoLogon.
- Do not treat an installer exit code, process start, command ACK, fixture, Plan, readiness result, harmless live cert, or the pre-reboot S4U classification as deployment completion.
- A field deployment result cannot activate or satisfy runtime proof without the actual signed-in-session prerequisites.
- After missing console output, use `sas evidence` before repeating a probe or deployment.

## Authority

- `harness/api/deployment-state-registry.json`
- `harness/api/harness-command-registry.json`
- `harness/api/harness-artifact-registry.json`
- `harness/workflows/cybernet-autologon-deployment-state.yaml`
- `Probe-CybernetSoftware.cmd`
- `scripts/Invoke-SasCybernetDeploymentReadiness.ps1`
- `Deploy-CybernetSoftware.cmd`
- `scripts/Invoke-SasCybernetSoftwareDeployment.ps1`
- `scripts/Invoke-SasAutoLogonS4URestartDeployment.ps1`
- `scripts/Invoke-SasAutoLogonKerberosS4UPilot.ps1`

## Used by

- `.claude/skills/autologon-deployment/SKILL.md`
