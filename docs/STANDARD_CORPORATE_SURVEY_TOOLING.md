# Standard Corporate Survey Tooling Lane

This lane turns probe results into a smaller, cleaner, more usable Cybernet target list while preserving the edge-tool lane for cases where Naabu, Nmap, or packet-expenditure tooling is justified.

The goal is not to replace the advanced lane. The goal is to sustain a dependable baseline that works in ordinary corporate environments with CMD, PowerShell, DNS, ARP, and approved local evidence files.

## Operating rule

Use standard corporate tools first when they can answer the question with lower operational complexity.

Use edge tools only when the standard lane cannot answer the question, or when the approved workflow already requires packet-level evidence.

This is authorized, scoped, low-noise survey discipline. It is not stealth, evasion, log suppression, or hiding activity.

## Inputs

The standard lane starts after an approved probe/preflight pass has produced local evidence such as:

- `to_probe_targets.csv`
- `review_required.csv`
- `serial_network_preflight_summary.json`
- packet/preflight evidence under gitignored `survey/output/**`, `logs/**`, or `survey/artifacts/**`

Generated operational evidence can contain hostnames, IPs, MAC addresses, serials, and site hints. Do not commit generated evidence.

## Dwindling the target list

Reached and non-reached targets are not final identity facts. They are routing facts for the next pass.

Use these statuses when reducing the target list:

| Status | Meaning | Next action |
| --- | --- | --- |
| `ConfirmedReached` | The host/IP responded to the approved reachability check. | Keep only if identity is still unresolved; otherwise remove from the next reachability pass. |
| `RetryCandidate` | The host/IP did not respond, but still has enough approved identity evidence to retry. | Retry later or with a different standard check. Do not mark dead solely from one failed probe. |
| `ReviewRequired` | The row has ambiguity, missing bridge data, multiple host candidates, or conflicting evidence. | Resolve through tracker, AD, operator notes, or another approved evidence source before probing again. |
| `DeferredSubnetCandidate` | The row is tied to a known location/subnet but lacks a direct target. | Only consider targeted subnet work if the subnet is approved and a signature rule is documented. |
| `OutOfScope` | The row is outside the approved target manifest, location, or subnet. | Do not probe. Return to planning/review. |

`NoPing`, `NoTcp`, and DNS failures are not proof that a device is gone. They only mean that a specific check did not produce a response from the current vantage point.

Reachability is not serial proof. Serial identity still requires stronger evidence such as WMI/CIM, SCCM, MDM, vendor data, barcode/operator confirmation, or another approved identity source.

## Location-to-subnet map

Maintain a local location/subnet map so future passes do not need to rediscover basic network geography.

Recommended CSV schema:

```csv
Site,Location,Building,Floor,SubnetCIDR,Gateway,SourceEvidence,LastVerified,SurveyAllowed,Confidence,Notes
```

Field guidance:

| Field | Purpose |
| --- | --- |
| `Site` | High-level site name, such as NSUH, LIJ, SSUH, or Ambulatory location. |
| `Location` | Human-readable department, room, clinic, or install area. |
| `Building` | Optional building identifier. |
| `Floor` | Optional floor or zone. |
| `SubnetCIDR` | Approved subnet, for example `10.10.20.0/24`. |
| `Gateway` | Known gateway if available. |
| `SourceEvidence` | Where the mapping came from: observed target IP, network team note, DHCP export, AD/DNS result, command output, or operator confirmation. |
| `LastVerified` | Date the mapping was last confirmed. |
| `SurveyAllowed` | `yes`, `no`, or `review`. |
| `Confidence` | `high`, `medium`, or `low`. |
| `Notes` | Human notes, including restrictions or known exceptions. |

This map belongs in a local or gitignored path when it contains real operational network details. Commit only redacted examples, schema, and tests.

## Standard CMD checks

Use these when working from a normal technician workstation where enterprise tools may be limited.

```bat
ping -n 1 -w 750 HOSTNAME
nslookup HOSTNAME
arp -a
tracert -d -h 3 HOSTNAME
```

Guidance:

- `ping` success means the host responded to ICMP; failure does not prove absence.
- `nslookup` helps distinguish DNS problems from reachability problems.
- `arp -a` is useful only for recently contacted local-neighbor evidence.
- `tracert -d -h 3` can provide rough path/gateway context without trying to map the network.

Do not run blind subnet sweeps from CMD. Do not turn a location subnet into a full `/24` sweep by default.

## Standard PowerShell checks

Use PowerShell when available because it can structure output more cleanly than CMD.

```powershell
Resolve-DnsName -Name HOSTNAME -ErrorAction SilentlyContinue
Test-Connection -ComputerName HOSTNAME -Count 1 -Quiet
Test-NetConnection -ComputerName HOSTNAME -Port 445
Get-NetNeighbor -AddressFamily IPv4
```

Guidance:

- Use one approved hostname/IP at a time unless a manifest has already been approved.
- Prefer `-Count 1`, explicit ports, and short targeted checks.
- Treat `Get-NetNeighbor` as local observation, not proof of device identity.
- Store output locally under gitignored paths.

## Targeted subnet signature search

Subnet work is allowed only when all of the following are true:

1. The subnet is tied to a known location through the location/subnet map.
2. `SurveyAllowed` is `yes` or the operator has explicitly approved the review case.
3. The search is bounded by documented Cybernet signatures.
4. The target source is recorded in the run artifact or manifest.
5. The command does not broaden beyond the approved subnet, approved location, or approved target class.

Acceptable signature sources include:

- Known Cybernet hostname or naming pattern from approved manifests.
- Known MAC vendor/OUI evidence from local ARP, DHCP, SCCM, MDM, or vendor records.
- Known open-service expectations from prior approved probes, such as a specific management/service port.
- Location constraints from deployment tracker, install notes, or verified subnet map.

A subnet signature pass should produce a review queue, not automatic truth. Candidate discovery is not identity proof.

## Edge tools remain valid

Naabu, Nmap, and the Go packet-expenditure lane remain useful when the question requires faster, cleaner, or richer network evidence than standard tools can provide.

The repo should support both lanes:

| Lane | Best use | Default posture |
| --- | --- | --- |
| Standard corporate tools | CMD/PowerShell/DNS/ARP checks from ordinary workstations. | First-line, low operational complexity. |
| Edge tooling | Packet/service evidence, larger target manifests, richer artifacts. | Approved, scoped, profile-controlled, CI-guarded. |

## Next implementation seam

The practical next script should consume prior probe results and produce a reduced target set:

```text
survey/input/target_reduction/<run_id>/prior_probe_results.csv
survey/output/target_reduction/<run_id>/reduced_targets.csv
survey/output/target_reduction/<run_id>/retry_candidates.csv
survey/output/target_reduction/<run_id>/review_required.csv
survey/output/target_reduction/<run_id>/out_of_scope.csv
survey/output/target_reduction/<run_id>/location_subnet_candidates.csv
survey/output/target_reduction/<run_id>/target_reduction_summary.json
survey/output/target_reduction/<run_id>/operator_handoff.txt
```

The first version can be plan-only and local-only. It should not probe. It should classify what to keep, retry, review, defer to subnet-candidate work, or remove from the next reachability pass.
