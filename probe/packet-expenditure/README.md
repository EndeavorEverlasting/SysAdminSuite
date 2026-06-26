# Packet expenditure / naabu evidence tooling

This module contains Go helpers for low-noise Naabu evidence:

- `sas-naabu-normalize` normalizes naabu TXT/JSON and followup JSONL into unified JSONL + summary JSON.
- `sas-packet-probe` orchestrates approved-host packet expenditure scans. The default build uses the **naabu CLI** (`--engine cli`). Optional **naabu/v2 library** builds use `-tags naabu_lib`.

## Profile

Default: [`Config/cybernet-packet-profile.json`](../../Config/cybernet-packet-profile.json)

| Setting | Value |
|---|---|
| Top ports | `-tp 1000` |
| Concurrency | `-c 50` |
| Rate | `-rate 3000` |
| Smart scan | `-ss -pt 20` |
| Scan type | SYN (`-s s`) |
| CDN/WAF exclusion | `-ec` |

Audit CLI (record-only):

```text
naabu -list <targets> -tp 1000 -c 50 -rate 3000 -ss -pt 20 -s s -ec -json -silent -duc -o <out.jsonl>
```

## Build

```bash
bash scripts/build-packet-probe.sh
```

Requires Go 1.22+.

Default (CLI engine, no naabu module fetch):

```bash
bash scripts/build-packet-probe.sh
```

Library engine (naabu/v2 runner):

```bash
SAS_PACKET_PROBE_TAGS=naabu_lib bash scripts/build-packet-probe.sh
```

The library build depends on `github.com/projectdiscovery/naabu/v2` with predictive smart-scan support.

## Field usage

```bash
bash survey/sas-run-packet-probe.sh \
  --site SSUH \
  --list input/approved-targets.txt \
  --out logs/nmap/SSUH_packet_probe.jsonl \
  --dry-run

bash survey/sas-run-packet-probe.sh \
  --site SSUH \
  --list input/approved-targets.txt \
  --out logs/nmap/SSUH_packet_probe.jsonl \
  --engine cli

SAS_PACKET_PROBE_TAGS=naabu_lib bash scripts/build-packet-probe.sh
bash survey/sas-run-packet-probe.sh \
  --site SSUH \
  --list input/approved-targets.txt \
  --out logs/nmap/SSUH_packet_probe.jsonl \
  --engine library
```

Normalizer usage:

```bash
bin/sas-naabu-normalize \
  -naabu logs/nmap/SSUH_keyports.txt \
  -followup logs/nmap/SSUH_keyports_followup.jsonl \
  -out logs/nmap/SSUH_keyports_normalized.jsonl \
  -summary logs/nmap/SSUH_keyports_summary.json
```

## Outputs

| Artifact | Path pattern |
|---|---|
| JSONL evidence | `logs/nmap/<site>_packet_probe.jsonl` (override with `--out`) |
| Summary JSON | sibling `*_summary.json` |

## Prerequisites

| OS | Requirement |
|---|---|
| Windows WAB | **Npcap** for SYN scans; naabu on PATH for `--engine cli` |
| Linux | libpcap-dev |
| macOS | libpcap via Homebrew |

## Packet probe doctrine

`Config/cybernet-packet-profile.json` must keep `excludeCdn: true`, `disableUpdateCheck: true`,
`output.silent: true`, JSON output, and smart scan mutually exclusive with stream/passive modes.
The Bash wrapper is the field entrypoint. CI uses dry-run and unit tests only, never live scans.

The CDN-safe bash pipeline (`survey/sas-run-naabu-pipeline.sh`) remains the canonical path for
UDP, `-sa`, host-discovery, and followup-pipe profiles.

## WAB note

Guest network failures classify as `ENVIRONMENT_BLOCKED_GUEST_NETWORK`, not product failure. See `docs/TEST_RESULT_CLASSIFICATION.md`.
