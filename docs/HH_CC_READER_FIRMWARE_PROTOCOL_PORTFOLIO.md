# H&H CC Reader Firmware Protocol Portfolio

Date: 2026-10-04
Status: P95 IMPLEMENTED — protocol inventory + deterministic selector
Repository: `EndeavorEverlasting/SysAdminSuite`

## Mission

Preserve every credible firmware-management protocol as an additive adapter and deterministically rank the next **observation** path from hospital/device evidence.

This program does **not** assume that every H&H site, terminal generation, processor, reseller relationship, or management enrollment uses the same update path.

The selector answers:

> Given what this hospital/device currently proves about its management plane, which protocol should we inspect next, and which alternatives remain available?

It does **not** answer:

> Are we authorized to mutate this reader?

Mutation authority remains a separate live-execution gate.

## Canonical owners

- Protocol catalog: `harness/api/hh-cc-reader-firmware-protocols.v1.json`
- Deterministic selector: `harness/api/hh_cc_reader_firmware_protocols.py`
- Live-execution boundary: `harness/api/hh-cc-reader-live-execution-boundary.v1.json`
- P95 recurrence proof: `Tests/survey/test_hh_cc_reader_firmware_protocol_contracts.py`
- Downstream project consumer: `EndeavorEverlasting/nyc-hh-fieldops-lab` through P04

## Protocol portfolio

| Protocol ID | Control plane | Default posture | Why it remains modeled |
| --- | --- | --- | --- |
| `experian_control_center` | Experian / AxiaMed healthcare device management | Preferred when evidenced | PAX publicly documents AxiaMed Control Center managing and remotely updating PAX Android devices including A80. |
| `provider_tms_ntms` | Provider TMS / NTMS | Preferred when evidenced | A80 deployments can expose a device-initiated firmware pull through an existing provider TMS/TID configuration. |
| `provider_managed_automatic` | Acquirer / PSP managed service | Preferred when provider-owned | Some estates intentionally abstract the package and deliver updates automatically. |
| `paxstore_reseller_push` | PAXSTORE Administrator Center / reseller | Last resort or corroboration by default | Production-capable and authoritative for package/firmware inventory, support escalation, and remote push, but not the global default when an estate-specific path is already evidenced. |
| `pax_partner_paydroid_tool` | PAX Partner / local PayDroid tooling | Lab only | Retained for authorized signed-package lab work; never auto-promoted onto a production hospital reader. |

Protocols are additive. Selecting one does not delete, invalidate, or rewrite evidence for another.

## Default preference

The default observation order is:

1. Experian / AxiaMed Control Center
2. Provider TMS / NTMS
3. Provider-managed automatic update
4. PAXSTORE reseller / Administrator Center
5. PAX Partner / PayDroid Tool (lab only)

A hospital/site profile may reorder known production protocols when current evidence supports a different local configuration.

PAXSTORE therefore remains fully represented and production-capable while serving as a default fallback/corroboration path rather than the mandatory first technical path.

## Dendritic execution model — observe / acquire / transport

Firmware execution now has three independent branches that converge only when mutation is ready:

```text
                         controlled firmware outcome
                           /        |        \
                          /         |         \
              OBSERVE CURRENT   ACQUIRE       TRANSPORT
                  STATE         PACKAGE/       UPDATE
                               DELIVERY
                   |              |              |
          Control Center     provider/PSP     Control Center
          provider TMS      TMS catalog      TMS pull
          provider state    partner portal   provider-managed
          device-local      vendor support   PAXSTORE fallback
          PAXSTORE fallback PAXSTORE fallback lab tool
```

A branch can be supplied by a different authorized system than the others. For example, Kiosk4 current firmware may be observed locally or in Control Center while the package/version mapping comes from the provider or authorized partner channel and deployment uses TMS.

### Artifact-acquisition portfolio

| Acquisition source | Posture | Actionable output |
| --- | --- | --- |
| estate provider / acquirer / PSP / ISO support | primary when provider owns delivery | approved package/version mapping, provider-supplied package, or provider-triggered delivery |
| provider TMS / NTMS catalog | primary when device is TMS-bound | package identity plus device-initiated/provider delivery |
| authorized PAX partner/dealer portal | authorized artifact source | signed PAX software/firmware plus metadata |
| PAX/vendor support channel | escalation source | supported version path, package guidance, or correct channel owner |
| PAXSTORE firmware list | fallback/corroboration | firmware inventory/package labels and optional remote-push candidate |
| public web | discovery only | protocol manuals, support routes, version-domain clues; never global package-absence proof |

This is why PAXSTORE search completeness is not the technical critical path.

## Selection contract

Input is sanitized configuration/evidence, not credentials:

- `site_profile` — optional H&H organization/site profile artifact with profile id, organization id, scope, status, authority reference, optional site id, preference order, and disabled protocols;
- `evidence_signals` — observed management-plane/device signals;
- `authority_signals` — independently proven mutation-authority signals;
- `proven_gates` — live execution gates already proven.

Read-only ranking may proceed without a proven site profile, but mutation-readiness remains `BLOCKED_SITE_PROFILE` until the supplied profile is H&H-scoped and status `PROVEN`. Site overrides require an explicit site id. This preserves discovery usefulness without allowing an arbitrary or unknown hospital context to inherit mutation assumptions.

Disabled or unobserved protocols remain in the output. They do not disappear.

The governed Windows front door is:

```cmd
Select-HHCCReaderFirmwareProtocol.cmd CONTEXT_JSON
```

It runs deterministic selection plus a protocol-specific **read-only observation dispatcher** and propagates nonzero exit codes. The dispatcher consumes `primary_protocol`; it does not perform a firmware update.

Output includes:

- primary protocol for the next observation, when a production path is evidenced;
- evidenced fallbacks;
- every preserved protocol;
- per-protocol observation state;
- missing authority signals;
- missing live gates;
- mutation-readiness classification;
- `mutation_authorized=false` unconditionally.

`ELIGIBLE_FOR_SEPARATE_MUTATION_DECISION` is not mutation authority. It means only that evidence/authority/gate prerequisites represented by this selector are present and the independent live mutation decision may proceed.

## Site-switch examples

### Site A — Control Center + TMS evidence

Default selection:

`experian_control_center -> provider_tms_ntms -> ... -> paxstore_reseller_push`

The TMS path remains an evidenced fallback.

### Site B — TMS is the known local owner

A site-specific preference may place `provider_tms_ntms` before Control Center without changing the global catalog.

### Site C — only PAXSTORE is evidenced

`paxstore_reseller_push` becomes the primary production observation path even though its default posture is fallback/corroboration.

### Lab target

Partner/PayDroid tooling may be evidenced and even satisfy lab gates, but it never becomes a production primary automatically.

## Public corroboration

- PAXSTORE currently advertises fleet control and remote firmware/application updates: https://www.pax.us/marketplace/
- PAX / AxiaMed describe Control Center as a cloud system that can secure, manage, monitor, and remotely update PAX Android devices including A80: https://www.pax.us/about/press-room/pax-technology-inc-and-axiamed-partner-to-provide-optimal-healthcare-payment-experience-with-android-based-a920-a80/
- BridgePay documents PAXSTORE Terminal Management -> App & Firmware -> Push Firmware for A-series devices: https://bridgepaynetwork.atlassian.net/wiki/spaces/DC/pages/215744615/PAX%2BA-Series%2BDeployment%2BInstructions
- Planet documents an A80 device-side Config -> Update -> Firmware path using a provider TMS/TID: https://www.weareplanet.com/sites/default/files/Customer%20Resources/HTML/A80%20Setup%20and%20User%20Guide_0.html

These sources establish protocol families and management patterns. They do not prove that a specific H&H reader is enrolled in a specific plane or that any public example configuration belongs to H&H.

## P04 handoff

P95 owns technical protocol inventory and deterministic selection semantics.

P04 downstream may:

- store site/hospital project preference and evidence state;
- consume a P95 selection receipt;
- project protocol status into private project-management / presentation artifacts;
- preserve fallbacks and blocker state.

P04 may **not** independently rename a P95 protocol, manufacture technical evidence, promote a fallback to authority, or turn presentation/project status into live firmware proof.

## Current Kiosk4 consequence

The missing authoritative `current_firmware_value` still blocks `BASELINE_LOCKED`.

The next live observation should be selected from current site/device management evidence rather than hard-coded to PAXSTORE.

PAXSTORE remains available for corroboration/fallback and support escalation. Partner tooling remains lab-only. No protocol selection permits a push/update during the observation pass.

## Proof ceiling

Repository contracts/tests can prove additive inventory, ranking behavior, site overrides, fallback retention, and fail-closed mutation-readiness semantics.

They do not prove live hospital enrollment, package/version-domain identity, credentials/entitlement, mutation authorization, firmware deployment, rollback, or post-update runtime behavior.
