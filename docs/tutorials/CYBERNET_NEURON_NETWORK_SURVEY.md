# Cybernet / Neuron Targeted Network Survey Tutorial

This is the primary field tutorial for technicians using SysAdminSuite to locate Cybernet and Neuron targets from deployment documentation.

Use this when you have approved target documentation, a local admin workstation, and a known site network scope. The workflow is read-only against target workstations: it builds local manifests, captures local network context, runs conservative Nmap discovery, then resolves observed hostnames, IPs, and MAC addresses against the target list.

## Plain-English contract

| Rule | Meaning |
|---|---|
| Authorized only | Run this only for assigned sites, approved subnets, and approved device classes. |
| Local artifacts only | Target lists, Nmap output, resolver CSVs, and dashboards stay on the admin box unless a lead tells you where to store them. |
| No endpoint mutation | This tutorial does not install software, copy files, start services, change registry keys, or schedule tasks on target workstations. |
| No evasion | Do not use decoys, spoofing, stealth flags, vuln scripts, brute force, or credential attacks. This is inventory discovery, not magic ninja theater. |
| Nmap is not a serial oracle | Nmap can help with live hosts, DNS, MACs, and open ports. Device serial matching comes from trackers, AD/CMDB exports, known manifests, or approved host probes. |

## What you should produce

At the end of a clean run, you should have:

- `survey/output/cybernet_targets_resolved.csv`
- `survey/output/neuron_targets_resolved.csv`, if Neurons are in scope
- `logs/network_context/*`
- `logs/nmap/<site>_<subnet>.*`
- `survey/output/<site>_nmap_identity_resolver.csv`
- `survey/output/<site>_nmap_identity_resolver.html`

Do not commit those files. They can contain hostnames, MACs, serials, IPs, site names, and operational evidence.

## Prerequisites

On the admin workstation:

- Git Bash or MSYS2 Bash
- Python 3 available as `python3` or `python`
- Nmap installed and available on `PATH`
- SysAdminSuite cloned locally
- Approved survey package copied locally, not committed
- Approved site subnet or a lead-approved method to confirm the subnet

Check Nmap and Python:

```bash
nmap --version
python3 --version || python --version
```

## Step 1 - Open the repo from Git Bash

```bash
cd /c/path/to/SysAdminSuite

git pull --ff-only
bash tests/bash/smoke-bash-windows-runtime.sh
```

Expected result:

```text
Smoke test passed. Bash-on-Windows runtime looks usable.
```

If the smoke test fails, stop. Fix the admin box first. A bad tool station creates bad evidence.

## Step 2 - Prepare local-only folders

```bash
mkdir -p survey/input survey/output survey/artifacts logs/network_context logs/nmap
```

Copy your approved target files into `survey/input/`.

Expected filenames for this workflow:

```text
survey/input/cybernet_survey_manifest.csv
survey/input/neuron_survey_manifest.csv
survey/input/combined_cybernet_neuron_manifest.csv
```

Safety check:

```bash
git check-ignore -v survey/input/cybernet_survey_manifest.csv
git check-ignore -v survey/output/test.csv
git check-ignore -v logs/nmap/test.xml || true
```

`survey/input/*` and `survey/output/*` must be ignored. If Git tries to track live target files, stop and escalate.

## Step 3 - Build clean target manifests

Cybernet manifest:

```bash
bash survey/sas-survey-targets.sh \
  --device-type Cybernet \
  --csv survey/input/cybernet_survey_manifest.csv \
  --output survey/output/cybernet_targets_resolved.csv
```

Neuron manifest, if in scope:

```bash
bash survey/sas-survey-targets.sh \
  --device-type Neuron \
  --csv survey/input/neuron_survey_manifest.csv \
  --output survey/output/neuron_targets_resolved.csv
```

Combined manifest, if the lead wants one resolver pass:

```bash
bash survey/sas-survey-targets.sh \
  --csv survey/input/combined_cybernet_neuron_manifest.csv \
  --output survey/output/combined_targets_resolved.csv
```

Open the output CSV and confirm columns exist:

```text
Identifier, IdentifierType, DeviceType, HostName, Serial, MACAddress, Source
```

Do not proceed if the target list is empty or mostly `Unknown` unless the lead expects that.

## Step 4 - Capture local network context

Run this before Nmap so the lead can prove where the admin box was connected.

```bash
bash survey/sas-device-snapshot.sh --output-dir logs/network_context
ipconfig /all > logs/network_context/ipconfig_all.txt
route print > logs/network_context/route_print.txt
arp -a > logs/network_context/arp_initial.txt
```

Look for:

- IPv4 address
- default gateway
- DNS suffix
- VLAN/subnet hints
- route table entries

Do not guess the scan scope from vibes. Confirm the CIDR with the lead or network source.

## Step 5 - Run the smallest useful Nmap discovery

Start with one approved `/24` unless a lead explicitly approves a different CIDR.

No-DNS host discovery:

```bash
SITE="SITEKEY"
CIDR="10.x.y.0/24"
SAFE_NAME="${SITE}_10_x_y_0_24"

nmap -sn -n --reason \
  -oA "logs/nmap/${SAFE_NAME}_discovery_nodns" \
  "$CIDR"
```

DNS-aware host discovery:

```bash
nmap -sn --system-dns --reason \
  -oA "logs/nmap/${SAFE_NAME}_discovery_dns" \
  "$CIDR"
```

Use the DNS-aware output for hostname matching when possible. Use the no-DNS output when DNS is stale, slow, or misleading.

## Step 6 - Optional Windows service confirmation

Only run this against live hosts found during discovery. This confirms likely Windows endpoints without running vulnerability scripts.

Create a live host list from the discovery output if needed, then run:

```bash
nmap -sT -Pn -p 135,139,445,3389 --reason --open \
  -oA "logs/nmap/${SAFE_NAME}_windows_ports" \
  -iL logs/nmap/live_hosts.txt
```

If you do not have `live_hosts.txt`, skip this step. Do not hand-build a huge list because you are impatient. Impatience is how garbage evidence gets born.

## Step 7 - Resolve Nmap evidence against the target manifest

Use the DNS XML first:

```bash
bash survey/sas-resolve-nmap-evidence.sh \
  --manifest survey/output/cybernet_targets_resolved.csv \
  --nmap-output "logs/nmap/${SAFE_NAME}_discovery_dns.xml" \
  --nmap-format xml \
  --output "survey/output/${SAFE_NAME}_cybernet_nmap_identity_resolver.csv" \
  --dashboard "survey/output/${SAFE_NAME}_cybernet_nmap_identity_resolver.html"
```

For Neurons:

```bash
bash survey/sas-resolve-nmap-evidence.sh \
  --manifest survey/output/neuron_targets_resolved.csv \
  --nmap-output "logs/nmap/${SAFE_NAME}_discovery_dns.xml" \
  --nmap-format xml \
  --output "survey/output/${SAFE_NAME}_neuron_nmap_identity_resolver.csv" \
  --dashboard "survey/output/${SAFE_NAME}_neuron_nmap_identity_resolver.html"
```

For a combined pass:

```bash
bash survey/sas-resolve-nmap-evidence.sh \
  --manifest survey/output/combined_targets_resolved.csv \
  --nmap-output "logs/nmap/${SAFE_NAME}_discovery_dns.xml" \
  --nmap-format xml \
  --output "survey/output/${SAFE_NAME}_combined_nmap_identity_resolver.csv" \
  --dashboard "survey/output/${SAFE_NAME}_combined_nmap_identity_resolver.html"
```

## Step 8 - Read the result like an adult

Prioritize matches in this order:

1. Exact hostname match to target manifest
2. Hostname prefix match consistent with the site/device naming pattern
3. MAC match from manifest or known evidence
4. IP observed but no trusted identity
5. Target missing from live scan

Common causes of misses:

- device is powered off
- device moved to another subnet
- hostname was renamed or mistyped
- DNS is stale
- tracker serial exists but hostname was never updated
- Nmap saw IP only, with no useful DNS/MAC identity

Do not mark a device found just because the subnet feels right. The judge rejects poetry disguised as evidence.

## Step 9 - Package the local evidence for the lead

Recommended local handoff folder:

```bash
RUN_ID="$(date +%Y%m%d_%H%M%S)_${SAFE_NAME}"
mkdir -p "survey/artifacts/${RUN_ID}"
cp survey/output/*"${SAFE_NAME}"* "survey/artifacts/${RUN_ID}/" 2>/dev/null || true
cp logs/network_context/* "survey/artifacts/${RUN_ID}/" 2>/dev/null || true
cp logs/nmap/*"${SAFE_NAME}"* "survey/artifacts/${RUN_ID}/" 2>/dev/null || true
```

Then zip the artifact folder locally using Windows Explorer or an approved internal method.

Before you leave the admin box:

```bash
git status --short
```

Expected: no live CSV, XML, HTML, ZIP, or tracker data staged for commit.

## Stop conditions

Stop and escalate when:

- the subnet is not approved or unclear
- the admin box is on the wrong VLAN
- smoke test fails
- Nmap is missing or blocked
- target manifests are empty or malformed
- live output appears in `git status --short`
- a scan would exceed the approved site scope

## Technician summary

```text
1. Pull repo.
2. Run Bash smoke test.
3. Copy approved target CSVs into survey/input.
4. Build manifest with sas-survey-targets.sh.
5. Capture local network context.
6. Run one approved Nmap -sn /24 discovery.
7. Resolve Nmap XML against the manifest.
8. Review exact/prefix/MAC/IP/missing results.
9. Package local artifacts.
10. Do not commit live data.
```
