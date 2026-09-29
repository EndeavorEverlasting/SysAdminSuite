# Operator Communication Style Contract

Status: canonical prose reference for coordinator-authored operational communication
Scope: internal team messages, client emails, manager updates, technician directions, and operational handoffs

## Purpose

Preserve the operator's established written voice so routine communication does not have to be reinvented or repeatedly corrected.

This contract controls prose style only. It does not override evidence, privacy, ticket, deployment, approval, or proof-boundary rules elsewhere in the repository.

## Default voice

Operational drafts should sound like a working project coordinator or manager communicating with people who need the current state and next action.

Default to:

- concise, direct, professional language;
- active voice;
- short paragraphs;
- concrete nouns, dates, quantities, locations, owners, and actions;
- the current state first, followed by the minimum supporting facts;
- a clear required action when one exists;
- a clearly named open dependency when one remains;
- natural contractions where they improve the voice, such as "I'm", "we're", and "I'll".

Do not make a short operational message sound ceremonial, legalistic, overly polished, or generated.

## Directive versus request

Use a directive when the recipient is expected to perform an already-decided action.

Prefer:

> Plan to be onsite tomorrow for the install.

Avoid turning an established assignment into a question such as:

> Would you be able to be onsite tomorrow?

Use a request only when the recipient owns information, approval, or another dependency that is genuinely still open.

Prefer:

> Can you confirm the expected delivery window so I can reply to the client?

## State, facts, action, dependency

For routine operational messages, prefer this order:

1. State the current condition or decision.
2. Give only the facts needed to act.
3. State the recipient's action.
4. Name any remaining dependency and who owns it.

A useful compact shape is:

```text
STATE
FACTS
ACTION
OPEN DEPENDENCY
```

Not every message needs all four lines. Omit anything that does not help the recipient act.

## Punctuation and phrasing

- Do not use em dashes in outbound operator-authored drafts. Use a comma, period, colon, semicolon, or parentheses instead.
- Avoid the phrase "locked in" as a default status expression.
- Prefer "confirmed", "once I have it", "once confirmed", or another literal description of the actual state.
- Avoid filler openings such as "I just wanted to reach out" when the message can begin with the subject or current state.
- Avoid unnecessary corporate slogans, inflated transitions, and decorative wording.
- Do not add exclamation points merely to make a routine operational message sound friendly.

## Evidence language

Do not blur confirmed facts and pending facts.

Prefer:

> The install is confirmed for tomorrow. I'm confirming the delivery ETA now and will send the arrival window once I have it.

Do not write as though an open dependency is already resolved.

Prefer literal state words such as:

- confirmed;
- scheduled;
- pending;
- open;
- awaiting;
- completed;
- blocked.

Use stronger completion language only when the supporting evidence permits it.

## Commitment boundary principle

Internal targets may be stricter than external commitments. Never convert an internal planning target or contingency buffer into an external promise without explicit operator intent and enough operational control to support it.

Canonical rule:

`COMMITMENT_STRENGTH <= EVIDENCE_STRENGTH AND OPERATOR_CONTROL`

Classify the underlying statement before drafting:

- `confirmed_fact`: externally usable as a literal fact when current evidence supports it;
- `expected_outcome`: externally usable only with uncertainty language;
- `internal_target`: an internal coordination target, not an external commitment;
- `contingency_buffer`: an internal hedge or safety margin, omitted externally unless it is genuinely relevant;
- `external_commitment`: permitted only when evidence supports it, operational control is sufficient, and the operator intends to make that promise.

Do not collapse a stricter internal plan into stronger client-facing language merely because the internal plan exists.

### Delivery-buffer regression

Internal plan: technicians target 11:00 AM so they have buffer before a delivery expected between 11:30 AM and 12:00 PM.

Client-safe wording may state the delivery window and that the technicians will "assemble on-site during delivery." It must not promise that technicians will be onsite by 11:00 AM or rewrite the hedge as "ahead of the delivery" unless the operator explicitly authorizes that stronger commitment.

The machine-readable authority is `harness/api/operator-communication-semantics.json`, validated by `schemas/harness/operator-communication-semantics.schema.json`.

## Audience patterns

### Internal team direction

Lead with the operational state. Give the assignment as a direction, not a favor, when the assignment is already established.

Canonical pattern:

> Team, [SITE] kiosk install is confirmed for [DATE].
>
> We have [QUANTITY] kiosks going to [ADDRESS], with installation in [INSTALL LOCATION].
>
> Plan to be onsite [DATE] for the install. I'm confirming the delivery ETA with [DELIVERY OWNER] now and will send the arrival window once I have it.
>
> [ACCESS SUMMARY.]

### Client acknowledgement

Acknowledge useful information, restate only what matters, and identify the next dependency without exposing internal noise.

Canonical pattern:

> Hi [CLIENT_NAME],
>
> Thank you, this is exactly what we needed.
>
> I have the installation location noted as [DESTINATION], with [QUANTITY / PLACEMENT]. I also noted [ACCESS SUMMARY].
>
> I'm confirming the delivery timing with our delivery team now and will follow up with the approximate arrival time once I have it.
>
> Thank you,
> [COORDINATOR_NAME]

### Manager or executive update

Use the smallest complete status packet:

```text
Current state:
What is proven:
What remains open:
Next action / owner:
```

Do not bury the blocker or next decision under a chronological narrative unless chronology is itself material.

## Editing test

Before sending a routine operational draft, ask:

1. Does the first sentence establish the state?
2. Is the expected action unmistakable?
3. Is a directive written as a directive rather than a request?
4. Are confirmed facts separated from open dependencies?
5. Can any sentence be removed without losing useful information?
6. Did any em dash or unwanted stock phrase slip back in?
7. Does this sound like a person who already understands the work?

If the answer to the last question is no, shorten and simplify before adding detail.

## Scope boundary

This document intentionally contains no live client names, email addresses, phone numbers, addresses, credentials, ticket screenshots, or private evidence.

Project-specific facts remain in their approved private operational sources. Repository templates use placeholders only.
