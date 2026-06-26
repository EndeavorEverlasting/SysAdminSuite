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

## Dashboard quick path (Cybernet Survey UI)

The dashboard opens Repo Setup first, then lets you choose **Start Cybernet Survey**. Use the survey path when you already have or can prepare an approved target list and want posture, identity, and optional reachability evidence reviewed in one place.

1. Open `http://127.0.0.1:5000/dashboard/?tutorial=setup` (see [`dashboard/README.md`](../../dashboard/README.md)).
2. Click **Start Cybernet Survey** and walk the wizard: Start → Load targets → Network posture → Identity evidence → optional Reachability → Review results.
3. Copy and run the posture and identity commands on the admin workstation.
4. Optionally run **Optional reachability check**; profile `keyports_cybernet_json` in step details when port confirmation is justified.
5. Click **Load Evidence** and import the resulting CSVs/JSON.
6. Read **Review Results**; use **Open network evidence details** or **Advanced Tools** for detailed panels only when needed.

The CLI steps below cover the full subnet-discovery orchestrator path (local context, DNS list, Nmap, resolve, package). Use that path when you need approved CIDR discovery, not just a guided target-list survey.

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

Preferred: use the orchestrator (copies context to `logs/network_context/<site>_<run-id>/`):

```bash
bash survey/sas-cybernet-subnet-survey.sh --site "$SITE" --run-id "$RUN_ID" --mode local-context-only
```

Manual alternative:

```bash
bash survey/sas-device-snapshot.sh --output-dir logs/network_context
cmd.exe /c ipconfig /all > logs/network_context/ipconfig_all.txt
cmd.exe /c route print > logs/network_context/route_print.txt
cmd.exe /c arp -a > logs/network_context/arp_initial.txt
```

Look for:

- IPv4 address
- default gateway
- DNS suffix
- VLAN/subnet hints
- route table entries

Do not guess the scan scope from vibes. Confirm the CIDR with the lead or network source.

## Step 5 - DNS/list sanity and Nmap discovery

Preferred orchestrator path:

```bash
SUBNET_FILE="survey/output/local_subnet_finder/${SITE}_${RUN_ID}/subnet_candidates.txt"

bash survey/sas-cybernet-subnet-survey.sh --site "$SITE" --run-id "$RUN_ID" --mode dns-list-only --subnet-file "$SUBNET_FILE"
bash survey/sas-cybernet-subnet-survey.sh --site "$SITE" --run-id "$RUN_ID" --mode discover --subnet-file "$SUBNET_FILE"
```

**Nmap can help with:** live hosts, DNS names, MACs on local L2, and XML evidence for the resolver.

**Nmap does not provide serial numbers by itself.** Serial matching comes from manifests, trackers, AD/CMDB exports, or approved identity probes.

Appendix — commands the runner executes per CIDR:

```bash
nmap -sL "$CIDR" -oN "logs/nmap/${SITE}_<safe>_list_dns.txt"
nmap -sn -n --reason -oA "logs/nmap/${SITE}_<safe>_discovery_no_dns" "$CIDR"
nmap -sn --system-dns --reason -oA "logs/nmap/${SITE}_<safe>_discovery_dns" "$CIDR"
```

Start with one approved `/24` unless a lead explicitly approves a different CIDR. CIDRs broader than `/24` require `--allow-wide`. Public/non-RFC1918 CIDRs require `--allow-public`.

## Step 6 - Optional Windows service confirmation

Only run against a **small host list** from discovery output. **Naabu** is acceptable only for narrow port reachability confirmation on that list — not for subnet-wide discovery.

```bash
HOSTS="survey/output/cybernet_subnet_survey/${SITE}_${RUN_ID}/hosts/<safe_cidr>_up.txt"
bash survey/sas-cybernet-subnet-survey.sh --site "$SITE" --run-id "$RUN_ID" --mode confirm-windows --host-file "$HOSTS"
bash survey/sas-ensure-naabu.sh
bash survey/sas-cybernet-subnet-survey.sh --site "$SITE" --run-id "$RUN_ID" --mode confirm-windows \
  --host-file "$HOSTS" --confirm-tool naabu --pipe-followup
```

Naabu defaults: full Cybernet key ports via `keyports_cybernet_json` (`-p 80,443,135,445,3389,5985,5986 -ec -silent -json`). Narrow web-only: `--naabu-profile web_reachability_only_json`. UDP: `--udp-services`. Host discovery: `--host-discovery` (approved subnet scope). All ports: `--all-ports --allow-full-ports`.

Appendix — underlying nmap command:

```bash
nmap -sT -Pn -p 135,445,3389 --reason --open -iL "$HOSTS" -oA "logs/nmap/${SITE}_<safe>_windows_ports"
```

Do not pass a raw CIDR to confirm mode. Do not hand-build a huge list because you are impatient.

## Step 7 - Resolve Nmap evidence against the target manifest

```bash
bash survey/sas-cybernet-subnet-survey.sh \
  --site "$SITE" \
  --run-id "$RUN_ID" \
  --mode resolve-only \
  --manifest survey/output/cybernet_targets_resolved.csv
```

Optional `--nmap-xml PATH` overrides auto-picked `*_discovery_no_dns.xml`.

Manual alternative (same resolver the runner calls):
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

Preferred:

```bash
bash survey/sas-cybernet-subnet-survey.sh \
  --site "$SITE" \
  --run-id "$RUN_ID" \
  --mode package-only \
  --manifest survey/output/cybernet_targets_resolved.csv
```

Artifact directory: `survey/artifacts/${SITE}_${RUN_ID}/` with `PACKAGE_MANIFEST.txt`.

Manual alternative:

```bash
mkdir -p "survey/artifacts/${SITE}_${RUN_ID}"
cp survey/output/cybernet_targets_resolved.csv "survey/artifacts/${SITE}_${RUN_ID}/" 2>/dev/null || true
cp logs/network_context/"${SITE}_${RUN_ID}"/* "survey/artifacts/${SITE}_${RUN_ID}/" 2>/dev/null || true
cp logs/nmap/${SITE}_* "survey/artifacts/${SITE}_${RUN_ID}/" 2>/dev/null || true
```

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

**Dashboard path:** Start Cybernet Survey → copy posture/identity commands → optional reachability → Load Evidence → Review Results.

**CLI orchestrator path:**

```text
1. Pull repo.
2. Run Bash smoke test.
3. Copy approved target CSVs into survey/input.
4. Build manifest with sas-survey-targets.sh.
5. Run sas-cybernet-subnet-survey.sh modes (local-context, dns-list, discover, resolve, optional confirm, package).
6. Review exact/prefix/MAC/IP/missing results.
7. Package local artifacts under survey/artifacts/.
8. Do not commit live data.
```
