# P111 Kiosk4 Local-Access Guide Synchronization — 2026-10-04

Status: REMOTE SYNC IN PROGRESS  
Floor at start: `main@696d1382d094373c6de76e2eaa59b1fd0331421e`  
Owner: H&H CC-reader live firmware evidence/continuity lane

## Purpose

Persist the current Kiosk4 local-access/input-method state in two durable authority-appropriate surfaces so a successor agent does not rediscover exhausted work:

1. a private Drive operator guide containing exact internal operational context; and
2. a public-safe SysAdminSuite derivative containing the reusable state machine and proof ceiling.

This is a P111 continuity/provenance synchronization slice. It is **not** a firmware implementation or mutation slice.

## Current live gate

```text
KIOSK4_IDENTITY=UNIQUE_TARGET_RESOLVED
CURRENT_FIRMWARE=LIVE_VALUE_NOT_CAPTURED
BASELINE_LOCKED=BLOCKED_EVIDENCE

LOCAL_NATIVE_ALPHA=PROVEN_BLOCKED
P95_SELECTOR=CLOSED
PAXSTORE_MARKETPLACE_CORPUS=CLOSED_FOR_THIS_GATE
MUTATION_AUTHORIZED=false
```

The exact next success transition remains:

```text
same private Kiosk4 identity
  -> authoritative labeled installed version
  -> version-domain classification
  -> BASELINE_LOCKED
```

## Private-provider artifact

The private H&H Drive operator guide is the operational authority for:

- exact internal access procedure;
- authorized credential values;
- raw field evidence;
- private device identity bindings;
- private provider/session evidence.

Repository code and documentation must not depend on the Drive file ID, private URL, credential text, serial, MAC, IPv4, or session data.

## Public sanitized derivative

Canonical derivative in this PR:

- `docs/HH_CC_READER_KIOSK4_LOCAL_ACCESS_FIELD_GUIDE.md`

It preserves:

- retired/disproven local discovery;
- the bounded remaining input-method tests;
- fail-closed result classifications;
- label-first version capture;
- classify-before-freeze ordering;
- P95/P111 no-replay rules;
- mutation denial;
- proof ceiling and successor gate.

## Forbidden synchronization content

Never admit into Git:

- H&H/PAX/AxiaMed credentials or PINs;
- live Kiosk4 serial/MAC/IPv4;
- private Drive IDs or URLs;
- raw restricted screenshots;
- account identity or session-bearing URLs;
- cookies, tokens, secrets, or MFA material.

Never use this documentation sync to authorize:

- Firmware Update / Push / Download;
- device reset or configuration change;
- package assignment;
- selector promotion without new evidence;
- `BASELINE_LOCKED` without a labeled current value.

## Acceptance gates

1. Private Drive guide created in the canonical CC-reader `00_START_HERE` lane.
2. Drive guide styled using the H&H metropolitan document profile.
3. Drive connector readback proves the guide content is durable.
4. Sanitized derivative contains no credential value or live reader identifier.
5. Sanitized derivative explicitly retires FUNC/alpha/tap/hold/combo rediscovery.
6. Sanitized derivative preserves the bounded IME/HID classifier and label-first capture contract.
7. `docs/evidence/latest/README.md` points to the current sanitized guide + this P111 sync record.
8. Pull request is opened from an isolated branch.
9. Private Drive P111 sync receipt records Drive/provider readback plus PR/commit state.
10. Integration is claimed only if Git provider state later proves the PR merged.

## Proof ceiling

This P111 slice proves documentation/provenance synchronization and continuity recovery.

It does **not** prove:

- alphanumeric input success;
- Settings credential acceptance;
- current Kiosk4 firmware;
- version-domain mapping;
- `BASELINE_LOCKED`;
- package/restore mapping;
- mutation authority;
- deployment.

## Successor

The next technical action remains live/operator evidence collection, not another documentation or harness sprint.

After the labeled observation exists, resume:

```text
Classify-HHCCReaderVersionDomain
  -> private current_firmware_value bind
  -> Evaluate-HHCCReaderFirmwareRoundtrip baseline
  -> BASELINE_LOCKED or exact fail-closed blocker
```
