# Low-Noise Survey Doctrine

This document codifies low-noise Cybernet/Neuron survey discipline for SysAdminSuite.
It is doctrine, command profiles, and guardrails — not a live field scan lane.

The goal is to stop wasting time on broad probing, CDN/cloud firewall endpoints,
noisy default output, and scan-first assumptions. AD defines the registered
population. Network tools validate reachability only. Evidence is written locally.

## Truth model

```text
AD registered population = source of registered Cybernet population
Naabu/Nmap = reachability validation only
HTTP/Cybernet detection = enrichment only
UDP probes = optional, justified profile only
Local pipeline = clean local evidence transformation
Target boxes = no writes, no scripts, no agent install
```

## 1. Purpose

Low-noise survey discipline exists to:

- Minimize wasted probes.
- Avoid scanning cloud/CDN/firewall edges as if they are Cybernets.
- Keep output clean and machine-readable.
- Prefer AD-derived target population before network reachability validation.
- Avoid target-side artifacts.
- Write all evidence locally.

Logging reality (use this wording, do not claim "no logs"):

```text
The survey must not write logs or artifacts to target workstations.
The survey writes evidence locally only.
Assume network monitoring may observe authorized traffic.
```

## 2. Language boundary

```text
This project uses "low-noise survey discipline," not "stealth."
The goal is authorized, scoped, no-target-mutation validation.
Do not attempt to bypass monitoring, evade security tools, hide activity, or defeat logging.
Assume enterprise network monitoring may record authorized traffic.
```

The intent is to avoid waste, avoid target-side changes, avoid broad scans, and
produce clean local evidence. The intent is not to evade monitoring.

## 3. Population vs reachability

| Layer                             | Role                                    |
| --------------------------------- | --------------------------------------- |
| AD export                         | registered Cybernet population          |
| logs/targets                      | local approved AD-derived target inputs |
| Naabu/Nmap                        | reachability validation                 |
| Cybernet detector/http enrichment | optional service fingerprint/enrichment |
| CIM/WMI/SCCM/vendor/manual        | serial/identity proof where approved    |
| survey/artifacts                  | local packaged evidence                 |

Do not use naabu or nmap discovery output as the device population. Export the
registered Cybernet devices from AD (or an approved AD-derived report), place the
export in the local gitignored `logs/targets/` store, then derive a plain-text
host list for reachability validation.

## 4. Command principles

- Use AD-derived host lists, not guessed subnets.
- Avoid broad subnet sweeps unless explicitly approved.
- Use `-ec` to exclude CDN/cloud edge targets where appropriate.
- Use key ports only when the use case requires them.
- Use `-silent` for local output hygiene.
- Prefer JSON for structured parsing.
- Prefer plain text when the next pipeline tool expects raw `host:port`.
- Use `-sa` for domain names/load-balanced hosts when all resolved IPs matter.
- Include UDP only when the Cybernet survey needs UDP evidence.
- Avoid banner/logo/noisy output in pipelines.
- Pipeline outputs directly into local parsers/enrichers when possible.
- Never write to target machines.

## 5. Approved profile examples

The commands below are templates, not commands to run blindly. Replace
`<site>` and `<runid>` and confirm the target list is an approved AD-derived host
list. `cybernet-detect` is a project placeholder for the local enrichment step;
do not depend on `httpx` unless the repo already provides that dependency.

### TCP structured JSON

```bash
naabu -list logs/targets/<site>_confirm_hosts.txt -json -silent -ec -o logs/nmap/<site>_<runid>_naabu.json
```

### TCP raw pipeline

```bash
naabu -list logs/targets/<site>_confirm_hosts.txt -silent -ec | cybernet-detect --stdin --jsonl > logs/nmap/<site>_<runid>_cybernet_detect.jsonl
```

### Key ports

```bash
naabu -list logs/targets/<site>_confirm_hosts.txt -p 80,443,135,445,3389,5985,5986 -json -silent -ec -o logs/nmap/<site>_<runid>_keyports.json
```

### All ports, only when justified

```bash
naabu -list logs/targets/<site>_confirm_hosts.txt -p - -json -silent -ec -o logs/nmap/<site>_<runid>_allports.json
```

### UDP optional profile

```bash
naabu -list logs/targets/<site>_confirm_hosts.txt -p u:53,u:161 -uP -json -silent -ec -o logs/nmap/<site>_<runid>_udp.json
```

```text
UDP profiles require explicit justification. They are not default Phase 2b.
```

### SYN-style host discovery for standard web-path mitigation

```bash
naabu -list logs/targets/<site>_subnets.txt -sn -pe -ps 80 -silent -ec -o logs/nmap/<site>_<runid>_host_discovery.txt
```

```text
Use subnet host discovery only when subnet scope is approved. Do not use this to define the Cybernet population.
```

### Load-balanced hostnames

```bash
naabu -host https://example.invalid -sa -json -silent -ec -o logs/nmap/<site>_<runid>_all_resolved_ips.json
```

```text
Use -sa when domain names may resolve to multiple IPs and every resolved IP matters.
Do not use public vendor/cloud examples in repo docs except example.invalid placeholders.
```

## 6. Output discipline

```text
All output must land in logs/nmap/, survey/output/, survey/artifacts/, or another documented gitignored output path.
Do not emit live results into repo root.
Do not commit live JSON, TXT, CSV, ZIP, or XLSX evidence.
```

## Profiles and tooling

- Canonical doctrine profiles: [`survey/naabu_profiles.json`](../survey/naabu_profiles.json)
- Profile contract validator: [`tests/bash/smoke-naabu-profiles.sh`](../tests/bash/smoke-naabu-profiles.sh)
- Render-only command helper: [`survey/sas-naabu-profile-command.sh`](../survey/sas-naabu-profile-command.sh)
- Operational naabu runbook (runtime config): [`docs/NAABU_CYBERNET_PROFILES.md`](NAABU_CYBERNET_PROFILES.md)
- WAB field gate (Phase 2b): [`docs/WAB_TEST_READINESS.md`](WAB_TEST_READINESS.md)

The runtime pipeline ([`survey/sas-run-naabu-pipeline.sh`](../survey/sas-run-naabu-pipeline.sh))
currently reads its execution profiles from `Config/cybernet-naabu-profiles.json`.
The doctrine contract in `survey/naabu_profiles.json` is the reference shape for a
future integration lane; it is not yet wired into the orchestrator. See the
known-gaps note in the Agent F handoff.
