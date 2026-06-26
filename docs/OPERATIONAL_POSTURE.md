# Operational posture

SysAdminSuite uses one low-waste posture across survey, dashboard, deployment,
and cleanup work. The machine-readable authority is
[`Config/operational-posture.json`](../Config/operational-posture.json).

This posture is about scope control, local-only evidence, and transparent
operator intent. It is not stealth, evasion, log suppression, or hiding activity.
Assume normal operating-system, endpoint-protection, application, CI, and
network monitoring may record authorized activity.

## Lane model

| Lane | Target mutation | Artifact rule | Default |
|------|-----------------|---------------|---------|
| Survey / recon | Never | Evidence stays in local ignored paths | Enabled |
| Dashboard probes | Never | Relay and probe output stay local | Enabled |
| Deployment / mapping | Authorized only | Transient payloads require teardown | Legacy-gated |

Survey promises such as "no target-side writes" apply to the survey and dashboard
lanes. Deployment and mapping tools are a separate lane: they may intentionally
copy files, create scheduled tasks, install software, or place shortcuts when an
operator explicitly authorizes that work.

## Low-noise survey principles

| Principle | SysAdminSuite control |
|-----------|-----------------------|
| AD-derived or approved manifests define population | `logs/targets/` handoff and survey manifests |
| Naabu validates reachability only | `survey/sas-run-naabu-pipeline.sh` and `survey/sas-run-packet-probe.sh` |
| Avoid CDN/cloud firewall waste | `-ec` is part of every approved Naabu reachability profile |
| Avoid logo/banner noise | `-silent` is enforced for Naabu pipelines |
| Prefer structured parser-facing output | JSON/JSONL profiles and local parsers |
| Use raw text only for local pipe handoff | `keyports_cybernet_pipe` into `sas-cybernet-packet-followup.sh` |
| Gate UDP, all-port, host-discovery, and public targets | explicit flags such as `--profile-justified` and `--approved-subnet-scope` |
| Never leave survey artifacts on target boxes | write only to local ignored paths |

Canonical references:

- [`docs/LOW_NOISE_SURVEY_DOCTRINE.md`](LOW_NOISE_SURVEY_DOCTRINE.md)
- [`survey/naabu_profiles.json`](../survey/naabu_profiles.json)
- [`Config/cybernet-naabu-profiles.json`](../Config/cybernet-naabu-profiles.json)

## Approved Naabu patterns

Use suite wrappers for execution. These examples are local operator commands, not
target-side scripts.

### Durable JSON evidence

```bash
bash survey/sas-run-naabu-pipeline.sh \
  --site <site> \
  --profile keyports_cybernet_json \
  --list logs/targets/<site>_confirm_hosts.txt \
  --out logs/nmap/<site>_<runid>_naabu.json
```

### Raw local pipe handoff

```bash
bash survey/sas-run-naabu-pipeline.sh \
  --site <site> \
  --profile keyports_cybernet_pipe \
  --list logs/targets/<site>_confirm_hosts.txt \
  --pipe-followup \
  --out logs/nmap/<site>_<runid>_cybernet_detect.jsonl
```

`httpx` is optional enrichment only. Use it through
`survey/sas-cybernet-packet-followup.sh --use-httpx` so the pipeline remains
silent and local.

### Special profiles

- UDP (`udp_dns_snmp_json`) requires `--profile-justified`.
- All ports (`allports_low_noise_json`) requires `--allow-full-ports`.
- Host discovery (`host_discovery_web_syn_txt`) requires `--approved-subnet-scope`.
- Load-balanced hostnames use `-sa` only through the hostname profile when every
  resolved IP is intentionally in scope.

## Legacy deployment gate

Legacy deployment/mapping tools are preserved for environments where they are
still needed, but they are disabled by default:

```bash
SAS_ALLOW_LEGACY_TOOLS=1 bash bash/apps/sas-stage-fileshare.sh --allow-legacy ...
```

```powershell
.\mapping\Controllers\Map-Run-Controller.ps1 -AllowLegacy ...
```

If the gate is not enabled, entrypoints fail closed with
`LEGACY_TOOLS_DISABLED` and point back to this document. Enabling the gate does
not bypass normal authorization, credentials, or target-scope requirements.

Deployment teardown rules are documented in
[`docs/DEPLOYMENT_TEARDOWN_DOCTRINE.md`](DEPLOYMENT_TEARDOWN_DOCTRINE.md).
