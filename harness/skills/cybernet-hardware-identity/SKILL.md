# Cybernet Hardware Identity Skill

## Trigger

Use this skill when the task is to find deployed Cybernets, decide whether a workstation is actually a Cybernet, reconcile Cybernet candidates, interpret a Cybernet-looking hostname, or collect serial/model identity before selecting the Cybernet profile.

Do not use this skill to deploy software, change AutoLogon, configure hardware, mutate Active Directory, broaden into subnet scanning, or modify `AGENTS.md`.

## Core rule

**Software presence or absence never confirms or disqualifies a Cybernet.**

Hospitals may carry different historical software footprints, and the standardized application set is a deployment desired state rather than a hardware identity signature.

**Serial and model are both required** before the workflow may classify `CONFIRMED_CYBERNET`. They must be compared with an approved hardware reference. A hostname convention, AD object, DNS result, ping response, open port, subnet, site inference, MAC, or software list can nominate a candidate but cannot open the Cybernet profile gate.

**Exclusion is conservative and evidence-bound.** Existing approved evidence may prevent unnecessary Cybernet probing only when `harness/api/cybernet-device-exclusion-registry.json` explicitly permits that evidence type at that stage. Weak, corroborating, and strong hints never accumulate into automatic exclusion authority, and no new active query is run solely to obtain exclusion evidence.

## Required inputs

- explicit candidate hostname/FQDN list
- current repository truth
- existing approved exclusion evidence when available
- approved protected-network authority when a live read-only probe is needed
- observed serial evidence
- observed model evidence
- approved hardware reference, kept local/untracked or supplied from another explicitly approved source

## Canonical surfaces

- map: `harness/maps/CYBERNET_HARDWARE_IDENTITY_MAP.md`
- workflow: `harness/workflows/cybernet-hardware-identity-discovery.yaml`
- identity artifact registry: `harness/api/cybernet-hardware-identity-artifact-registry.json`
- conservative exclusion registry: `harness/api/cybernet-device-exclusion-registry.json`
- exclusion doctrine: `docs/CYBERNET_DEVICE_EXCLUSION_REGISTRY.md`
- network preflight: `survey/sas-network-preflight.ps1` or `sas network probe ...`
- workstation identity: `bash/transport/sas-workstation-identity.sh`
- optional WMI identity: `bash/transport/sas-wmi-identity.sh`
- local model/serial identity: `QRTasks/Get-ModelInfo.ps1`
- profile authority after confirmation only: `Config/cybernet-client-preferences.json`
- validators: `harness/validators/validate-cybernet-hardware-identity.py` and `harness/validators/validate-cybernet-device-exclusion-registry.py`
- operator status: `harness/reports/CYBERNET_HARDWARE_IDENTITY_STATUS.md`

## Procedure

### 1. Establish candidate status

Start from an explicit bounded list. Record why each host is a candidate, but keep the reason below the identity proof boundary.

Allowed candidate signals include:

- Cybernet-style hostname convention
- AD-backed computer object
- previous inventory or deployment worksheet
- software observations
- site/subnet clue
- DNS resolution
- ping/TCP response

None of those signals can classify the device.

### 2. Reuse authoritative exclusion evidence before spending new queries

Consult `harness/api/cybernet-device-exclusion-registry.json` against evidence that already exists.

The default is `DO_NOT_EXCLUDE`.

A printer, access point, Cronus/time clock, server, or other non-Cybernet device may stop before network-signature or endpoint-metadata work only when an allowed `AUTHORITATIVE` source is bound to the same stable device. Examples include an approved explicit CMDB/asset class, approved printer/network-controller/time-clock inventory, a prior SysAdminSuite confirmed-non-Cybernet decision, or an approved hardware-reference decision.

Do **not** turn these into exclusion authority:

- hostname patterns;
- software presence or absence;
- subnet/site inference;
- open TCP ports;
- MAC OUI/vendor;
- the 135+445 candidate signature;
- AD `OperatingSystem` text by itself;
- existing HTTP/SNMP hints.

Weak, corroborating, and strong evidence never accumulates into authority. Do not run new SNMP, HTTP, printer, RDP, or other endpoint queries merely to exclude a target.

A generic `computer`, `desktop`, or `workstation` inventory label is not enough to exclude another computer: Cybernets are Windows workstations. Pre-query exclusion of another computer requires prior confirmed-non-Cybernet identity or an approved hardware-reference result.

If credible exclusion evidence conflicts, or positive Cybernet hardware evidence exists, use `REVIEW_REQUIRED_NO_AUTO_EXCLUSION` and continue only through read-only identity review.

### 3. Run only the read-only probe that is earned

For candidates not authoritatively excluded, if network evidence is needed, use the low-noise explicit-target path. Do not scan a subnet to compensate for incomplete identity.

Example:

```text
sas network probe HOST01 HOST02
```

A responder is still only a candidate.

### 4. Prove workstation class before hardware metadata

In the professional canary, a dual-port 135+445 candidate may enter the existing read-only workstation-class gate. `Win32_OperatingSystem.ProductType` must equal `1` before manufacturer/model/serial are queried.

A current `ProductType` other than `1` may stop the same canary before hardware metadata. Do not add a separate ProductType query solely to populate exclusion evidence.

### 5. Collect serial evidence

Use the existing read-only workstation identity adapter when authorized:

```text
bash bash/transport/sas-workstation-identity.sh --targets-file targets/local/candidates.txt --allow-wmi --output survey/output/cybernet_identity_candidates.csv
```

The current adapter can return `ObservedSerial`, but it does not return model. Serial-only evidence remains `IDENTITY_INCOMPLETE`.

### 6. Collect model evidence

For a locally observed workstation, run:

```text
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\QRTasks\Get-ModelInfo.ps1
```

That surface emits manufacturer, model, product identity, BIOS serial/version, and board identity.

For remote work, use only another explicitly approved read-only source that actually returns model. Do not invent a remote model query in the harness lane; product/transport enhancement is a separate scope.

### 7. Compare with the approved hardware reference

The reference may be an operator-provided inventory, approved external system, or local ignored reference file. It must not be fabricated or committed when it contains live inventory.

Use exact evidence. Do not create fuzzy model aliases or serial exceptions from memory.

### 8. Classify

- `IDENTITY_INCOMPLETE` — serial, model, or reference authority is missing.
- `CONFLICTING_IDENTITY` — sources disagree; block profile selection.
- `CONFIRMED_NON_CYBERNET` — the approved reference establishes the observed serial/model hardware is not Cybernet. Preserve the device in a known-device list and apply `KEEP_AS_KNOWN_DEVICE_EXCLUDE_FROM_CYBERNET_TARGETS`.
- `CONFIRMED_CYBERNET` — serial + model satisfy the approved Cybernet hardware reference.

### 9. Gate the profile

Only `CONFIRMED_CYBERNET` may load `Config/cybernet-client-preferences.json` and proceed into Cybernet-specific configuration/software/AutoLogon workflows.

Do not use missing applications as a reason to exclude a device. Missing applications can become a **deployment gap after identity is confirmed**, not an identity conclusion.

### 10. Hand off

Report:

- candidate count;
- exclusion disposition count;
- classification count;
- artifact paths;
- exclusion/reference authority;
- exact missing field for incomplete devices;
- whether the Cybernet profile gate is open;
- one executable next action.

Never commit live hostnames, serial numbers, model inventories, exclusion entries, credentials, or raw field evidence.

## Failure handling

- Weak/strong/corroborating non-Cybernet hints: `DO_NOT_EXCLUDE`; keep the candidate unless stronger approved authority already exists.
- Conflicting exclusion evidence: `REVIEW_REQUIRED_NO_AUTO_EXCLUSION`.
- WMI/identity transport failure: keep the candidate unresolved; do not infer non-Cybernet.
- Serial collected but model missing: `IDENTITY_INCOMPLETE`.
- Model collected but serial missing: `IDENTITY_INCOMPLETE`.
- Software mismatch: no identity or exclusion effect.
- Hostname looks correct but hardware conflicts: hardware/reference evidence wins.
- Known non-Cybernet device using the naming convention: preserve as a known device and exclude it from prime Cybernet targets only with approved evidence bound to that device.
- Reference unavailable: stop at read-only evidence collection and report the exact reference dependency.

## Validation

```text
python harness/validators/validate-cybernet-hardware-identity.py
python harness/validators/validate-cybernet-device-exclusion-registry.py
python Tests/survey/test_cybernet_hardware_identity_harness_completeness.py
git diff --check
```

## Expected outputs

- local/untracked exclusion decision when applicable
- local/untracked network/identity evidence as applicable
- local/untracked hardware identity decision
- classification that cannot exceed the available serial/model/reference proof
- clean handoff with the profile gate state
- tracked harness/report/validator changes only when maintaining this harness

## Proof ceiling

This skill can prove that the repository requires conservative, authoritative exclusion evidence before skipping Cybernet survey work and requires hardware identity before Cybernet profile selection. It cannot prove a live external inventory record is accurate, prove a live workstation is a Cybernet without observed serial + model + approved reference evidence, or authorize deployment.
