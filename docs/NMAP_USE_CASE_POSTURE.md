# Nmap Use Case Posture

## Purpose

Nmap is now a first-class SysAdminSuite evidence lane for approved, read-only network discovery and identity reconciliation.

This does not replace every runtime lane. It clarifies where Nmap should be preferred when PowerShell is blocked, unreliable, unavailable, or not the right evidence source.

## Core rule

Use Nmap when the question is network truth.

Use PowerShell when the question is Windows internals and the environment allows it.

Use Bash-on-Windows wrappers when technicians need short repeatable field commands.

Use parsers when the evidence already exists and the job is reconciliation, not probing.

## Use case matrix

| Use case | Primary evidence lane | Why |
| --- | --- | --- |
| Cybernet unique identifier discovery | Nmap artifact first | PowerShell is known blocked in the WAB field path. Network identity must come from saved scanner evidence. |
| Cybernet reachability review | Nmap artifact plus explicit ping evidence | Identity evidence and cmd ping evidence are separate signals. |
| Neuron network posture | Nmap where approved, Bash-on-Windows local snapshot for field context | Network visibility should be separated from local workstation state. |
| Printer/server reachability | Nmap or approved network artifact first, then queue/config tooling | Confirms network-facing posture before mapping assumptions. |
| WAB test readiness | Local smoke test first, then Nmap/network evidence after correct network posture is proven | `running` does not prove network validation. |
| Live serial / identity resolver | Saved identity artifacts plus manifest/AD exports | Resolver should consume evidence, not invent it. |
| Dashboard/report generation | Parser output | Reports should explain evidence provenance, timestamps, and classification. |
| PowerShell-permitted lab validation | PowerShell remains valid as secondary evidence | Useful for parity checks, but not the WAB default. |

## Classification expectations

| Situation | Classification |
| --- | --- |
| Host is on guest network and internal targets fail | `ENVIRONMENT_BLOCKED_GUEST_NETWORK` |
| Nmap or approved scanner path is blocked by endpoint policy | `ENVIRONMENT_BLOCKED_POLICY` |
| Correct network is claimed but evidence is missing | `NETWORK_PREFLIGHT_FAILED` or `INCONCLUSIVE` |
| Nmap identity artifact parses successfully | `OK_NMAP_IDENTITY_PROBE` or `OK_IDENTITY_ARTIFACT_PARSED` |
| Identity artifact exists but cmd ping failed then later worked | `INCONCLUSIVE_TRANSIENT_REACHABILITY` |
| Parser fails against a valid artifact | `PRODUCT_FAILURE` |

## Reporting standard

Every dashboard or report that uses Nmap-derived evidence should clearly show:

- source artifact path
- source artifact timestamp
- network posture
- parser version
- identity artifact status
- separate ping status, when available
- classification
- notes for transient or conflicting evidence

## Agent guidance

Agents should make Nmap visible in planning, docs, and parser work whenever the use case depends on network-facing identity or reachability.

Do not bury Nmap as a Cybernet-only exception. It is the primary lane for approved network evidence when the field problem is network identity, reachability, or service posture.

Do not turn this into live mutation tooling. Nmap use in this repo should remain approved, scoped, read-only, artifact-oriented, and parser-friendly unless the user explicitly authorizes a different operational mode.

## Practical design principle

Probe once. Preserve artifacts. Parse many times.

The durable product layer should favor saved evidence over repeated live probing. That makes reports explainable, reviewable, and safer for public-safe repo work.
