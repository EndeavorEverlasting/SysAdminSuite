# Cybernet Hardware Identity Map

Use this map when a task asks which discovered workstations are actually Cybernets, which candidates deserve a deeper probe, or whether a hostname should enter a Cybernet deployment workflow.

**Serial + model are the qualifying hardware evidence.** A Cybernet-looking hostname, AD object, subnet, ping reply, open port, or installed/missing application set is only candidate evidence.

## Identity rule

> Software footprint is not identity.

Cybernet deployments changed over time and some hospitals carried different application sets before standardization. Therefore:

- software presence does not confirm a Cybernet;
- software absence does not disqualify a Cybernet;
- a hostname convention does not confirm a Cybernet;
- AD presence does not confirm a Cybernet;
- DNS, ICMP, TCP, subnet, and site inference do not confirm a Cybernet;
- serial and model must both be observed and compared with an approved hardware reference before the Cybernet profile may be selected.

Unknown or conflicting evidence stops at read-only discovery.

## Repository surfaces

| Need | Canonical surface | What it proves |
|---|---|---|
| Professional computer-population signature scan | `survey/sas-run-windows-pc-signature.sh` | Against an approved computer host list, probes only TCP 135+445 with zero retries/rate 50; emits only dual-port candidates; **no metadata** |
| Local scanner-evidence filter | `survey/sas-filter-windows-pc-signature.py` | From existing Naabu evidence, requires both 135+445 before candidate promotion; performs no network activity |
| Low-noise explicit-host reachability | `sas network probe HOST01 HOST02 ...` / `survey/sas-network-preflight.ps1` | DNS/ping/selected-port posture only |
| Bounded model+serial identity canary | `sas cybernet canary HOST01 HOST02 ...` / `survey/sas-cybernet-canary.ps1` | Reuses current dual-port evidence; otherwise 135+445 preflight, then one DCOM/CIM session only after both ports open; hardware metadata only after `ProductType=1` |
| Bash read-only workstation identity | `bash/transport/sas-workstation-identity.sh` | Host/serial/MAC when approved transport succeeds; **no model field today** |
| Optional read-only WMI identity | `bash/transport/sas-wmi-identity.sh` | Host/serial/MAC when WMI succeeds; **no model field today** |
| Local hardware identity | `QRTasks/Get-ModelInfo.ps1` | Manufacturer, model, product identity, BIOS serial/version, board identity |
| Cybernet profile after identity | `Config/cybernet-client-preferences.json` | Configuration/software rules for a **proven eligible Cybernet**, not identity itself |
| Identity workflow | `harness/workflows/cybernet-hardware-identity-discovery.yaml` | Evidence ordering and classification |
| Artifact authority | `harness/api/cybernet-hardware-identity-artifact-registry.json` | Evidence roles, locations, tracking, proof ceilings |
| Repeatable procedure | `harness/skills/cybernet-hardware-identity/SKILL.md` | Fresh-agent execution path |
| Operator status | `harness/reports/CYBERNET_HARDWARE_IDENTITY_STATUS.md` | Working paths, known gaps, proof ceiling |
| Contract validator | `harness/validators/validate-cybernet-hardware-identity.py` | Anti-misclassification wiring |

## Workflow

1. **Computer population intake** — prefer passive/approved workstation sources: AD computer population, deployment trackers, prior inventory, approved sheets, CMDB/endpoint inventory, or existing local evidence. Do not begin with a broad service scan merely to discover printers/APs again.
2. **Reuse evidence first** — when complete current evidence is already available, reuse it instead of generating more packets.
3. **Minimal network signature** — for an approved computer host list, use `sas-run-windows-pc-signature.sh`. It spends only TCP 135+445, zero scan retries, rate 50, and promotes only hosts where both ports are observed. This is candidate evidence only.
4. **Bounded canary** — feed unresolved dual-port candidates to `sas cybernet canary` in batches of at most five explicit hosts. The command refuses CIDRs/ranges/wildcards and performs no subnet discovery.
5. **Prove workstation class** — after both ports open, the canary may create one read-only DCOM/CIM session and read `Win32_OperatingSystem.ProductType`. Only `ProductType=1` may advance to hardware metadata. Servers/DCs and unresolved OS class stop before model/serial queries.
6. **Collect hardware identity** — a confirmed Windows client workstation may return manufacturer/model and BIOS serial from the same bounded session; local `QRTasks/Get-ModelInfo.ps1` remains another approved model+serial source when physically on the workstation.
7. **Compare to an approved hardware reference** — keep the live reference local/untracked or in another explicitly approved source. Never invent model or serial rules from memory.
8. **Classify**:
   - `IDENTITY_INCOMPLETE` — serial or model is missing, or the reference cannot be resolved.
   - `CONFLICTING_IDENTITY` — evidence sources disagree; block profile selection.
   - `CONFIRMED_NON_CYBERNET` — an approved reference establishes the observed serial/model pair is not Cybernet hardware. Keep it as a known device and remove it from prime Cybernet targets.
   - `CONFIRMED_CYBERNET` — observed serial + observed model satisfy the approved Cybernet hardware reference.
9. **Profile gate** — only `CONFIRMED_CYBERNET` may load `Config/cybernet-client-preferences.json` or advance to Cybernet configuration/deployment lanes.
10. **Handoff** — report classification, evidence artifact pointers, reference authority, gaps, and the next read-only or deployment gate without committing live inventory.

## Commands

Professional network-signature lane terminal: **Git Bash / Bash-on-Windows**. The input is an approved computer host list, not a CIDR/range/wildcard.

```bash
bash survey/sas-run-windows-pc-signature.sh --list targets/local/approved_computers.txt
```

Metadata-canary operator terminal: **Windows PowerShell**. The installed `sas` front door is cwd-independent.

```powershell
sas cybernet canary HOST01 HOST02
```

Candidate-only network probe when model+serial identity is not yet required:

```powershell
sas network probe HOST01 HOST02
```

Legacy Bash serial/MAC identity remains available from a proven repository root, but it is not the preferred arbitrary-cwd field handoff because it still does not emit model:

```text
bash bash/transport/sas-workstation-identity.sh --targets-file targets/local/candidates.txt --allow-wmi --output survey/output/cybernet_identity_candidates.csv
```

Local model/serial identity on the workstation being examined:

```text
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\QRTasks\Get-ModelInfo.ps1
```

There is intentionally **no deployment command** in this identity workflow. Deployment becomes eligible only after `CONFIRMED_CYBERNET`.

## Known traps

- Starting Cybernet hunting with web/printer-aware ports and then treating every responder as a workstation candidate.
- Reusing the standardized six-app Cybernet software list as an identity signature.
- Treating a missing clinical-core app as evidence that a device is not a Cybernet.
- Treating an `OPR`-style hostname as proof of hardware class.
- Counting a dual-port 135+445 responder as a confirmed workstation; `ProductType=1` is still required before hardware metadata.
- Promoting model/serial evidence to `CONFIRMED_CYBERNET` without the approved hardware reference.
- Confusing low-noise discipline with stealth: normal monitoring may still log or alert on authorized survey traffic.
- Feeding CIDRs, IP ranges, or wildcards into the identity canary or professional host-list signature lane.
- Committing live hostnames, serials, model inventories, or site deployment data to Git.
- Selecting the Cybernet profile before hardware identity is resolved.

## Validation

```text
python harness/validators/validate-cybernet-hardware-identity.py
python Tests/survey/test_cybernet_hardware_identity_harness_completeness.py
python Tests/survey/test_windows_pc_signature_filter.py
bash survey/sas-generate-naabu-runtime-profiles.sh --check
bash -n survey/sas-run-windows-pc-signature.sh
pwsh -NoProfile -File tools/Test-Pester5Suite.ps1 -TestPath Tests/Pester/CybernetLowNoiseCanary.Tests.ps1
bash -n .githooks/pre-commit
bash -n .githooks/pre-push
git diff --check
```

## Proof ceiling

This harness can prove that repository routing requires serial + model + approved reference evidence before Cybernet profile selection, and that weaker network signals remain candidate-only. The professional signature lane proves only bounded 135+445 reachability; the canary additionally proves Windows client-workstation class before bounded model+serial collection. Neither surface itself proves a live target is a Cybernet, populates the approved hardware reference, authorizes deployment, or claims reduced monitoring visibility.
