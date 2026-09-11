# Cybernet Hardware Identity Map

Use this map when a task asks which discovered workstations are actually Cybernets, which candidates deserve a deeper probe, or whether a hostname should enter a Cybernet deployment workflow.

**Serial + model are the qualifying hardware evidence.** A Cybernet-looking hostname, AD object, subnet, ping reply, open port, or installed/missing application set is only candidate evidence.

## Identity rule

> Software footprint is not identity.

Cybernet deployments changed over time and some hospitals carried different application sets before standardization. Therefore software presence/absence, hostname convention, AD presence, DNS/ICMP/TCP posture, subnet/site inference, and OUI are not Cybernet identity. Serial and model must both be observed and compared with an approved hardware reference before the Cybernet profile may be selected. Unknown or conflicting evidence stops at read-only discovery.

## Conservative exclusion rule

**Exclusion is not identification.** Before spending network-signature or endpoint-metadata work, existing approved evidence may remove a device from the Cybernet candidate lane only under `harness/api/cybernet-device-exclusion-registry.json`.

- authoritative exclusion evidence may stop already-proven printers, access points, Cronus/time clocks, servers, and other non-Cybernet devices at the stage explicitly authorized by that evidence type;
- weak/corroborating/strong evidence never accumulates into automatic exclusion authority;
- hostname patterns, software presence/absence, subnet/site inference, open ports, MAC OUI, and the 135+445 signature cannot auto-exclude;
- no new active query may be created solely to obtain exclusion evidence;
- conflicts or positive Cybernet hardware evidence block automatic exclusion and route to read-only identity review;
- other Windows computers require prior confirmed-non-Cybernet identity or approved hardware-reference evidence before pre-query exclusion.

Tracked exclusion policy contains no live entries. Live exclusions stay local/untracked or in another explicitly approved authority and bind to a stable device key rather than hostname/IP alone.

## The operator question

The primary technician front door is:

```cmd
C:\SASAL\Probe-Cybernet.cmd HOST01 HOST02
```

It asks: **Is each explicit candidate a Windows client workstation, and can it return model + serial for comparison with the approved Cybernet hardware reference?**

The CMD establishes repository currentness before target contact, re-enters the refreshed sealed runtime, and then spends only the bounded canary evidence necessary to answer that question. Do not substitute `sas network probe`, a broad key-port scan, or a software check when hardware identity is the question.

## Repository surfaces

| Need | Canonical surface | What it proves |
|---|---|---|
| Technician Cybernet identity front door | `Probe-Cybernet.cmd` | Current-main refresh before target contact, then one refreshed bounded identity canary with exit-code propagation |
| Conservative non-Cybernet exclusion | `harness/api/cybernet-device-exclusion-registry.json` + `docs/CYBERNET_DEVICE_EXCLUSION_REGISTRY.md` | Which existing evidence may safely stop printer/AP/time-clock/server/other-device follow-up; weak hints remain non-authoritative |
| Professional computer-population signature scan | `survey/sas-run-windows-pc-signature.sh` | Against an approved computer host list, probes only TCP 135+445 with zero retries/rate 50; emits only dual-port candidates; **no metadata** |
| Local scanner-evidence filter | `survey/sas-filter-windows-pc-signature.py` | From existing Naabu evidence, requires both 135+445 before candidate promotion; performs no network activity |
| Bounded model+serial identity canary | `survey/sas-cybernet-canary.ps1` | Reuses current evidence; otherwise 135+445 preflight, then one DCOM/CIM session only after both ports open; hardware metadata only after `ProductType=1` |
| Low-noise explicit-host reachability | `sas network probe HOST01 HOST02 ...` / `survey/sas-network-preflight.ps1` | DNS/ping/selected-port posture only; use only when reachability itself is the question |
| Bash read-only workstation identity | `bash/transport/sas-workstation-identity.sh` | Host/serial/MAC when approved transport succeeds; **no model field today** |
| Local hardware identity | `QRTasks/Get-ModelInfo.ps1` | Manufacturer, model, product identity, BIOS serial/version, board identity |
| Cybernet profile after identity | `Config/cybernet-client-preferences.json` | Configuration/software rules for a **proven eligible Cybernet**, not identity itself |
| Identity workflow | `harness/workflows/cybernet-hardware-identity-discovery.yaml` | Evidence ordering, conservative exclusion, and classification |
| Artifact authority | `harness/api/cybernet-hardware-identity-artifact-registry.json` | Evidence roles, locations, tracking, proof ceilings |
| Repeatable procedure | `harness/skills/cybernet-hardware-identity/SKILL.md` | Fresh-agent execution path |
| Contract validators | `harness/validators/validate-cybernet-hardware-identity.py` + `harness/validators/validate-cybernet-device-exclusion-registry.py` | Anti-misclassification and conservative exclusion wiring |

## Workflow

1. **Currentness before contact** — enter through `Probe-Cybernet.cmd`. It uses the repository-owned Guest/Internet refresh transaction to resolve current `origin/main`, reseal `C:\SASAL`, restore network posture, and re-enter the refreshed CMD before target contact.
2. **Computer population intake** — prefer passive/approved workstation sources: AD computer population, deployment trackers, prior inventory, approved sheets, CMDB/endpoint inventory, or existing local evidence.
3. **Reuse exclusion evidence first** — consult the device-exclusion registry against evidence already available. Anything weaker than authoritative remains in the candidate lane.
4. **Reuse identity evidence first** — complete current Cybernet identity evidence may be reused instead of generating more packets.
5. **Minimal PC signature** — unresolved candidates spend only TCP 135+445 before metadata candidacy. Both ports are required; the signature is candidate evidence only.
6. **Prove workstation class** — only after both ports open may the canary create one read-only DCOM/CIM session and read `Win32_OperatingSystem.ProductType`. Only `ProductType=1` may advance to hardware metadata.
7. **Collect hardware identity** — a confirmed Windows client workstation may return manufacturer/model and BIOS serial from the same bounded session.
8. **Compare to approved hardware reference** — never invent model/serial rules from memory. Live references remain local/untracked or in another explicitly approved source.
9. **Classify**:
   - `IDENTITY_INCOMPLETE` — serial/model/reference missing;
   - `CONFLICTING_IDENTITY` — evidence sources disagree; block profile selection;
   - `CONFIRMED_NON_CYBERNET` — approved reference proves observed hardware is outside the Cybernet class; preserve as known device and exclude from prime targets;
   - `CONFIRMED_CYBERNET` — observed serial + model satisfy the approved Cybernet hardware reference.
10. **Profile gate** — only `CONFIRMED_CYBERNET` may load `Config/cybernet-client-preferences.json` or enter deployment lanes.
11. **Handoff** — report exclusion disposition, hardware classification, ignored artifact paths, reference authority, gaps, and one next action without committing live inventory.

## Commands

Primary technician identity command — **CMD**:

```cmd
C:\SASAL\Probe-Cybernet.cmd HOST01 HOST02
```

Optional population-reduction signature lane — **Git Bash / Bash-on-Windows**:

```bash
bash survey/sas-run-windows-pc-signature.sh --list targets/local/approved_computers.txt
```

Candidate-only reachability — use only when reachability is the actual question:

```powershell
sas network probe HOST01 HOST02
```

Local model/serial identity on the workstation being examined:

```text
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\QRTasks\Get-ModelInfo.ps1
```

There is intentionally **no deployment command** in this identity workflow. Deployment becomes eligible only after `CONFIRMED_CYBERNET`.

## Known traps

- Running a generic reachability probe when the actual question is Cybernet hardware identity.
- Starting Cybernet hunting with web/printer-aware ports and treating every responder as a workstation candidate.
- Running new SNMP/HTTP/printer probes merely to prove a device should have been excluded.
- Treating several weak/strong hints as equivalent to one authoritative exclusion source.
- Rejecting an ordinary Windows computer merely because inventory says `computer`, `desktop`, or `workstation`.
- Reusing the standardized application list as an identity signature.
- Treating a Cybernet-style hostname as proof of hardware class.
- Counting a dual-port 135+445 responder as a confirmed workstation; `ProductType=1` is still required before hardware metadata.
- Promoting model/serial evidence to `CONFIRMED_CYBERNET` without the approved hardware reference.
- Feeding CIDRs, IP ranges, or wildcards into the identity canary.
- Committing live hostnames, serials, model inventories, exclusion entries, or site deployment data to Git.
- Skipping currentness because a local checkout appears clean.

## Validation

```text
python Tests/survey/test_cybernet_probe_cmd_contracts.py
python harness/validators/validate-cybernet-hardware-identity.py
python harness/validators/validate-cybernet-device-exclusion-registry.py
python Tests/survey/test_cybernet_hardware_identity_harness_completeness.py
python harness/validators/validate-operator-command-handoff.py
python Tests/survey/test_windows_pc_signature_filter.py
bash survey/sas-generate-naabu-runtime-profiles.sh --check
bash -n survey/sas-run-windows-pc-signature.sh
pwsh -NoProfile -File tools/Test-Pester5Suite.ps1 -TestPath Tests/Pester/CybernetLowNoiseCanary.Tests.ps1
git diff --check
```

## Proof ceiling

The harness can prove currentness-before-contact routing, bounded packet/metadata ordering, authoritative-only exclusion, and serial+model+approved-reference gating. Repository proof cannot establish that any live target is Cybernet, prove an external exclusion source is accurate, populate the approved hardware reference, authorize deployment, or prove field network/DCOM availability.
