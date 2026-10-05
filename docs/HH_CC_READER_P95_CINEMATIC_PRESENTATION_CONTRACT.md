# H&H CC Reader — P95 Cinematic Presentation Contract

Date: 2026-10-05  
Status: ACTIVE DESIGN / PROOF CONTRACT  
Repository: `EndeavorEverlasting/SysAdminSuite`  
Primary owner: P95 protocol / live-boundary presentation layer  
Supporting owners: P01 executive language standard, P13 recurring-failure retention, P111 Drive/repo artifact synchronization, P11 validation/readback

## Purpose

Prevent H&H CC Reader firmware presentations from regressing into flat text decks or internal-agent narration.

A P95 presentation is a stakeholder-facing proof sequence: each visible slide advances the audience through a decision gate, and each motion cue must map to a real evidence transition. The deck must not announce that it is a “scene sequence”; it must behave like one.

## Non-negotiable audience boundary

Internal protocol names are implementation machinery, not executive impact.

Visible stakeholder slides must not use labels such as `P13`, `P111`, `P95`, `BLOCKED_EVIDENCE`, `CLOSED_DO_NOT_REOPEN`, `current_firmware_value`, or other machine-state tokens unless the audience explicitly asked for harness details.

Translate them instead:

| Internal state | Stakeholder language |
| --- | --- |
| P13 | repeated work has been retired into a reusable rule |
| P111 | evidence is synchronized across Drive, repo, and deck surfaces |
| P95 | motion and source selection remain proof-gated |
| `BLOCKED_EVIDENCE` | an authorized source has not yet returned the current installed version |
| `CLOSED_DO_NOT_REOPEN` | the branch is complete unless new evidence changes the device state |
| `mutation_authorized=false` | no update action is authorized yet |

## Executive prose rule

The slide should answer: what changed, why it matters, what decision is next.

Avoid:

- internal advice to the operator or agent;
- self-referential claims such as “this deck is a scene sequence”;
- tool/prompt badges as if they were impact;
- underscore tokens, raw enum names, and machine-readable phrasing;
- “stop” phrasing that sounds like prior misconduct. Use “do not repeat”, “closed by evidence”, or “not the current path”.

Prefer:

- concise executive claims;
- impact language;
- owner/decision language;
- visible achievement without overstating completion;
- proof ceiling stated in human terms.

## Research-derived technique floor

The reusable floor for this repo is:

1. Use the Anthropic-style PPTX workflow discipline: create or edit real `.pptx`, render/read back, and inspect the produced artifact before delivery.
2. Use PowerPoint Morph for scene continuity where a concept should move from one state to another.
3. Use explicit PowerPoint object names with the `!!` prefix for Morph-critical objects so matching is deliberate, one-to-one, and not left to visual guessing.
4. Prefer scene pairs over per-object animation spam: a repeated background/subject moves, scales, or crops across slides while the proof state changes.
5. Keep a fallback transition where XML or player support is uncertain.
6. Do not promote a Google Slides projection as the canonical animated artifact when Morph/keyframe continuity is required. The canonical delivery artifact is `.pptx`; Drive may store the PPTX.
7. If Drive/Google Slides preview flattens or flashes through a PPTX, do not claim the animation was observed there. Report the playback surface honestly.

## P95 rule: motion must encode proof

Every animation/keyframe must answer one of these questions:

| Motion intent | Allowed when | Forbidden when |
| --- | --- | --- |
| Zoom into evidence | The source evidence is captured and safe to show or sanitized | Raw credential/identity evidence is visible |
| Slide/pan across branches | The branch dispositions are already typed | The deck is still inventing branch states |
| Morph a gate from open to closed | The evidence state actually changed | The state is aspirational or planned |
| Fade out a dead end | The branch is closed by evidence and retained in a closure record | The branch is merely inconvenient |
| Reveal next gate | The next gate is explicitly blocked/open with named missing evidence | The reveal implies completion |
| Highlight protocol path | That protocol is evidenced and authorization state is explicit | The path implies mutation authority |

## Scene spine for the Kiosk4 firmware deck

A presentation should follow this spine unless the operator asks for another audience/order:

1. **Establish the gate** — local discovery is complete; the next decision is the authorized update path.
2. **Zoom into sanitized local evidence** — show Kiosk4/menu evidence and privacy boundaries.
3. **Separate field classes** — numeric credential gates versus alphanumeric diagnostic host-name fields.
4. **Retire local branches** — Netstat, Connectivity Test, Network Settings, generic menu crawl.
5. **Open the source portfolio** — Control Center, TMS/NTMS, provider-managed update, PAXSTORE, partner/lab fallback.
6. **Demand proof before update** — current value → version-domain classification → restore/rollback → authority → controlled update → post-update observation.

## Required slide ledger

Each deck must keep a small internal or companion ledger:

```text
slide_id | scene_intent | evidence_source | proof_state | motion_type | continuity_object_names | privacy_gate | proof_ceiling | stakeholder_translation
```

The ledger may use internal typed states. The visible deck should not expose raw state tokens.

## Privacy and screenshot boundary

Credential-bearing, serial/MAC/IP-bearing, private Drive-ID-bearing, or session-bearing screenshots must not be used as visible deck assets unless redacted first.

For device photos, apply privacy-by-design treatment:

- keep the screen readable;
- crop or blur bedding, room, keyboard, hands, and other environmental context;
- blur or de-emphasize device keys when they are not the evidence target;
- never blur the exact screen text that proves the claim;
- exclude credential-bearing admin-unlock photos from visible decks unless the credential is fully redacted and the redaction is read-back verified.

Allowed derivatives:

- cropped/blurred/redacted images;
- verbal proof-state projection;
- sanitized menu capability map;
- public-safe repository derivative.

Forbidden:

- visible credentials;
- live serial/MAC/IP values;
- private Drive IDs or session URLs;
- screenshots that imply access beyond the authorized operator boundary.

## Morph implementation expectations

When producing a PowerPoint-native animated deck:

1. Build the scene as `.pptx` first.
2. Duplicate/mutate scene objects for keyframes.
3. Give Morph-critical objects unique, stable names beginning with `!!` across adjacent slides.
4. Apply Morph to destination slides.
5. Add a fade fallback for older or non-Morph renderers when patching OOXML.
6. Render/export thumbnails or PDF and inspect every slide for collisions, tiny text, clipping, and false proof implications.
7. Verify the package contains expected transition markers and named continuity objects before claiming animation work.
8. Distinguish created animation from observed playback. PowerPoint Morph proof is package-level until it is played in a Morph-supporting PowerPoint environment.

## Visual floor

- One dominant mood per deck; avoid generic corporate blue panels.
- Use real evidence photos and cinematic generated/source imagery as scene assets.
- Use privacy-treated evidence crops instead of raw room-context photos.
- Use large readable type: title usually 32pt or larger; body normally 18pt or larger except labels.
- Use fewer words than the source document.
- Use proof-state color consistently behind the scenes: amber for gate/current focus, cyan for technical path, green for proven/ready, red for forbidden/not proved.
- Keep panels sparse; use composition, depth, and contrast rather than dashboard grids.
- Motion belongs between scenes; do not animate every bullet.
- When a technical justification is thin, convert it into a visual transition or source-owner diagram rather than adding internal prose.

## Delivery gates

Before delivery, record:

1. artifact type and canonical location (`.pptx` when Morph/keyframes matter);
2. slide count;
3. rendered thumbnail/PDF readback result;
4. overlap/out-of-bounds check result;
5. transition/keyframe implementation proof;
6. privacy gate result;
7. executive-language gate result;
8. proof ceiling.

## Kiosk4 proof ceiling preserved

A cinematic presentation may show the depth of work, but it may not claim:

- current firmware value;
- version-domain binding;
- baseline lock;
- package/restore mapping;
- mutation authority;
- deployment;
- post-deployment runtime observation;

unless each item has independent evidence.

## Current deck artifacts

First contract-following deck:

`Kiosk4 Firmware Gate — Cinematic P95 Morph Deck — 2026-10-04.pptx`

Second pass after operator critique:

`Kiosk4 Firmware Gate — Executive Cinematic v2 — 2026-10-05.pptx`

The v2 pass removed visible protocol badges, self-referential scene claims, underscore/state-token language, operator-advice phrasing, and raw environmental context in screenshots. It remains a Drive-stored PPTX because Morph/keyframe continuity is a PowerPoint feature and Google-native conversion may flatten or alter animation semantics.
