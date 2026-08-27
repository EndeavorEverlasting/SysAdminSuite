# AutoLogon protected-transport preflight handoff

## Field boundary

The protected-network authority is the live Windows `DomainAuthenticated` non-Wi-Fi path. That path can be a corporate Ethernet/LAN interface or an authenticated VPN adapter. Ordinary Internet Wi-Fi may coexist when a stronger protected path is active, but VPN is not itself a requirement when the operator is already on an approved DomainAuthenticated Ethernet/LAN path.

The original field failure stopped at AutoLogon S4U stage 1 (`transport preflight`) before staging or target mutation. The prior low-noise observer used an in-process PowerShell runspace for ADMIN$ and DCOM Schedule-service reads. Its nominal timeout called `PowerShell.Stop()` and then disposed the runspace. A blocked UNC/DCOM operation could keep that stop/dispose path waiting until the network transport changed, so the timeout was not a reliable wall-clock boundary.

## Repair

The default no-credential `kerberos_smb_task` preflight now routes potentially blocking Windows operations through killable child processes. Each operation retains the existing per-observation timeout and fails closed. A hard timeout records a sanitized timeout stage and maps the public transport result to `inconclusive` with `observation_timeout` plus `required_observation_missing`; it never authorizes target mutation.

The protected-runtime repair is `scripts/Repair-SasKerberosSmbTransportPreflightRuntime.ps1`. It is intentionally surgical: it installs the hard-bounded observer and patches only the transport observer/diagnostic wiring in the existing runtime entrypoint. It does not replace unrelated field repairs such as transport output path compaction.

## Historical field proof

A prior operator-local read-only proof succeeded on an approved `DomainAuthenticated` Ethernet path with no VPN required. The protected network gate returned `OK_NETWORK_POSTURE`, the hard-bounded transport engine returned without a timeout, and the transport result classified:

- `classification = kerberos_smb_task_ready`
- `selected_transport = kerberos_smb_task`
- `reason_codes = all_kerberos_smb_task_prerequisites_satisfied`
- `probe engine = hard_process_bounded`
- `child process isolation = True`
- `timeout stage = none`
- `transport_authorization_proven = True`
- `target_mutation_performed = False`

That proof authorized one controlled canonical retry on the then-proven transport floor. It did not permanently certify another network path or future session.

## Latest field retry

The controlled canonical retry has now been consumed. A later protected field run on an authenticated `DomainAuthenticated` VPN path independently passed:

- protected-network admission;
- sealed-runtime verification;
- canonical target resolution;
- exact local-host eligibility; and
- interrupted-probe recovery.

The transaction then stopped at S4U stage 1 with `KERBEROS_S4U_TRANSPORT_BLOCKED` and public transport classification `inconclusive`. It stopped before stage-8 remote staging, AutoLogon application, restart handoff, or reboot. The durable result therefore remains a pre-apply failure with no target mutation authorized by this run.

The hard-bounded preflight already records a sanitized diagnostic boundary—classification, selected transport, reason codes, probe engine, child-process isolation, and exact timeout stage—but the deployment wrapper previously exposed only `inconclusive`. The repository now treats preservation of those local diagnostics as part of the protected-transport failure contract.

## Current gate

Do **not** run another full AutoLogon `Remote` transaction from this state. First recover the already-written local preflight result and English summary from the failed S4U result and identify the exact bounded transport boundary.

A new controlled AutoLogon retry becomes eligible only after a fresh **read-only** preflight on the intended current protected path proves all of the following in the same session:

- `classification = kerberos_smb_task_ready`
- `selected_transport = kerberos_smb_task`
- `reason_codes = all_kerberos_smb_task_prerequisites_satisfied`
- `probe engine = hard_process_bounded`
- `timeout stage = none`
- `transport_authorization_proven = True`
- `target_mutation_performed = False`

The canonical deployment will perform its own bounded transport preflight again immediately before apply. That repeat is part of the owned deployment transaction and is not permission for broad or repeated manual probing.

If a future transaction reaches target mutation and then fails or becomes ambiguous, stop and continue from its durable field result. Do not blindly rerun.

A transport timeout or authorization denial remains a network/authorization boundary. It is not permission to disconnect an approved protected path and continue target mutation over an unapproved path.
