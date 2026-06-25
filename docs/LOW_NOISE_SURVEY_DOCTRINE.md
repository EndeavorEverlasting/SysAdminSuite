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
list. Use `bash survey/sas-cybernet-detect.sh` for the canonical local enrichment step.
Do not depend on `httpx` unless the repo already provides that dependency; keep optional
`httpx` behind `survey/sas-cybernet-packet-followup.sh --use-httpx`.

### TCP structured JSON

```bash
naabu -list logs/targets/<site>_confirm_hosts.txt -json -silent -ec -o logs/nmap/<site>_<runid>_naabu.json
```

### TCP raw pipeline

```bash
naabu -list logs/targets/<site>_confirm_hosts.txt -silent -ec \
  | bash survey/sas-cybernet-detect.sh --site <site> --stdin --jsonl \
  > logs/nmap/<site>_<runid>_cybernet_detect.jsonl
```

When `httpx` is available on the local box, keep it behind the SysAdminSuite
followup wrapper so banners, logs, and enrichment output stay local and
machine-readable:

```bash
naabu -list logs/targets/<site>_confirm_hosts.txt -silent -ec \
  | bash survey/sas-cybernet-packet-followup.sh --site <site> --stdin --use-httpx --cybernet-detect \
  > logs/nmap/<site>_<runid>_enrichment.jsonl
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
reads its execution profiles from `Config/cybernet-naabu-profiles.json`, which is
**generated** from this doctrine contract by
[`survey/sas-generate-naabu-runtime-profiles.sh`](../survey/sas-generate-naabu-runtime-profiles.sh).
Doctrine (`survey/naabu_profiles.json`) is the single source of truth; do not hand-edit
the runtime config. Regenerate and verify:

```bash
bash survey/sas-generate-naabu-runtime-profiles.sh
bash survey/sas-generate-naabu-runtime-profiles.sh --check   # fails if runtime is stale
```

### Evidence vs pipeline output

- `keyports_cybernet_json` is the **default**: full Windows key ports
  (`80,443,135,445,3389,5985,5986`) with `-json` for durable, parseable, packageable
  evidence. Use it for `confirm-windows`, `parse-naabu-only`, and the package path.
  The dashboard presents optional reachability as **Optional reachability check** with
  profile `keyports_cybernet_json` in the wizard step details.
- `keyports_cybernet_pipe` is the **raw local pipeline** profile: same ports, `-silent -ec`,
  no `-json`. Use it only to stream `host:port` into local enrichment
  (`sas-cybernet-packet-followup.sh`). It is not durable evidence.
- `web_reachability_only*` are narrow 80/443 profiles for deliberate web-only checks.
- `udp_dns_snmp_json` and `allports_low_noise_json` require justification
  (`--profile-justified`, or `--allow-full-ports` for all-ports). UDP is never default.
- `host_discovery_web_syn_txt` requires `--approved-subnet-scope` and is never a
  population source. AD remains population authority.

Legacy runtime profile names (`keyports_cdn`, `keyports_cdn_json`, `windows_selected`,
`host_discovery_tcp80`, `udp_infrastructure`, `hostname_all_ips`,
`full_ports_cdn_guarded`) remain available as backward-compatible aliases.
