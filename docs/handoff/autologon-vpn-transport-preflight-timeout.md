# AutoLogon protected-transport preflight handoff

## Field boundary

The protected-network authority is the live Windows `DomainAuthenticated` non-Wi-Fi path. That path can be a corporate Ethernet/LAN interface or an authenticated VPN adapter. Ordinary Internet Wi-Fi may coexist when a stronger protected path is active, but VPN is not itself a requirement when the operator is already on an approved DomainAuthenticated Ethernet/LAN path.

The original field failure stopped at AutoLogon S4U stage 1 (`transport preflight`) before staging or target mutation. The prior low-noise observer used an in-process PowerShell runspace for ADMIN$ and DCOM Schedule-service reads. Its nominal timeout called `PowerShell.Stop()` and then disposed the runspace. A blocked UNC/DCOM operation could keep that stop/dispose path waiting until the network transport changed, so the timeout was not a reliable wall-clock boundary.

## Repair

The default no-credential `kerberos_smb_task` preflight now routes potentially blocking Windows operations through killable child processes. Each operation retains the caller-selected per-observation timeout and fails closed. A hard timeout records a sanitized timeout stage and maps the public transport result to `inconclusive` with `observation_timeout` plus `required_observation_missing`; it never authorizes target mutation.

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

The transaction then stopped at S4U stage 1 with `KERBEROS_S4U_TRANSPORT_BLOCKED`. Recovery of the already-written sanitized transport artifacts narrowed that failure to this exact boundary:

- `classification = inconclusive`
- `selected_transport = none`
- reason codes: `observation_timeout`, `required_observation_missing`
- probe engine: `hard_process_bounded`
- hard child-process isolation: `True`
- Probe timeout stage: `admin_share`
- Ports actually tested: `445`
- target mutation performed: `False`

This means the Kerberos/SMB path had advanced through identity/ticket prerequisites and TCP 445 reachability, then the bounded ADMIN$ authorization observation did not finish inside the historical five-second caller budget. The run stopped before stage-8 remote staging, AutoLogon application, restart handoff, or reboot. The evidence does not establish whether ADMIN$ would succeed with a slightly larger bounded observation window, so another full deployment is not justified directly from this result.

## Current completion gate

Do **not** issue another bare AutoLogon `Remote` transaction from this state. The repository-owned continuation is now:

`Complete-SysAdminSuiteAutoLogon.cmd HOST`

The completion command is an admission/composition layer, not a second deployment implementation. In order it:

1. resolves the machine-local sealed manifest authority with no target contact;
2. runs the canonical full SHA-256 runtime seal audit with no target contact;
3. establishes the exact current `DomainAuthenticated` VPN/LAN network-guard authority;
4. re-proves the canonical protected-network gate;
5. canonicalizes the one explicit target;
6. proves **exact explicit-host eligibility** from the process-scoped operator target using the read-only host validator, with no local policy write;
7. runs one fresh **read-only** `kerberos_smb_task` transport preflight with a 15-second per-observation timeout; and
8. only after `AUTOLOGON_COMPLETION_PREFLIGHT_READY`, enters the existing sealed crash-safe AutoLogon bootstrap pinned to the prepared runtime commit.

If exact explicit-host eligibility fails, the command stops before the transport preflight. If the fresh read-only transport admission is anything other than the following, the completion command emits `AUTOLOGON_COMPLETION_TRANSPORT_BLOCKED` and starts no deployment bootstrap:

- `classification = kerberos_smb_task_ready`
- `selected_transport = kerberos_smb_task`
- `reason_codes = all_kerberos_smb_task_prerequisites_satisfied`
- `probe engine = hard_process_bounded`
- `timeout stage = none`
- `transport_authorization_proven = True`
- `target_mutation_performed = False`

The 15-second admission window is still hard process bounded; it does not restore the old unbounded runspace behavior. It gives the first VPN SMB authorization handshake more time than the historical five-second caller budget while keeping the target read-only. A successful read-only admission does not itself prove deployment. The canonical deployment will perform its own bounded transport preflight again immediately before apply and retains ownership of target locking, recovery, single apply invocation, restart observation, and cleanup evidence.

If a future transaction reaches target mutation and then fails or becomes ambiguous, stop and continue from its durable field result. Do not blindly rerun.

A transport timeout or authorization denial remains a network/authorization boundary. It is not permission to disconnect an approved protected path and continue target mutation over an unapproved path.
