# Cybernet Low-Noise Identity Canary

## Operator contract

**Operator terminal: Windows PowerShell.**

Use the installed `sas` command from any directory. Do not paste Bash backslash-continuation syntax into CMD or PowerShell, and do not depend on the repository being your current directory.

```powershell
sas cybernet canary HOST01 HOST02
```

Up to five explicit approved hostnames/FQDNs/IPs may be supplied in one canary. CIDRs, IP ranges, wildcard patterns, and subnet-discovery inputs are rejected.

## What the canary does

1. Looks for complete model+serial identity evidence from the last 24 hours and reuses it without network activity.
2. For candidates still needing evidence, performs one canonical preflight pass: DNS resolution, one ICMP attempt, and TCP 135/445 checks.
3. Only when TCP 135 is open, attempts one read-only DCOM/CIM session with the current Windows security context.
4. Reads `Win32_ComputerSystem` for hostname/manufacturer/model and `Win32_BIOS` for BIOS serial.
5. Performs no canary-level retry of a failed identity query.
6. Writes results only under ignored `survey/output/cybernet_canary/` state.
7. Never mutates a target and never accepts credentials in the command line.

This is **not a stealth feature**. It reduces unnecessary packets by shrinking scope, reusing fresh evidence, limiting ports, and refusing automatic canary retries. Normal enterprise monitoring still sees the traffic and this workflow does not guarantee that monitoring will not alert.

## Why this is the preferred hunt loop

The population should come from passive or already-approved sources first: AD-derived inventory, deployment trackers, prior Cybernet sheets, reconciled device exports, and existing local evidence. Those sources nominate candidates without generating survey packets.

Then use canaries in small explicit batches. A responder is still only a candidate. The canary becomes materially useful when it returns both model and serial, because those can be reconciled against the approved Cybernet hardware reference. Software presence or absence is not identity.

## Field loop

1. Reduce the candidate population offline/passively.
2. Run one canary of no more than five candidates.
3. Remove confirmed non-Cybernet hardware from the prime hunt list.
4. Preserve complete model+serial evidence so the next run can reuse it without packets.
5. Only after exhausting approved candidate sources should a separately approved subnet-confirmation workflow be considered.

## Example

```powershell
sas cybernet canary WNH270OPR470 WNH270OPR472 WNH270OPR484 WNH270OPR486
```

Expected local artifact:

```text
survey/output/cybernet_canary/<run>/cybernet_canary_identity.csv
```

Useful columns include `ObservedManufacturer`, `ObservedModel`, `ObservedSerial`, `IdentityStatus`, `EvidenceSource`, and `NetworkActivityPerformed`.

## Interpretation

- `IDENTITY_COLLECTED` — model and BIOS serial were read. Compare them to the approved hardware reference; do not classify from the canary alone.
- `IDENTITY_PARTIAL` — the read-only query returned incomplete identity.
- `IDENTITY_QUERY_FAILED` — RPC was open but the one identity attempt failed or was denied; no retry occurred.
- `RPC_NOT_OPEN_IDENTITY_SKIPPED` — the canary did not earn a WMI/CIM query.
- `FreshLocalReuse` — complete recent evidence was reused and no live probe was performed for that target.

## Proof ceiling

The canary proves bounded read-only network/identity observations. It does not prove a device is a Cybernet, does not authorize deployment, and does not claim reduced monitoring visibility.
