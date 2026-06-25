# Naabu Cybernet scan profiles

CDN-aware naabu CLI for Cybernet field discovery. Read-only. All artifacts stay on the **local** workstation — no logs on target hosts.

## Bootstrap

```bash
bash survey/sas-ensure-naabu.sh
# or
bash scripts/sas-ensure-naabu.sh
```

Downloads pinned `naabu.exe` to `bin/naabu.exe` from [ProjectDiscovery naabu releases](https://github.com/projectdiscovery/naabu/releases) when not on PATH.

**Northwell field:** use only `sas-ensure-naabu.sh` (GitHub release zip). **Do not use winget** — it is not available on Northwell workstations.

**Other environments:** `winget install projectdiscovery.naabu` (or vendor PATH install) is acceptable when Git Bash ensure is not used; the suite still prefers the pinned GitHub download for reproducible versions.

## Profile truth model

Doctrine is the single source of truth. The runtime config is generated from it:

```text
survey/naabu_profiles.json            (doctrine contract — edit here)
        |  bash survey/sas-generate-naabu-runtime-profiles.sh
        v
Config/cybernet-naabu-profiles.json   (runtime — generated, do not hand-edit)
        |
        v
survey/sas-run-naabu-pipeline.sh      (execution)
```

Regenerate after editing the doctrine contract:

```bash
bash survey/sas-generate-naabu-runtime-profiles.sh
# verify in CI / pre-commit:
bash survey/sas-generate-naabu-runtime-profiles.sh --check
```

## Profiles (doctrine: `survey/naabu_profiles.json`)

| Profile | Equivalent naabu flags | Use |
|---------|------------------------|-----|
| `keyports_cybernet_json` | `-p 80,443,135,445,3389,5985,5986 -ec -silent -duc -json -o FILE` | **Default.** Durable Cybernet key-port JSON evidence |
| `keyports_cybernet_pipe` | `-p 80,443,135,445,3389,5985,5986 -ec -silent -duc` | Raw txt/stdout stream for local pipeline handoff |
| `web_reachability_only_json` | `-p 80,443 -ec -silent -duc -json -o FILE` | Narrow web reachability JSON evidence |
| `web_reachability_only` | `-p 80,443 -ec -silent -duc` | Narrow web reachability txt out |
| `allports_low_noise_json` | `-p - -ec -json` (requires `--allow-full-ports`) | Opt-in full range, justification required |
| `udp_dns_snmp_json` | `-p u:53,u:161 -uP -ec -silent -json` (requires `--profile-justified`) | DNS/SNMP UDP, justification required |
| `host_discovery_web_syn_txt` | `-sn -pe -ps 80 -ec -silent` (requires `--approved-subnet-scope`) | Subnet host discovery; not a population source |
| `load_balanced_hostname_all_ips_json` | `-host URL -sa -p 80,443 -ec -silent -json` | All A records behind load balancers |

### Backward-compatible aliases

Old profile names still resolve so existing scripts and runbooks keep working:

| Legacy alias | Resolves to |
|--------------|-------------|
| `keyports_cdn` | `web_reachability_only` (80,443 txt) |
| `keyports_cdn_json` | `web_reachability_only_json` (80,443 json) |
| `windows_selected` | `keyports_cybernet_json` |
| `host_discovery_tcp80` | `host_discovery_web_syn_txt` |
| `udp_infrastructure` | `udp_dns_snmp_json` |
| `hostname_all_ips` | `load_balanced_hostname_all_ips_json` |
| `full_ports_cdn_guarded` | `allports_low_noise_json` |

**Default change:** the runtime default is now `keyports_cybernet_json` (full Windows key
ports, JSON evidence), not the old 80,443-only `keyports_cdn`. Use `web_reachability_only*`
when you deliberately want a narrow 80/443 check.

## Field commands

### Cybernet key ports (default JSON evidence)

```bash
bash survey/sas-run-naabu-pipeline.sh --site SSUH \
  --list logs/targets/SSUH_confirm_hosts.txt \
  --out logs/nmap/SSUH_keyports_cybernet.json
```

Raw equivalent:

```text
naabu -list targets.txt -p 80,443,135,445,3389,5985,5986 -ec -silent -duc -json -o results.json
```

### Raw pipeline (txt → Cybernet followup)

```text
naabu -list targets.txt -p 80,443,135,445,3389,5985,5986 -ec -silent -duc | sas-cybernet-packet-followup.sh --stdin --cybernet-detect
```

```bash
bash survey/sas-run-naabu-pipeline.sh --site SSUH --profile keyports_cybernet_pipe \
  --list targets.txt --out logs/nmap/SSUH_ports.txt --pipe-followup
```

`httpx` is optional via `--use-httpx` on the followup script when installed.

### Narrow web reachability only (80,443)

```bash
bash survey/sas-run-naabu-pipeline.sh --site SSUH --profile web_reachability_only_json \
  --list logs/targets/SSUH_confirm_hosts.txt --out logs/nmap/SSUH_web_confirm.json
```

### Host discovery (approved subnet scope)

```bash
bash survey/sas-run-naabu-pipeline.sh --site SSUH --profile host_discovery_web_syn_txt \
  --approved-subnet-scope --list logs/targets/SSUH_approved_subnets.txt \
  --out logs/nmap/SSUH_hostdisc.txt
```

Host discovery is not a population source. AD remains population authority.

### UDP (justification required)

```bash
bash survey/sas-run-naabu-pipeline.sh --site SSUH --profile udp_dns_snmp_json \
  --profile-justified --list targets.txt --out logs/nmap/SSUH_udp.json
```

### Load-balanced hostname (`-sa`)

```bash
bash survey/sas-run-naabu-pipeline.sh --site SSUH --profile load_balanced_hostname_all_ips_json \
  --host 'https://example.invalid' --out logs/nmap/SSUH_lb.json
```

## Orchestrator integration

```bash
bash survey/sas-cybernet-subnet-survey.sh --site SSUH --mode confirm-windows \
  --confirm-tool naabu --host-file survey/output/.../hosts/<cidr>_up.txt \
  --pipe-followup
```

After confirm, the orchestrator auto-runs `sas-parse-naabu-evidence.sh` and writes:

- `run_dir/resolver/<site>_naabu_reachability.csv`

Re-parse without rescan:

```bash
bash survey/sas-cybernet-subnet-survey.sh --site SSUH --run-id <run-id> --mode parse-naabu-only
```

## Packaged artifacts (`package-only`)

| Artifact | Typical path in bundle |
|----------|------------------------|
| Naabu JSON/txt | `logs/<site>_*_windows_ports_naabu.json` |
| Followup JSONL | `logs/<site>_*_followup.jsonl` |
| Reachability CSV | `resolver/<site>_naabu_reachability.csv` |
| Manifest index | `PACKAGE_MANIFEST.txt` |

## Post-run parsing (manual)

```bash
bash survey/sas-parse-naabu-evidence.sh \
  --naabu-output logs/nmap/SSUH_web_confirm.json \
  --followup logs/nmap/SSUH_web_confirm_followup.jsonl \
  --output survey/output/naabu_identity_resolver.csv
```

Optional Go normalizer: `probe/packet-expenditure/` (`sas-naabu-normalize`).

## WAB / network posture

- Guest network: classify as `ENVIRONMENT_BLOCKED_GUEST_NETWORK`, not product failure.
- See [`WAB_TEST_READINESS.md`](WAB_TEST_READINESS.md) and [`TEST_RESULT_CLASSIFICATION.md`](TEST_RESULT_CLASSIFICATION.md).

## Contract tests

```bash
bash tests/bash/smoke-naabu-profiles.sh          # doctrine contract parses + low-noise invariants
bash Tests/bash/test_naabu_profile_sync.sh       # runtime config is not stale vs doctrine
bash Tests/bash/test_naabu_pipeline_contracts.sh # runtime rendering (-silent/-ec/-json, gates)
bash Tests/bash/test_naabu_package_contracts.sh
```

## Legacy / PowerShell-enabled environments

PowerShell support is retained for PowerShell-enabled environments and as a reference implementation.
For Northwell-targeted workflows, PowerShell is deprecated. Prefer Bash-first workflows that consume approved AD exports and write local evidence only.

`Invoke-SASCybernetSubnetDiscovery` (PR #49 module under `modules/CybernetSubnetDiscovery/`) may emit
`evidence/CybernetSubnetDiscovery/<site>/CybernetSubnetDiscovery_TargetIPs.txt` for optional handoff.
That output is not required for Northwell WAB Phase 2b or Bash orchestrator workflows.
PS-generated Naabu/Nmap strings are record-only reference commands; execute scans through Bash
(`survey/sas-run-naabu-pipeline.sh`, `survey/sas-cybernet-subnet-survey.sh`) instead.
