# Go / Naabu Packet Pipeline Plan

## Purpose

Define a low-noise, low-waste packet pipeline for Cybernet survey work after the delta planner has reduced the target set.

This is not the first step in the workflow. The packet pipeline runs only after SysAdminSuite has already answered:

```text
What do we already know locally?
What targets still need packets?
What evidence is stale, conflicting, or missing?
```

The packet pipeline exists to spend packets deliberately, not to rediscover the whole network.

## Workflow position

```text
approved serial / target source
  -> delta preflight planner
  -> staged reduced targets under survey/input/
  -> packet pipeline, only when packet evidence is still justified
  -> local survey/output artifacts
  -> reconciliation / dashboard evidence load
```

Naabu is one execution lane after delta planning. It is not a replacement for serial identity proof, AD registration evidence, DNS evidence, subnet/location inference, or approved identity transport.

## Safety and posture

Allowed:

- read-only reachability validation against approved reduced targets
- local-only output under ignored `survey/output/` or `logs/nmap/`
- explicit operator scope control
- quiet local CLI output where useful for pipeline parsing
- no target-side file writes or target mutation

Forbidden:

- broad scanning outside the approved reduced target set
- using packet output as serial identity proof
- treating subnet inference as scan authorization
- collecting credentials
- creating remote tasks
- installing software
- suppressing telemetry or attempting to hide activity
- committing live hostnames, IPs, serials, MACs, or scan output

Normal network, endpoint, firewall, and infrastructure monitoring may record authorized traffic. That is expected. Silent local output is for parseable pipeline data, not evasion.

## Runtime note

Naabu is a packet-survey toolchain lane. It may require Linux, WSL, or another approved admin runtime. It is not the default Windows PowerShell field preflight path.

PowerShell remains the Northwell field workflow for `survey/sas-network-preflight.ps1`.

## Input and output roots

Input target files must come from approved/codified roots:

```text
targets/local/
logs/targets/
survey/input/   # normalized or generated staging only
```

The delta planner should stage the runnable reduced target list here:

```text
survey/input/delta_preflight/<run_id>/to_probe_targets.txt
```

Generated packet-pipeline outputs go here:

```text
survey/output/packet_pipeline/<run_id>/
logs/nmap/
survey/artifacts/
```

Recommended packet-pipeline outputs:

```text
naabu_open_ports.txt
naabu_results.json
cybernet_enrichment.json
packet_pipeline_summary.json
pipeline_stderr.txt
README.txt
```

## Output format doctrine

Use JSON for durable machine artifacts.

Use raw text only when piping because simple target/port lines are easier to pass to the next local enrichment step.

The production enrichment adapter should be named around Cybernet survey intent, such as `cybernet-detect`. If a generic HTTP enrichment tool is used during experimentation, treat it as a placeholder and keep production docs centered on Cybernet enrichment.

## Flag vocabulary to verify before implementation

The implementation sprint must verify the installed Naabu version and exact flag support before emitting field commands.

User-supplied principles to preserve if supported by the installed tool:

| Concept | Candidate flag / behavior | Use |
|---|---|---|
| Silent local output | `silent` mode | Parseable local pipeline output, not evasion |
| JSON output | `json` output mode | Durable local artifacts |
| CDN/cloud exclusion | `exclude CDN` style behavior | Avoid wasting packets on shared/cloud front doors where appropriate |
| Scan all resolved IPs | scan-all-IPs behavior | Opt-in for approved hostnames/domains only |
| Exhaustive ports | all-ports behavior | Explicitly gated, not default |
| UDP probing | UDP profile behavior | Opt-in only when it answers a Cybernet survey question |
| Host discovery signal | SYN-style host/alive signal | Reachability hint only, not identity proof |

Do not assume flag names are stable. Contract tests should check profile intent, not hard-code unverified external CLI behavior without a version check.

## CDN / cloud / firewall fronting

Some IPs or hostnames may point to cloud firewalls, CDN edges, load balancers, or shared front doors. Probing those broadly wastes time and can produce misleading results.

Rules:

- CDN/cloud exclusion should be default for external/cloud-looking targets when supported.
- Front-door results are not proof that a Cybernet device is alive.
- Do not broaden scope just because a domain resolves to multiple public IPs.
- If a target appears CDN/cloud-fronted, classify it as review-required or route it to the correct internal evidence path.

## Scan-all-IPs behavior

Domains and load-balanced names can resolve to multiple IPs.

Rules:

- Scan-all-IPs behavior is opt-in, not default.
- Only use it for approved hostnames/domains.
- Combine with CDN/cloud exclusion when appropriate.
- Do not apply it to arbitrary public domains.
- Record the operator reason in `packet_pipeline_summary.json`.

## Port profile doctrine

Default profiles should be narrow and tied to the survey question.

Suggested profiles:

```text
web_signal: 80,443
windows_identity_candidate: 135,445,3389
cybernet_device_candidate: 9100 plus project-approved Cybernet ports
```

### Exhaustive ports are gated

All-ports behavior is not the low-waste default.

Use it only behind an explicit profile such as:

```text
profile = approved_exhaustive_ports
reason = operator-approved exception
scope = reduced target list only
```

If used, record the reason in `packet_pipeline_summary.json`.

## Host discovery / alive signal

When the goal is a quick IP-host alive signal rather than a port inventory, use a minimal approved alive-signal profile where supported.

Interpretation:

- This is reachability evidence only.
- It is not Cybernet identity proof.
- It can help decide whether a target deserves deeper approved identity transport.

## UDP profile

UDP is not default. Include UDP only when it answers a Cybernet survey question.

Examples where UDP may be useful:

```text
DNS evidence, when scoped and relevant
SNMP evidence, only if approved and expected in the environment
```

Rules:

- UDP requires explicit profile selection.
- Record why UDP was used.
- Do not treat UDP silence as proof a device is absent.

## Pipeline composition

Prefer single-purpose local pipeline steps:

```text
reduced target file
  -> packet reachability tool with quiet parseable output
  -> Cybernet enrichment adapter
  -> local JSON/CSV artifact
```

The pipeline should avoid banners and human-format noise because the next local tool needs parseable input.

This is local output hygiene. It is not log suppression, target stealth, or monitoring bypass.

## Summary JSON

`packet_pipeline_summary.json` should include:

```text
run_id
generated_at
input_target_file
target_count
profile_name
ports_requested
udp_enabled
cdn_exclusion_enabled
scan_all_ips_enabled
silent_mode_enabled
json_output_path
text_output_path
pipeline_output_path
operator_reason
network_activity_performed
scope_source
```

`network_activity_performed` is `true` for this packet lane because packets are intentionally sent. That distinguishes it from the delta planner, where `network_activity_performed` must remain `false`.

## Required profile names

Recommended profile names:

```text
alive_web_signal
windows_identity_candidate
cybernet_candidate_ports
udp_dns_snmp_review
approved_exhaustive_ports
domain_all_ips_review
```

## Future implementation surfaces

Preferred implementation files:

```text
Config/cybernet-naabu-profiles.json
survey/sas-naabu-packet-pipeline.sh
survey/sas-naabu-packet-plan.ps1
Tests/bash/test_go_naabu_packet_pipeline_contracts.sh
docs/go_naabu_packet_pipeline.plan.md
```

The PowerShell plan wrapper may generate command lines and validate scope. The packet execution wrapper may remain Bash/WSL/Linux only if Naabu requires it, but Northwell field docs must clearly distinguish that from the PowerShell network preflight lane.

## Required tests

Tests must prove:

1. Packet execution uses only reduced staged target files under `survey/input/`.
2. Generated outputs stay under `survey/output/packet_pipeline/` or approved ignored output roots.
3. Silent local output is enabled in generated packet commands.
4. JSON output is supported for durable artifacts.
5. Raw text output is allowed only for local pipeline chaining.
6. CDN/cloud exclusion is enabled for relevant profiles where supported.
7. All-ports behavior is rejected unless `approved_exhaustive_ports` is explicitly selected.
8. UDP profiles are opt-in and reasoned.
9. Scan-all-IPs behavior is opt-in and allowed only for approved hostname/domain scope.
10. Packet output is never treated as serial identity proof.
11. No live target, serial, MAC, or packet output fixture is committed.

## Copy-ready next-agent prompt

```text
You are continuing SysAdminSuite.

Implement the Go / Naabu packet pipeline plan from:
- docs/go_naabu_packet_pipeline.plan.md
- docs/DELTA_PREFLIGHT_EVIDENCE_CACHE_SPRINT.md
- docs/FIELD_NETWORK_PREFLIGHT.md

Mission:
Create a low-noise, low-waste packet pipeline that runs only after the delta preflight planner emits a reduced target file under survey/input/delta_preflight/<run_id>/to_probe_targets.txt.

Rules:
- Do not scan outside approved reduced target files.
- Do not treat packet reachability as serial proof.
- Keep packet tool output quiet for parseable local output.
- Prefer JSON for durable artifacts.
- Use raw text only for local pipeline chaining.
- Use CDN/cloud exclusion where supported and relevant.
- Gate exhaustive all-ports behavior behind explicit operator approval.
- Gate UDP profiles behind explicit profile selection and reason.
- Gate scan-all-IPs behavior behind explicit approved hostname/domain scope.
- Keep outputs local and ignored.
- Do not add credentials, target mutation, remote tasks, or telemetry suppression.

Validation:
- bash/static contracts
- offline survey tests
- Pester only for PowerShell command planning, if applicable

Merge policy:
merge_when_green.
```
