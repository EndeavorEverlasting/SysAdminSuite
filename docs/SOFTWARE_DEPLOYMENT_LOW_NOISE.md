# Software deployment low-noise and target-UI contract

## Purpose

Software deployment is a low-noise operation. The goal is not to conceal authorized activity. The goal is to avoid packets, ports, retries, remote enumeration, and target-user disruption that do not answer the approved deployment question.

This contract applies to:

- the technician readiness command `sas cybernet Probe HOST`;
- the alias `sas network HOST`;
- the integrated readiness gate inside `sas cybernet Deploy HOST`;
- `software_install.transport_preflight`;
- the Windows-native SMB plus Remote Task Scheduler deployment path.

The canonical shared policy remains `scripts/SasLowNoisePolicy.psm1` and `Config/low-noise-policy.json`.

## Technician front doors

Read-only one-target readiness diagnosis:

```powershell
sas cybernet Probe <AUTHORIZED-CYBERNET-HOST-OR-FQDN>
```

Equivalent alias:

```powershell
sas network <AUTHORIZED-CYBERNET-HOST-OR-FQDN>
```

Full deployment:

```powershell
sas cybernet Deploy <AUTHORIZED-CYBERNET-HOST-OR-FQDN>
```

The full deployment command automatically runs the same readiness chain before any mutation. A separate manual probe is useful for iterative diagnosis but is not a prerequisite loop when deployment is already authorized.

The lower-level transport front door remains available for development and contract validation:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\Test-SasSoftwareDeploymentTransport.ps1 `
  -ComputerName <authorized-fqdn> `
  -AllowNetworkActivity `
  -TransportIntent kerberos_smb_task
```

Technicians should prefer the `sas` surfaces because they own repository resolution, short-path handling, short-hostname domain completion, artifacts, and the deployment continuation boundary.

## Default transport question

The current Cybernet deployment question is always `kerberos_smb_task` because the proven field path uses SMB staging plus Remote Task Scheduler. The readiness command and integrated deployment gate must not probe WinRM ports or request WinRM tickets.

`auto` is broad transport discovery. It is never used by the technician Cybernet readiness/deployment path. Naabu, Nmap, subnet discovery, and general service enumeration are also forbidden substitutions for deployment readiness.

## Kerberos SMB plus Task Scheduler probe order

The narrow collector performs a staged dependency chain:

1. Inspect local domain-join and TGT Boolean state.
2. Resolve the one authorized FQDN.
3. Request only the CIFS service ticket.
4. Test TCP 445.
5. Test `ADMIN$` read authorization.
6. Test TCP 135 only after `ADMIN$` is authorized.
7. Query the Schedule service.
8. Query one reserved nonexistent task name to prove read authorization without enumerating the target's task library.

A failed earlier stage suppresses later probes. Failure does not authorize broadening the port set or immediate retry.

## Short hostname handling

The technician may supply either one short hostname or one FQDN. A short hostname is completed with the current domain-joined administrator session's DNS suffix before target DNS resolution. If no usable domain suffix exists, the command fails closed and requires the authorized FQDN.

This completion step does not enumerate DNS, Active Directory, the subnet, or neighboring hosts.

## Evidence and artifact requirements

Every readiness run produces local ignored artifacts through the canonical run context:

- `cybernet_deployment_readiness_result.json`;
- the nested `software_deployment_transport_result.json`;
- `sanitized_transport_observations.json`;
- `low_noise_context.json`;
- `english_summary.txt`;
- `artifact_registry.json`;
- `operator_handoff.txt`.

Live readiness status:

```text
CYBERNET_DEPLOYMENT_READINESS_READY
```

Required transport classification:

```text
kerberos_smb_task_ready
```

The readiness artifact records a target fingerprint rather than a target identifier, the exact tested port subset, whether the local network gate passed, the transport classification, and the proof ceiling. It must report `target_mutation_performed=false`.

The full deployment artifact links the readiness result and records:

- `low_noise_transport_preflight_required=true`;
- `readiness_status`;
- `readiness_transport_classification`;
- `readiness_tested_ports`.

A terminal crash is handled with `sas evidence`; it is not a reason to repeat a probe or redeploy.

## Iterative diagnosis rules

- Run one explicitly scoped target at a time.
- Read the emitted classification before another probe.
- Do not broaden to WinRM, `auto`, Naabu, Nmap, all-port, subnet, or retry loops.
- Do not repeat an identical successful probe merely to generate prettier console output.
- Do not repeat a failed probe until the exact failed dependency or environment gate has changed.
- Once deployment is authorized, use `sas cybernet Deploy HOST`; the command owns a fresh same-transaction readiness gate and continues only if it passes.

## Target-user visibility contract

The current Windows-native deployment path is designed not to create a popup or terminal window in the logged-on user's session:

- the remote task runs as `SYSTEM`;
- the task is not created with `/IT`;
- PowerShell is launched with `-NoProfile -NonInteractive`;
- generated installer processes use `Start-Process -NoNewWindow`;
- approved MSI packages retain validated silent arguments.

These controls establish the repository execution posture. They do not prove that every future vendor installer is silent. Each approved package must retain validated unattended arguments and separate package qualification.

Do not add:

- `/IT`;
- an interactive user principal;
- credential prompts;
- visible PowerShell or console launchers;
- installer arguments that allow dialogs;
- desktop notifications or user-session automation.

## Failure posture

- A reachable port is not authorization proof.
- A task-query acknowledgement is not installation proof.
- A readiness result is not deployment completion.
- A silent controller console is not evidence of low network traffic.
- A vendor process exit code is not proof that no UI appeared.
- An inconclusive preflight stops for review; it does not silently broaden.
- A live deployment still requires one authorized target, returned result evidence, cleanup proof, restart-complete proof, and technician acceptance at the applicable ceiling.

## Validation

Repository enforcement lives in:

- `Tests/survey/test_cybernet_deployment_readiness_contracts.py`;
- `Tests/survey/test_portable_onsite_operator_contracts.py`;
- `Tests/survey/test_software_deployment_transport_preflight_contracts.py`;
- `Tests/Pester/CybernetDeploymentReadiness.Tests.ps1`;
- `Tests/Pester/SoftwareDeploymentTransport.Tests.ps1`;
- `Tests/bash/test_smb_scheduled_task_install_contracts.sh`;
- `harness/validators/validate-harness-registries.py`;
- `harness/validators/validate-outcome-contracts.py`.

## Proof ceiling

Static contracts, PowerShell parsing, sanitized fixture execution, schema validation, and CI can prove the intended low-noise selection, staged stop conditions, artifact wiring, and noninteractive execution posture. They do not prove current corporate-network traffic volume, absence of vendor UI on a real target, successful installation, cleanup, restart, automatic sign-in, or operator acceptance. Those require separately authorized runtime evidence.
