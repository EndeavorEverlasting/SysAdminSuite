# P01 — Executive Presentation Language Standard

Date: 2026-10-05  
Status: ACTIVE STYLE / JUDGMENT CONTRACT  
Applies to: H&H firmware presentations, executive updates, stakeholder decks, and client-facing summaries  
Related owners: P95 cinematic presentation contract, P13 recurring-failure retention, P111 artifact synchronization

## Purpose

Prevent stakeholder-facing artifacts from sounding like agent notes, prompt logs, or machine-state dumps.

The audience should see achievement, risk reduction, executive posture, and the next decision. They should not see the scaffolding used to produce the artifact unless they explicitly ask for it.

## Core rule

Translate internal machinery into executive meaning.

| Do not show stakeholders | Say this instead |
| --- | --- |
| `P13 + P111 + P95` | repeated field work is retired; evidence is synchronized; motion and claims remain proof-gated |
| `BLOCKED_EVIDENCE` | the authorized source has not returned the current installed version yet |
| `CLOSED_DO_NOT_REOPEN` | complete unless the device state changes |
| `mutation_authorized=false` | no update action is authorized yet |
| `current_firmware_value` | current installed firmware value |
| `source_protocol` | source owner or management path |
| `labeled_observations` | labeled screen evidence |

## Forbidden visible patterns

These patterns are allowed in repo contracts, receipts, and internal ledgers. They are not allowed in stakeholder slides unless the deck is explicitly technical-harness training.

- raw protocol identifiers as badges or slide value propositions;
- underscore-delimited enum language;
- self-referential claims such as “this deck is now a scene sequence”;
- “agent”, “prompt”, “harness”, “slop”, or “chat” language in stakeholder-facing prose;
- operator-directed advice such as “stop treating local menus…”;
- vague achievement claims without a next decision;
- details that invite questions unrelated to the business objective, such as bedding/background context in photos.

## Preferred executive patterns

Use this shape:

```text
Finding → consequence → next decision
```

Examples:

- Local menu discovery is complete. Field effort now shifts to source ownership and package evidence.
- The keyboard path exists, but credential-gated settings remain numeric-only. The firmware owner must provide the current-version source.
- No update action is authorized yet. We are keeping the reader unchanged until version, package, rollback and authority are proven.
- The source portfolio remains active: Control Center, provider TMS, provider-managed update, PAXSTORE entitlement, and lab-only partner tooling.

## Photo and privacy prose

When using device photos:

- crop or blur room/background context;
- preserve screen readability;
- omit credential-bearing photos unless redacted;
- write captions around the proof, not the private setting.

Use captions like:

- Admin menu inventory complete.
- Credential prompt: digits only.
- Diagnostic host field: text accepted.
- Source portfolio remains open.

Avoid captions like:

- Here is where I entered the password.
- This is the AI slot / prompt result.
- We invoked P13.
- Stop treating this as the firmware plane.

## Achievement framing

A deck may be successful even when the firmware value is not yet captured. The achievement is the narrowing of the problem and the prevention of repeated field waste.

Allowed claims:

- local menu inventory is complete;
- numeric credential gates and diagnostic text fields are distinct;
- local menu-poking is no longer the path;
- authorized management/source portfolio remains open;
- next evidence gate is clearly defined.

Forbidden claims without proof:

- current firmware is known;
- baseline is locked;
- package domain is proven;
- update authority exists;
- deployment occurred;
- runtime behavior is verified.

## Review checklist

Before delivery, scan every visible slide:

1. Would a client or executive understand the claim without asking what our internal protocol labels mean?
2. Does each slide answer what changed, why it matters, or what decision is next?
3. Are all photos privacy-treated?
4. Are there any underscores, raw enums, prompt names, or internal mechanics visible?
5. Does the deck avoid blaming, apologizing, or exposing field improvisation?
6. Does the proof ceiling remain explicit in human language?
7. Does the artifact feel like a rollout from a project manager, not an agent scratchpad?

If any answer fails, revise before sharing.
