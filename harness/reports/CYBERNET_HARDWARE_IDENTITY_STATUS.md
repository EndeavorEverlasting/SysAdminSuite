# Cybernet Hardware Identity Status

## WORKING

The repository already has useful read-only discovery surfaces:

- `sas network probe ...` / `survey/sas-network-preflight.ps1` for explicit-host DNS, ping, and bounded TCP posture;
- `bash/transport/sas-workstation-identity.sh` for host/serial/MAC collection through approved transports;
- `bash/transport/sas-wmi-identity.sh` for optional read-only WMI host/serial/MAC collection;
- `QRTasks/Get-ModelInfo.ps1` for local manufacturer, model, product identity, BIOS serial/version, and baseboard identity;
- `Config/cybernet-client-preferences.json` for the Cybernet configuration/software profile **after hardware identity is proven**.

The harness now routes Cybernet discovery through `harness/workflows/cybernet-hardware-identity-discovery.yaml` and records evidence roles in `harness/api/cybernet-hardware-identity-artifact-registry.json`.

## Identity standard

Cybernet identity requires:

1. observed serial;
2. observed model; and
3. a match against an approved hardware reference.

software footprint, software absence, hostname convention, AD presence, DNS, ping, open ports, subnet, and site inference are candidate signals only.

A standardized software set is a desired deployment state. It is not a hardware signature. Older or site-specific deployments may legitimately have different applications.

## KNOWN GAP

The current remote workstation/WMI identity adapters can collect serial but not model. Therefore a successful remote identity collection can still be `IDENTITY_INCOMPLETE` for Cybernet classification.

`QRTasks/Get-ModelInfo.ps1` supplies model + serial when the workstation can be examined locally. A future product/transport enhancement may add an approved remote model field, but that is outside this harness-only sprint.

No populated Cybernet model/serial allowlist is committed to Git. Live deployment inventory belongs in local ignored state or another approved external source.

## Classification behavior

- `IDENTITY_INCOMPLETE` — serial, model, or reference is missing.
- `CONFLICTING_IDENTITY` — evidence sources disagree; profile selection is blocked.
- `CONFIRMED_NON_CYBERNET` — approved reference establishes the observed serial/model identity is outside the Cybernet class. Keep it as a known device and exclude it from prime Cybernet targets.
- `CONFIRMED_CYBERNET` — observed serial + model satisfy the approved Cybernet hardware reference.

Only `CONFIRMED_CYBERNET` may advance to `Config/cybernet-client-preferences.json`.

## Known traps closed by this harness

- treating a Cybernet-style hostname as hardware proof;
- treating missing standardized applications as evidence against Cybernet identity;
- counting a responder as a found Cybernet;
- treating AD presence as device-class proof;
- promoting serial-only evidence when model is absent;
- inventing model/serial rules from memory;
- committing live device inventory to the repository;
- selecting deployment/configuration before hardware identity is resolved.

## Validation

```text
python harness/validators/validate-cybernet-hardware-identity.py
python Tests/survey/test_cybernet_hardware_identity_harness_completeness.py
bash -n .githooks/pre-commit
bash -n .githooks/pre-push
git diff --check
```

CI authority:

```text
.github/workflows/cybernet-hardware-identity-harness.yml
```

## What remains external

A live classification still requires:

- protected-network authority when the target must be contacted;
- an actual read-only source for serial;
- an actual read-only source for model;
- an approved hardware reference against which both are compared.

The harness does not manufacture those facts.

## Proof ceiling

Repository validation can prove the **identity gate and anti-misclassification contract**: serial + model + approved reference are required before Cybernet profile selection, and weaker signals cannot be promoted to identity. It does not prove any particular live workstation is or is not a Cybernet, target reachability, deployment success, or runtime acceptance.
