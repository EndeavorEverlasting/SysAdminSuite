# Naabu Cybernet scan profiles

CDN-aware naabu CLI for Cybernet field discovery. Read-only. All artifacts stay on the **local** workstation — no logs on target hosts.

## Bootstrap

```bash
bash survey/sas-ensure-naabu.sh
# or
bash scripts/sas-ensure-naabu.sh
```

Downloads pinned `naabu.exe` to `bin/naabu.exe` from [ProjectDiscovery naabu releases](https://github.com/projectdiscovery/naabu/releases) when not on PATH.

## Profiles (`Config/cybernet-naabu-profiles.json`)

| Profile | Equivalent naabu flags | Use |
|---------|------------------------|-----|
| `keyports_cdn` | `-p 80,443 -ec -silent -duc` | Default web reachability (txt out) |
| `keyports_cdn_json` | same + `-json -o FILE` | Audit JSON evidence |
| `host_discovery_tcp80` | `-sn -pe -ps 80 -silent` | Ping + TCP/80 instead of full port scan |
| `udp_infrastructure` | `-p u:53,u:161 -uP -silent` | DNS/SNMP UDP (elevated) |
| `hostname_all_ips` | `-host URL -sa -p 80,443 -ec` | All A records behind load balancers |
| `full_ports_cdn_guarded` | `-p - -ec` (requires `--allow-full-ports`) | Opt-in full range |
| `windows_selected` | `135,139,445,3389,5985,5986,80,443` + `-ec` | Narrow Windows endpoint set |

## Field commands

### CDN-safe key ports (JSON evidence)

```bash
bash survey/sas-run-naabu-pipeline.sh --site SSUH --profile keyports_cdn_json \
  --list evidence/CybernetSubnetDiscovery/SSUH/CybernetSubnetDiscovery_TargetIPs.txt \
  --out logs/nmap/SSUH_web_confirm.json
```

Raw equivalent:

```text
naabu -list targets.txt -p 80,443 -ec -silent -duc -json -o results.json
```

### Silent pipeline (txt → Cybernet followup)

```text
naabu -list targets.txt -silent -duc | sas-cybernet-packet-followup.sh --stdin --cybernet-detect
```

```bash
bash survey/sas-run-naabu-pipeline.sh --site SSUH --profile keyports_cdn \
  --list targets.txt --out logs/nmap/SSUH_ports.txt --pipe-followup
```

`httpx` is optional via `--use-httpx` on the followup script when installed.

### Host discovery (subnets)

```bash
bash survey/sas-run-naabu-pipeline.sh --site SSUH --profile host_discovery_tcp80 \
  --list subnet_candidates.txt --out logs/nmap/SSUH_hostdisc.txt
```

### UDP (Cybernet-adjacent)

```bash
bash survey/sas-run-naabu-pipeline.sh --site SSUH --profile udp_infrastructure \
  --list targets.txt --out logs/nmap/SSUH_udp.txt
```

### Load-balanced hostname (`-sa`)

```bash
bash survey/sas-run-naabu-pipeline.sh --site SSUH --profile hostname_all_ips \
  --host 'https://fleet-api.example.com' --out logs/nmap/SSUH_lb.txt
```

## Orchestrator integration

```bash
bash survey/sas-cybernet-subnet-survey.sh --site SSUH --mode confirm-windows \
  --confirm-tool naabu --host-file survey/output/.../hosts/<cidr>_up.txt \
  --pipe-followup
```

## Post-run parsing

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
bash Tests/bash/test_naabu_pipeline_contracts.sh
```
