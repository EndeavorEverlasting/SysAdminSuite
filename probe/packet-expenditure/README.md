# Packet expenditure / naabu evidence normalizer (stdlib-only v1)

This module normalizes naabu TXT/JSON and followup JSONL into unified JSONL + summary JSON.
Bash field execution uses `survey/sas-run-naabu-pipeline.sh`; this Go tool is for post-run consolidation.

## Build

```bash
go build -o ../../bin/sas-naabu-normalize ./cmd/sas-naabu-normalize
```

## Usage

```bash
bin/sas-naabu-normalize \
  -naabu logs/nmap/SSUH_keyports.txt \
  -followup logs/nmap/SSUH_keyports_followup.jsonl \
  -out logs/nmap/SSUH_keyports_normalized.jsonl \
  -summary logs/nmap/SSUH_keyports_summary.json
```

## Prerequisites (naabu CLI scanning)

| OS | Requirement |
|---|---|
| Windows WAB | **Npcap** for SYN scans; naabu auto-installed to `bin/naabu.exe` via `survey/sas-ensure-naabu.sh` (GitHub release — **not winget** on Northwell) |
| Linux | libpcap-dev |
| macOS | libpcap via Homebrew |

## CDN-safe defaults

Default profile `keyports_cdn` uses `-p 80,443 -ec -silent -duc`. Full port `-p - -ec` requires `--allow-full-ports`.

## WAB note

Guest network failures classify as `ENVIRONMENT_BLOCKED_GUEST_NETWORK`, not product failure.
