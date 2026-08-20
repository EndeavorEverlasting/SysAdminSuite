# AutoLogon protected-transport preflight handoff

## Field boundary

The protected-network authority is the live Windows `DomainAuthenticated` non-Wi-Fi path. That path can be a corporate Ethernet/LAN interface or an authenticated VPN adapter. Ordinary Internet Wi-Fi may coexist when a stronger protected path is active, but VPN is not itself a requirement when the operator is already on an approved DomainAuthenticated Ethernet/LAN path.

The original field failure stopped at AutoLogon S4U stage 1 (`transport preflight`) before staging or target mutation. The prior low-noise observer used an in-process PowerShell runspace for ADMIN$ and DCOM Schedule-service reads. Its nominal timeout called `PowerShell.Stop()` and then disposed the runspace. A blocked UNC/DCOM operation could keep that stop/dispose path waiting until the network transport changed, so the timeout was not a reliable wall-clock boundary.

## Repair

The default no-credential `kerberos_smb_task` preflight now routes potentially blocking Windows operations through killable child processes. Each operation retains the existing per-observation timeout and fails closed. A hard timeout records a sanitized timeout stage and maps the public transport result to `inconclusive` with `observation_timeout` plus `required_observation_missing`; it never authorizes target mutation.

The protected-runtime repair is `scripts/Repair-SasKerberosSmbTransportPreflightRuntime.ps1`. It is intentionally surgical: it installs the hard-bounded observer and patches only the transport observer/diagnostic wiring in the existing runtime entrypoint. It does not replace unrelated field repairs such as transport output path compaction.

## Field proof reached

A fresh operator-local read-only proof has now succeeded on an approved `DomainAuthenticated` Ethernet path with no VPN required. The protected network gate returned `OK_NETWORK_POSTURE`, the hard-bounded transport engine returned without a timeout, and the transport result classified:

- `classification = kerberos_smb_task_ready`
- `selected_transport = kerberos_smb_task`
- `reason_codes = all_kerberos_smb_task_prerequisites_satisfied`
- `probe engine = hard_process_bounded`
- `child process isolation = True`
- `timeout stage = none`
- `transport_authorization_proven = True`
- `target_mutation_performed = False`

This closes the prior transport-preflight blocker. It does not prove task creation, software execution, reboot, or cleanup.

## Controlled retry gate

Exactly one new canonical AutoLogon `Remote` transaction is appropriate only when all of the following remain true:

1. the current protected-network gate still passes on the live `DomainAuthenticated` path;
2. the prior failed field transaction stopped pre-apply with `target_mutation_performed = false`, `autologon_applied = false`, `pre_reboot_autologon_ready = false`, and `automatic_reboot_performed = false`;
3. the fresh read-only transport proof is `kerberos_smb_task_ready` with `timeout stage = none`; and
4. the canonical field deployment owns target locking, interrupted-probe recovery, the single apply invocation, restart observation, and cleanup proof.

The canonical deployment will perform its own bounded transport preflight again immediately before apply. That repeat is part of the owned deployment transaction and is not permission for broad or repeated manual probing.

If the next transaction reaches target mutation and then fails or becomes ambiguous, stop and continue from its durable field result. Do not blindly rerun.

A transport timeout or authorization denial remains a network/authorization boundary. It is not permission to disconnect an approved protected path and continue target mutation over an unapproved path.
