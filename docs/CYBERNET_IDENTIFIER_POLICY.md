# Cybernet Identifier Policy

## Purpose

Cybernet unique identifier discovery is **Nmap-first** for the current WAB field path.

PowerShell is known blocked in this path and must not be treated as the primary method for Cybernet identity discovery unless field conditions change and the user explicitly restores that method.

For the broader cross-use-case posture, see `docs/NMAP_USE_CASE_POSTURE.md`.

## Policy

- Use Nmap-derived evidence as the primary identity source for Cybernet discovery.
- Preserve scanner artifacts as durable evidence before parsing or reconciling results.
- Do not treat PowerShell, WMI, CIM, or remote PowerShell failures as proof that a Cybernet is offline.
- Treat PowerShell-derived evidence as secondary or lab-only unless the field path proves it is available.
- Keep discovery read-only unless the user explicitly approves a mutating workflow.

## Expected identity evidence

When available through the approved network path, Cybernet identity evidence may include:

- Reachable host record
- IP address
- MAC address
- Vendor/OUI hint
- DNS or host naming evidence
- Service posture
- Saved scanner artifact path
- Classification result

## Classification

| Condition | Classification |
| --- | --- |
| Cybernet discovery attempted while on guest network | `ENVIRONMENT_BLOCKED_GUEST_NETWORK` |
| Nmap or equivalent approved scanner is blocked by endpoint policy | `ENVIRONMENT_BLOCKED_POLICY` |
| Correct network is claimed but identity evidence is unavailable | `NETWORK_PREFLIGHT_FAILED` until the network path is proven |
| Nmap-derived identity evidence is captured successfully | `OK_NMAP_IDENTITY_PROBE` |
| Scanner evidence exists but SysAdminSuite parsing fails | `PRODUCT_FAILURE` |

## Agent rule

Future agents must not default Cybernet identity discovery back to PowerShell. The current field reality is that PowerShell is blocked. Use the working evidence path first, then build parsers and tracker reconciliation around that artifact layer.

Do not bury Nmap as a Cybernet-only exception. For network-facing identity, reachability, and service posture, Nmap is a first-class evidence lane across SysAdminSuite.
