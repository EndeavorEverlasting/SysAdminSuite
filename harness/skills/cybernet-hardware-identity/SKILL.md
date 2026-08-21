# Cybernet Hardware Identity Skill

## Trigger

Use this skill when the task is to find deployed Cybernets, decide whether a workstation is actually a Cybernet, reconcile Cybernet candidates, interpret a Cybernet-looking hostname, or collect serial/model identity before selecting the Cybernet profile.

Do not use this skill to deploy software, change AutoLogon, configure hardware, mutate Active Directory, broaden into subnet scanning, or modify `AGENTS.md`.

## Core rule

**Software presence or absence never confirms or disqualifies a Cybernet.**

Hospitals may carry different historical software footprints, and the standardized application set is a deployment desired state rather than a hardware identity signature.

**Serial and model are both required** before the workflow may classify `CONFIRMED_CYBERNET`. They must be compared with an approved hardware reference. A hostname convention, AD object, DNS result, ping response, open port, subnet, site inference, MAC, or software list can nominate a candidate but cannot open the Cybernet profile gate.

## Required inputs

- explicit candidate hostname/FQDN list
- current repository truth
- approved protected-network authority when a live read-only probe is needed
- observed serial evidence
- observed model evidence
- approved hardware reference, kept local/untracked or supplied from another explicitly approved source

## Canonical surfaces

- map: `harness/maps/CYBERNET_HARDWARE_IDENTITY_MAP.md`
- workflow: `harness/workflows/cybernet-hardware-identity-discovery.yaml`
- artifact registry: `harness/api/cybernet-hardware-identity-artifact-registry.json`
- network preflight: `survey/sas-network-preflight.ps1` or `sas network probe ...`
- workstation identity: `bash/transport/sas-workstation-identity.sh`
- optional WMI identity: `bash/transport/sas-wmi-identity.sh`
- local model/serial identity: `QRTasks/Get-ModelInfo.ps1`
- profile authority after confirmation only: `Config/cybernet-client-preferences.json`
- validator: `harness/validators/validate-cybernet-hardware-identity.py`
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

### 2. Run only the read-only probe that is earned

If network evidence is needed, use the low-noise explicit-target path. Do not scan a subnet to compensate for incomplete identity.

Example:

```text
sas network probe HOST01 HOST02
```

A responder is still only a candidate.

### 3. Collect serial evidence

Use the existing read-only workstation identity adapter when authorized:

```text
bash bash/transport/sas-workstation-identity.sh --targets-file targets/local/candidates.txt --allow-wmi --output survey/output/cybernet_identity_candidates.csv
```

The current adapter can return `ObservedSerial`, but it does not return model. Serial-only evidence remains `IDENTITY_INCOMPLETE`.

### 4. Collect model evidence

For a locally observed workstation, run:

```text
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\QRTasks\Get-ModelInfo.ps1
```

That surface emits manufacturer, model, product identity, BIOS serial/version, and board identity.

For remote work, use only another explicitly approved read-only source that actually returns model. Do not invent a remote model query in the harness lane; product/transport enhancement is a separate scope.

### 5. Compare with the approved hardware reference

The reference may be an operator-provided inventory, approved external system, or local ignored reference file. It must not be fabricated or committed when it contains live inventory.

Use exact evidence. Do not create fuzzy model aliases or serial exceptions from memory.

### 6. Classify

- `IDENTITY_INCOMPLETE` — serial, model, or reference authority is missing.
- `CONFLICTING_IDENTITY` — sources disagree; block profile selection.
- `CONFIRMED_NON_CYBERNET` — the approved reference establishes the observed serial/model hardware is not Cybernet. Preserve the device in a known-device list and apply `KEEP_AS_KNOWN_DEVICE_EXCLUDE_FROM_CYBERNET_TARGETS`.
- `CONFIRMED_CYBERNET` — serial + model satisfy the approved Cybernet hardware reference.

### 7. Gate the profile

Only `CONFIRMED_CYBERNET` may load `Config/cybernet-client-preferences.json` and proceed into Cybernet-specific configuration/software/AutoLogon workflows.

Do not use missing applications as a reason to exclude a device. Missing applications can become a **deployment gap after identity is confirmed**, not an identity conclusion.

### 8. Hand off

Report:

- candidate count;
- classification count;
- artifact paths;
- reference authority;
- exact missing field for incomplete devices;
- whether the Cybernet profile gate is open;
- one executable next action.

Never commit live hostnames, serial numbers, model inventories, credentials, or raw field evidence.

## Failure handling

- WMI/identity transport failure: keep the candidate unresolved; do not infer non-Cybernet.
- Serial collected but model missing: `IDENTITY_INCOMPLETE`.
- Model collected but serial missing: `IDENTITY_INCOMPLETE`.
- Software mismatch: no identity effect.
- Hostname looks correct but hardware conflicts: hardware/reference evidence wins.
- Known non-Cybernet device using the naming convention: preserve as a known device and exclude it from prime Cybernet targets.
- Reference unavailable: stop at read-only evidence collection and report the exact reference dependency.

## Validation

```text
python harness/validators/validate-cybernet-hardware-identity.py
python Tests/survey/test_cybernet_hardware_identity_harness_completeness.py
git diff --check
```

## Expected outputs

- local/untracked network/identity evidence as applicable
- local/untracked hardware identity decision
- classification that cannot exceed the available serial/model/reference proof
- clean handoff with the profile gate state
- tracked harness/report/validator changes only when maintaining this harness

## Proof ceiling

This skill can prove that the repository requires hardware identity before Cybernet profile selection and can organize read-only identity evidence. It cannot prove a live workstation is a Cybernet without observed serial + model + approved reference evidence, and it cannot authorize deployment.
