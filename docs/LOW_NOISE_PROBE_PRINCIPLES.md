# Low-Noise Probe Principles

## Purpose

This document codifies low-noise principles for SysAdminSuite survey work.

The goal is not to hide authorized activity. The goal is to reduce unnecessary packets, avoid repeated work, and make every probe explainable from the request through the action and resulting artifacts.

## Core principle

The network sees packets, not the operator's shell.

If a tool sends the same SYN, CONNECT, ICMP, or UDP probes to the same targets and ports at the same rate, the network-facing visibility is materially the same whether the process was launched from:

```text
CMD
Windows PowerShell
Windows Terminal
Git Bash
WSL
```

Shell choice can change local endpoint/process history, parent process, and operator workflow. It does not make the same packets lower-noise on the network.

## Shared implementation point

The canonical implementation surface is:

```text
scripts/SasLowNoisePolicy.psm1
```

Survey planners and command dispatchers should import this module instead of copying low-noise strings locally.

Required shared functions:

```text
Get-SasLowNoisePolicy
New-SasLowNoiseSummaryObject
Get-SasLowNoiseOperatorLines
```

The policy must be consumed by every path that stages or runs probes, including:

```text
serial preflight planning
network preflight execution
Naabu command planning
subnet confirmation planning
future delta/iteration planners
```

No use case should invent its own retry doctrine or omit the principle that fresh reachable/identity evidence suppresses habitual re-probing.

## What actually lowers network noise

Low-noise comes from the survey design:

```text
smaller scope
fewer ports
lower rate
fewer retries
smarter evidence reuse
avoiding broad scans
avoiding targets that do not deserve packets yet
```

Before staging or running any probe, SysAdminSuite should answer:

```text
Should this target be probed at all?
Which exact host/IP should be probed?
Which exact ports answer the survey question?
At what rate?
How many retries?
Is this already fresh in local evidence?
Is this a CDN/WAF/load-balanced/front-door target?
Is this a mystery serial that needs review, not packets?
```

## Request-to-artifact path

Every probe-worthy action should be explainable as a chain:

```text
request
  -> source artifact
  -> local evidence review
  -> target selection reason
  -> low-noise profile
  -> action handoff
  -> timestamped output artifact
  -> delta/review classification
```

If a row cannot explain that chain, it should not silently become a network target.

## Serial-first implication

Serials remain the anchor for Cybernet work.

A serial-only row is not low priority. It is a mystery row that answers the operational question:

```text
Where did this serial go?
```

But a serial string is not a network endpoint. Do not ping it. Do not pass it to packet tools. Route it to review until an approved bridge exists.

Valid bridges include:

```text
approved workstation identity evidence
approved tracker/export enrichment
approved hostname evidence
approved IP evidence
approved MAC/IP evidence
approved DNS/AD/export evidence
prior local probe artifact with a valid host/IP target
```

## Probe-again pragmatism

A fixed number of repeat probes is not inherently meaningful.

Five probes are unnecessary when a device is already recently reachable or identity-confirmed. Re-probing a fresh success may be safe, but it is usually lower value than preserving the success and waiting for a meaningful reason or a better time window.

Prefer:

```text
probe at a different time of day
probe on a different day of week
probe only when evidence is stale, missing, conflicting, or operator-forced
```

Avoid:

```text
five retries in the same narrow time window
re-probing already fresh reachable rows by default
all-port profiles as the default
UDP by default
scan-all-IPs by default
```

## Attempt diversity

Repeated non-response is more meaningful when it is time-diverse.

Recommended dimensions:

```text
morning / midday / afternoon / evening / overnight
weekday / weekend
same day / different dates
same network path / different approved vantage if applicable
```

A row should not become `PERSISTENTLY_SILENT_TIME_DIVERSE` merely because the same command retried several times in one narrow window.

## Fresh evidence handling

Fresh useful evidence should reduce packets.

Recommended skip logic:

```text
identity-confirmed and fresh -> skip probe by default
reachable and fresh -> skip probe by default
recently silent but not diverse -> retry later, not immediately forever
serial-only no bridge -> review, not packets
candidate-only AD/DNS/hostname evidence -> review or enrich before packets
CDN/WAF/front-door target -> review or bounded profile, not broad probing
```

## CDN/WAF/front-door handling

Cloud firewalls, WAFs, CDNs, and load balancers can produce misleading results.

They may answer on common ports while not representing the Cybernet device being investigated.

Rules:

```text
Do not treat front-door reachability as serial proof.
Do not broaden scope because a hostname resolves to multiple public IPs.
Use CDN/WAF exclusion behavior where the selected tool supports it and the target profile indicates it is appropriate.
Route suspicious front-door evidence to review.
```

## Packet profile doctrine

Packet tools should run only from staged reduced target files, not directly from raw source artifacts.

Default profiles should be small and explainable:

```text
selected Windows/Cybernet candidate ports
selected web signal ports only when useful
selected UDP only when it answers a specific question
```

All-port behavior, UDP profiles, scan-all-IPs behavior, and broad subnet activity must be explicitly gated and reasoned.

## Artifact context requirement

Every planner output that stages a probe should include low-noise context in machine-readable and human-readable artifacts.

Minimum fields for summary JSON:

```text
low_noise_policy_version
low_noise_principle
network_visibility_note
probe_selection_questions
probe_again_guidance
fresh_evidence_guidance
mystery_serial_guidance
front_door_guidance
packet_profile_guidance
network_activity_performed
```

Minimum handoff text:

```text
The network sees packets, not the shell.
This planner performed no network activity.
Only bridged hostnames/IPs were staged.
Fresh reachable/identity evidence should reduce re-probing.
Prefer retrying stale or silent rows at a different time/day instead of repeating immediately.
Mystery serials require review, not packets.
```

## Output classification implications

Artifacts should explain why each row is in its bucket.

Recommended reasons:

```text
skipped_identity_fresh
skipped_reachable_fresh
staged_bridge_exists
review_no_probe_ready_bridge
review_front_door_or_cdn
retry_later_for_time_diversity
review_persistent_silence
review_mystery_serial
```

## Developer / agent requirements

When implementing survey paths:

1. Put local evidence lookup before packet actions.
2. Make target staging a deliberate artifact, not an implicit side effect.
3. Put low-noise rationale into JSON summaries and operator handoffs.
4. Do not treat shell choice as network-noise control.
5. Do not reduce local console output and call that network-noise reduction.
6. Do not use stealth, bypass, or no-trace language.
7. Preserve monitoring transparency and authorized-activity assumptions.
8. Preserve mystery serials as first-class review outputs.
9. Do not use fixed retry counts without freshness and time-diversity context.
10. Prefer delta-only probing after each run.
11. Import `scripts/SasLowNoisePolicy.psm1` for shared wording and artifact fields instead of copying policy strings.
12. Add static contracts when a new survey lane stages or runs probes so the shared policy cannot be omitted.

## Acceptance criteria for future implementation

A low-noise survey sprint is not complete unless:

- staged target files are reduced from source population by local evidence
- summary JSON explains low-noise rationale
- operator handoff explains why packets are or are not justified
- fresh evidence suppresses unnecessary re-probing
- retry guidance prefers different time/day over immediate repetition
- serial-only mystery rows are visible and not packetized
- shell choice is not presented as network visibility mitigation
- shared policy comes from `scripts/SasLowNoisePolicy.psm1`
- generated outputs remain local and ignored
