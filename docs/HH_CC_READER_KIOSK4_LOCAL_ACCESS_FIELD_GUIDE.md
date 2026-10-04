# H&H CC Reader — Kiosk4 Local Access + Input Method Field Guide

Status: CURRENT LIVE GATE — `BASELINE_LOCKED / BLOCKED_EVIDENCE`  
Date: 2026-10-04  
Floor: `main@696d1382d094373c6de76e2eaa59b1fd0331421e`  
Scope: sanitized P111 derivative of the private H&H operator guide  
Mutation authority: `false`

## Read first — the problem is already narrow

Do not restart the AxiaMed admin-path discovery, Netstat/START TEST, Connectivity Test, PAXSTORE marketplace evidence work, or protocol selection merely to obtain newer timestamps.

The same Kiosk4 identity is already resolved. The missing live evidence is one authoritative, labeled `current_firmware_value` bound to that same identity.

The remaining **local human-input** question is narrower: can the second PAX/Android Settings credential prompt be made to accept the already-authorized alphanumeric credential from private operator documentation? If that input barrier cannot be corrected by the bounded tests below, close the local-input branch and continue through an authenticated management/provider surface.

## Current state

| Gate | State | Meaning |
| --- | --- | --- |
| Kiosk4 identity | `UNIQUE_TARGET_RESOLVED` | Same-device identity is already proved outside tracked source. |
| Native keypad / exposed local alpha entry | `PROVEN_BLOCKED / RETIRED_DISCOVERY` | Repeated FUNC/alpha/tap/hold/combo attempts on this provisioned reader did not produce alphabetic input. |
| P95 protocol selector | `CLOSED` | Existing receipt preserved all configured protocols, selected no production route, and kept `mutation_authorized=false`. |
| PAXSTORE / P111 marketplace corpus | `CLOSED_FOR_THIS_GATE` | Presentation/context evidence only; do not replay it as a firmware-observation prerequisite. |
| Current firmware | `LIVE_VALUE_NOT_CAPTURED` | Authoritative labeled installed value remains missing. |
| `BASELINE_LOCKED` | `BLOCKED_EVIDENCE` | Freeze waits for the labeled current value. |
| Campaign target `2.0.15.260522` | `TARGET_ONLY` | Never substitute the target for the observed current value. |

## Already exhausted — do not repeat

The following are not open discovery branches unless new evidence proves the device/application state materially changed:

- FUNC / alpha key combinations;
- tap / hold / simultaneous-key experiments intended to coax letters from the exposed numeric input;
- date-based or broad password guessing;
- Netstat START TEST and Connectivity Test solely to create a newer run;
- PAXSTORE App Store keyword searching as the default firmware route;
- protocol selection with the same empty evidence context.

Generic A80 documentation can describe platform capability, but it does not override direct observation of the provisioned H&H Kiosk4.

## Today's local objective

Reach one of two deterministic outcomes:

1. **Input workaround classified** and a read-only labeled software/version surface becomes accessible; or
2. **Local-input branch cleanly closed** with a specific classification, allowing the program to pivot to the authorized management/provider observation plane.

Do not turn the field window into open-ended peripheral or password experimentation.

## 1. Reach the second credential prompt

Use the already-authorized private H&H procedure to reach the first admin layer and then the second PAX/Android Settings credential prompt.

Do not restage network diagnostics on the way there.

At the second prompt, stop before submitting credentials and classify the available input method.

## 2. One input-method switch attempt — only when a real selector is visible

With the second credential field focused, inspect once for a real Android input-method selector such as:

- a keyboard/input icon;
- a globe/input control; or
- a visible `Choose/Change input method` control.

If an actual selector is present, choose the full Android/AOSP keyboard when offered.

Test one alphabetic character and one symbol, then clear the field.

- both register -> `INPUT_METHOD=ALPHANUMERIC_ACCEPTED`
- no selector exists -> `INPUT_METHOD=IME_SWITCHER_UNAVAILABLE`
- selector changes but field still filters non-digits -> continue to the external-HID classifier below

Do **not** repeat generic tapping, holding, swiping, FUNC, or alpha-key discovery after this bounded check.

## 3. One wired-keyboard classification

Use one known-good wired USB keyboard through the A80's USB Host interface first. This is a classification experiment, not a claim that the H&H image must accept generic HID input.

With the second credential field empty:

1. enter one alphabetic character and observe whether a masked character appears;
2. clear the field;
3. enter one symbol and observe;
4. clear the field;
5. enter one digit and observe;
6. clear the field.

Classify exactly one result:

| Result | Meaning | Transition |
| --- | --- | --- |
| `EXTERNAL_HID_ALPHANUMERIC_ACCEPTED` | alpha + symbol + digit all register | proceed to one authorized credential attempt |
| `FIELD_NUMERIC_FILTER` | digit registers; alpha/symbol do not | stop local input work; application/prompt restriction established |
| `EXTERNAL_HID_NOT_ACCEPTED` | test input does not register | stop generic-HID work; route specialized hardware questions to provider/research lane |
| `AMBIGUOUS` | behavior cannot be observed confidently | preserve evidence and stop rather than improvise |

If `FIELD_NUMERIC_FILTER`, do not assume a scanner will bypass the same field character policy.

If `EXTERNAL_HID_NOT_ACCEPTED`, do not escalate the field visit into random scanner, Bluetooth, serial, PIN-pad, OTG-power-chain, or service-cable experimentation. Provider-specific input/service hardware becomes a separate research/provider branch.

## 4. Credential gate — only after alphanumeric input works

Use the authorized alphanumeric Settings credential from **private operator documentation only**.

Attempt the documented credential once.

- accepted -> `CREDENTIAL_STATE=ACCEPTED`; remain read-only
- rejected after alpha/symbol entry is visibly working -> `CREDENTIAL_STATE=REJECTED_INPUT_SOLVED`

Do not brute-force alternatives.

Credential rejection and input-method failure are different evidence states.

**Repository boundary:** no credential value belongs in tracked source, issues, public screenshots, examples, or receipts.

## 5. After access — capture labels, not interpretations

Do **not** open or invoke Firmware Update, Push, Download, reset, assignment, or configuration actions simply because Settings access succeeds.

Navigate only through read-only information surfaces, for example:

- About device;
- Software versions;
- System information;
- Terminal information; or
- a provider/payment application's read-only Info surface.

Capture:

```text
source_surface
navigation_path
section_heading
field_label
displayed_value
captured_at
identity_binding_reference
notes
```

Requirements:

- preserve the exact section/title and exact field label;
- capture every relevant visible version string rather than choosing one in the field;
- preserve the raw image privately;
- bind the observation to the existing private identity receipt;
- do not copy live serial, MAC, IPv4, credentials, session data, or private evidence URLs into Git;
- do not promote Android build, application version, package version, or another numeric string to `current_firmware_value` until version-domain classification proves the mapping.

## 6. Classify first; freeze second

After a private labeled observation exists:

1. run the existing version-domain classifier;
2. identify which labeled value, if any, belongs to the campaign firmware/version domain;
3. populate the private baseline input only from that proved mapping;
4. run the existing round-trip baseline evaluator.

Completion requires:

- a labeled version-domain receipt;
- `BASELINE_LOCKED`;
- non-null `current_firmware_value`;
- the same private Kiosk4 identity binding;
- `mutation_authorized=false`.

The target `2.0.15.260522` remains a target until authoritative observation proves what is currently installed.

## 7. If the local-input branch closes

Return to the evidence-ranked management portfolio rather than repeating local discovery:

1. Experian/AxiaMed Control Center when authorized read authentication exists;
2. provider/acquirer TMS or NTMS only when an actual estate surface is present;
3. provider-managed service when that provider owns the observation/update plane;
4. PAXSTORE Terminal Management only after a genuine evidence signal establishes the entitlement/route and protocol selection is rerun with that new evidence.

A login wall, App Store, Personal Center, catalog result, portal focus, or generic authenticated session is not production-protocol evidence.

## Stop — forbidden in this gate

- no firmware push, download, assignment, reset, or configuration mutation;
- no target-as-current substitution;
- no private credentials or live device identifiers in Git;
- no replay of P111 marketplace work;
- no selector rerun without new evidence signals;
- no repeated native-keypad alpha experiments;
- no random peripheral escalation after the bounded HID classifier;
- no `BASELINE_LOCKED` claim without a labeled current value.

## Semantic progress events

Only these count as progress on this gate:

1. input workaround classified;
2. labeled version observation captured;
3. version domain classified;
4. `BASELINE_LOCKED`.

Later and separately:

- package/version-domain mapping;
- restore/rollback proof;
- mutation authority;
- controlled deployment;
- post-deployment runtime observation.

Login, hover, portal focus, menu opening, keyboard insertion, and unlabeled numeric strings are not firmware completion events.

## P111 provenance boundary

The private H&H Drive workspace owns:

- exact operational procedures;
- authorized credentials;
- raw photos/screenshots;
- live identity bindings;
- private session/provider evidence.

This public repository owns only the sanitized reusable decision contract.

The sanitized derivative must remain sufficient for another agent to resume the state machine without requiring the repository to know private Drive identities or values.

## Proof ceiling

This guide proves only the current **procedure/state contract** and the retirement of already-exhausted discovery branches.

It does not prove:

- that the second credential is accepted on the H&H image;
- that generic USB HID works on the provisioned reader;
- the live Kiosk4 firmware value;
- the version-domain bind;
- package availability or restore capability;
- mutation authority;
- successful deployment.

## Handoff

```text
CURRENT_GATE=BASELINE_LOCKED
MISSING_EVIDENCE=authoritative labeled current_firmware_value for same private Kiosk4 identity

LOCAL_NATIVE_ALPHA=PROVEN_BLOCKED
LOCAL_REMAINING=ONE_VISIBLE_IME_SWITCH_CHECK + ONE_WIRED_HID_CLASSIFICATION
REMOTE_REMAINING=AUTHORIZED_EVIDENCED_MANAGEMENT_SURFACE

P111_PAXSTORE=DO_NOT_REPLAY
PROTOCOL_SELECTOR=DO_NOT_RERUN_WITHOUT_NEW_EVIDENCE
MUTATION_AUTHORIZED=false

NEXT_SUCCESS_TRANSITION:
labeled installed value
  -> version-domain classification
  -> BASELINE_LOCKED
```
