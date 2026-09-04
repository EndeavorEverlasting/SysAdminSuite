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
| Low-noise explicit-host reachability | `sas network probe HOST01 HOST02 ...` / `survey/sas-network-preflight.ps1` | DNS/ping/selected-port posture only |
| Bounded model+serial identity canary | `sas cybernet canary HOST01 HOST02 ...` / `survey/sas-cybernet-canary.ps1` | Reuses fresh identity evidence; otherwise one 135/445 preflight plus one DCOM/CIM identity session only when 135 opens |
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

1. **Candidate intake** — start from passive/approved sources: AD reconciliation, deployment trackers, prior inventory, approved sheets, or existing local evidence. Naming convention, software observations, or site clues may nominate a host but do not identify it.
2. **Reuse evidence first** — when complete model+serial evidence is fresh, reuse it instead of generating more packets.
3. **Bounded canary** — for unresolved candidates, use `sas cybernet canary` in batches of at most five explicit hosts. The command refuses CIDRs/ranges/wildcards and performs no subnet discovery.
4. **Collect hardware identity** — the canary attempts one DCOM/CIM identity session only after TCP 135 opens; local `QRTasks/Get-ModelInfo.ps1` remains a second approved model+serial source when physically on the workstation.
5. **Compare to an approved hardware reference** — keep the live reference local/untracked or in another explicitly approved source. Never invent model or serial rules from memory.
6. **Classify**:
   - `IDENTITY_INCOMPLETE` — serial or model is missing, or the reference cannot be resolved.
   - `CONFLICTING_IDENTITY` — evidence sources disagree; block profile selection.
   - `CONFIRMED_NON_CYBERNET` — an approved reference establishes the observed serial/model pair is not Cybernet hardware. Keep it as a known device and remove it from prime Cybernet targets.
   - `CONFIRMED_CYBERNET` — observed serial + observed model satisfy the approved Cybernet hardware reference.
7. **Profile gate** — only `CONFIRMED_CYBERNET` may load `Config/cybernet-client-preferences.json` or advance to Cybernet configuration/deployment lanes.
8. **Handoff** — report classification, evidence artifact pointers, reference authority, gaps, and the next read-only or deployment gate without committing live inventory.

## Commands

Preferred operator terminal for the field canary: **Windows PowerShell**. The installed `sas` front door is cwd-independent.

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

- Reusing the standardized six-app Cybernet software list as an identity signature.
- Treating a missing clinical-core app as evidence that a device is not a Cybernet.
- Treating an `OPR`-style hostname as proof of hardware class.
- Counting a ping responder or port-open host as a discovered Cybernet.
- Promoting serial-only WMI evidence to `CONFIRMED_CYBERNET` when model is still unknown.
- Confusing low-noise discipline with stealth: normal monitoring may still log or alert on authorized canary traffic.
- Feeding CIDRs, IP ranges, or wildcards into the identity canary.
- Committing live hostnames, serials, model inventories, or site deployment data to Git.
- Selecting the Cybernet profile before hardware identity is resolved.

## Validation

```text
python harness/validators/validate-cybernet-hardware-identity.py
python Tests/survey/test_cybernet_hardware_identity_harness_completeness.py
pwsh -NoProfile -File tools/Test-Pester5Suite.ps1 -TestPath Tests/Pester/CybernetLowNoiseCanary.Tests.ps1
bash -n .githooks/pre-commit
bash -n .githooks/pre-push
git diff --check
```

## Proof ceiling

This harness can prove that repository routing requires serial + model + approved reference evidence before Cybernet profile selection, and that known weaker signals remain candidate-only. The canary adds bounded read-only model+serial collection but does not itself prove a live target is a Cybernet, populate the approved hardware reference, authorize deployment, or claim reduced monitoring visibility.
