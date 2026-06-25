# Packet expenditure / naabu evidence tooling

This module contains stdlib-only Go helpers for low-noise Naabu evidence:

- `sas-naabu-normalize` normalizes naabu TXT/JSON and followup JSONL into unified JSONL + summary JSON.
- `sas-packet-probe` is an enforced Naabu CLI wrapper for approved host files. It records
  `-ec -silent -json -duc -tp 1000 -c 50 -rate 3000 -ss -pt 20` in the audit string and
  rejects empty, CIDR, oversized, or public-IP target lists unless explicitly allowed.

## Build

```bash
go build -o ../../bin/sas-naabu-normalize ./cmd/sas-naabu-normalize
go build -o ../../bin/sas-packet-probe ./cmd/sas-packet-probe
```

## Usage

```bash
bin/sas-naabu-normalize \
  -naabu logs/nmap/SSUH_keyports.txt \
  -followup logs/nmap/SSUH_keyports_followup.jsonl \
  -out logs/nmap/SSUH_keyports_normalized.jsonl \
  -summary logs/nmap/SSUH_keyports_summary.json

bash ../../survey/sas-run-packet-probe.sh \
  --site SSUH \
  --list ../../survey/fixtures/naabu_pipeline/targets.sample.txt \
  --out ../../logs/nmap/SSUH_packet_probe.json \
  --summary ../../logs/nmap/SSUH_packet_probe.summary.json \
  --dry-run
```

## Prerequisites (naabu CLI scanning)

| OS | Requirement |
|---|---|
| Windows WAB | **Npcap** for SYN scans; naabu auto-installed to `bin/naabu.exe` via `survey/sas-ensure-naabu.sh` (GitHub release — **not winget** on Northwell) |
| Linux | libpcap-dev |
| macOS | libpcap via Homebrew |

## CDN-safe defaults

Default profile `keyports_cybernet_json` uses `-p 80,443,135,445,3389,5985,5986 -ec -silent -duc -json`. Full port `-p - -ec` (`allports_low_noise_json`) requires `--allow-full-ports`.

## Packet probe doctrine

`Config/cybernet-packet-profile.json` must keep `excludeCdn: true`, `output.silent: true`,
JSON output, update-check disabled, and smart scan mutually exclusive with stream/passive modes.
The Bash wrapper is the field entrypoint; CI uses dry-run and unit tests only, never live scans.

## WAB note

Guest network failures classify as `ENVIRONMENT_BLOCKED_GUEST_NETWORK`, not product failure.
