# Software deployment low-noise and target-UI contract

## Purpose

Software deployment is a low-noise operation. The goal is not to conceal authorized activity. The goal is to avoid packets, ports, retries, remote enumeration, and target-user disruption that do not answer the approved deployment question.

This contract applies to:

- `software_install.transport_preflight`;
- the Windows-native SMB plus Remote Task Scheduler deployment path in `bash/apps/sas-install-apps.sh`;
- future transport live certification and operator execution.

The canonical shared policy remains `scripts/SasLowNoisePolicy.psm1` and `Config/low-noise-policy.json`.

## Default transport question

The preflight front door is:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\Test-SasSoftwareDeploymentTransport.ps1 `
  -ComputerName <authorized-fqdn> `
  -AllowNetworkActivity
```

The default `TransportIntent` is `kerberos_smb_task` because the proven Cybernet deployment path uses SMB staging plus Remote Task Scheduler. The default must not probe WinRM ports or request WinRM tickets.

Use an explicit intent only when the requested operation needs it:

```powershell
-TransportIntent kerberos_smb_task
-TransportIntent winrm
-TransportIntent auto
```

`auto` is broad transport discovery. It is never the default and requires a recorded reason when the deployment question can already be answered by one transport.

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

## WinRM probe order

An explicit WinRM intent performs:

1. Local domain/TGT and one-FQDN DNS checks.
2. One HTTP service-ticket request.
3. TCP 5985.
4. TCP 5986 only when 5985 is not reachable and did not time out.
5. One bounded read-only PSSession that is immediately removed.

It does not probe SMB or Task Scheduler surfaces.

## Evidence and artifact requirements

Every run produces local ignored artifacts through the canonical run context:

- `software_deployment_transport_result.json`;
- `sanitized_transport_observations.json`;
- `low_noise_context.json`;
- `english_summary.txt`;
- `artifact_registry.json`.

`low_noise_context.json` records the exact effective port subset. The public-safe artifacts do not include target identifiers, usernames, credentials, ticket bytes, package paths, or raw faults.

Fresh complete evidence should be reused when the repository workflow can prove that it matches the same target, scope, transport intent, and freshness window. Partial, ambiguous, stale, or wrong-scope evidence does not authorize reuse.

## Target-user visibility contract

The current Windows-native deployment path is designed not to create a popup or terminal window in the logged-on user's session:

- the remote task runs as `SYSTEM`;
- the task is not created with `/IT`;
- PowerShell is launched with `-NoProfile -NonInteractive`;
- generated installer processes use `Start-Process -NoNewWindow`;
- the approved BCA MSI uses `/qn /norestart`.

These controls establish the repository execution posture. They do not prove that every future vendor installer is silent. Each approved package must retain validated unattended arguments and must be separately qualified before a physical rollout.

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
- A silent controller console is not evidence of low network traffic.
- A vendor process exit code is not proof that no UI appeared.
- An inconclusive preflight stops for review; it does not silently broaden to `auto`.
- A live deployment still requires one authorized target, returned result evidence, cleanup proof, and technician acceptance.

## Validation

Repository enforcement lives in:

- `Tests/survey/test_software_deployment_transport_preflight_contracts.py`;
- `Tests/Pester/SoftwareDeploymentTransport.Tests.ps1`;
- `Tests/bash/test_smb_scheduled_task_install_contracts.sh`;
- `.github/workflows/harness-contracts.yml`;
- `harness/workflows/software-deployment-transport.yaml`.

## Proof ceiling

Static contracts, PowerShell parsing, sanitized fixture execution, schema validation, and CI can prove the intended low-noise selection and noninteractive execution posture. They do not prove current corporate-network traffic volume, absence of vendor UI on a real target, successful installation, cleanup, or operator acceptance. Those require separately authorized runtime evidence.
