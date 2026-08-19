# AutoLogon VPN transport-preflight timeout handoff

## Field boundary

The protected-network gate can succeed while ordinary Internet Wi-Fi remains connected and a DomainAuthenticated Citrix VPN path is active. A later Kerberos SMB/Task Scheduler transport observation can still block independently inside Windows networking.

The field-proven failure stopped at AutoLogon S4U stage 1 (`transport preflight`) before staging or target mutation. The prior low-noise observer used an in-process PowerShell runspace for ADMIN$ and DCOM Schedule-service reads. Its nominal timeout called `PowerShell.Stop()` and then disposed the runspace. A blocked UNC/DCOM operation could keep that stop/dispose path waiting until the VPN transport changed, so the timeout was not a reliable wall-clock boundary.

## Repair

The default no-credential `kerberos_smb_task` preflight now routes potentially blocking Windows operations through killable child processes. Each operation retains the existing per-observation timeout and fails closed. A hard timeout records a sanitized timeout stage and maps the public transport result to `inconclusive` with `observation_timeout` plus `required_observation_missing`; it never authorizes target mutation.

The protected-runtime repair is `scripts/Repair-SasKerberosSmbTransportPreflightRuntime.ps1`. It is intentionally surgical: it installs the hard-bounded observer and patches only the transport observer/diagnostic wiring in the existing runtime entrypoint. It does not replace unrelated field repairs such as transport output path compaction.

## Next field proof

Do not immediately retry the full AutoLogon transaction. First run only the read-only `kerberos_smb_task` preflight while the protected VPN is connected. Required proof is one of:

- `kerberos_smb_task_ready`, which proves the read-only transport prerequisites under the current token; or
- a bounded fail-closed result with an exact timeout stage such as `tcp_445`, `admin_share`, `tcp_135`, `schedule_service`, or `scheduled_task_query`.

A transport timeout is a network/authorization boundary, not permission to disconnect the protected VPN and continue target mutation over an unapproved path.
