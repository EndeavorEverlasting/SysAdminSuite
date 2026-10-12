# P141 — Deterministic Android toolset interaction: strategic scout
Date: 2026-10-12 | Repository: EndeavorEverlasting/SysAdminSuite | Inspected main: 7aef5c5249de18c573c16ea7ee204865a2dbfb5f

## RECOMMENDED THESIS — exactly one

**A — Build a single read-only, proof-backed `Next` / readiness interaction through the existing `Manage-AdminBoxAndroidToolchain.cmd`.** This should enumerate what is usable now, distinguish independently blocked developer and SAS-ADB tracks, and generate private approver-ready packets without auto-approving packages or authorizing machines.

**Why now:** #539 already merged the P95 archive-pin trust root and fail-closed `Bootstrap`, and #540 merged 19 adversarial fixture files. Another downloader, pin resolver, P95 investigation or Bootstrap implementation duplicates completed work. Real Admin Box 1 `Apply` and SAS qualification are still blocked by distinct absent authorities. The manual cognitive load has shifted from technical installation to reconstructing which action is allowed and what evidence/approval remains.

**Confidence:** HIGH in prioritization (repo evidence plus recurring operator pull), MEDIUM in exact interaction contract until one read-only real-host receipt has been traced through current engine+pin+profile validators. **Route:** P04 factoring → P07 bounded integration. No additional P95/P82 necessary unless a distinct unresolved architecture/empirical question is actually demonstrated.

## Repository situation and opportunity signals

**CURRENT FACT**
- #539 merged at f3478b419d168b73eea5ba3876ff1a2cf99bfe86: trusted reviewed pin-catalog schema/resolver, `Bootstrap` verb, exact source provenance, existing downloader → prepare → verify integration. #540 merged at 7aef5c5249de18c573c16ea7ee204865a2dbfb5f: nineteen synthetic fixture records with contracts. Do not redo those implementation lanes.
- The pin catalog `configs/android-provider/sas-platform-tools-archive-pins.json` contains a deliberately blocked 37.0.1 candidate with all-zero hash, `PENDING` approval and `blocked_pending_independent_sha256_pin`. WinGet published checksum is not an approved independent organizational digest.
- Latest reported Admin Box 1 receipt: JDK17 present, CLI/Studio/SDK not installed, no approved private `%LOCALAPPDATA%\SysAdminSuite\android-toolchain\host-profile.json`, no SAS-owned Platform-Tools qualification. Source admission and Inventory were read-only successes, not installation proof. Re-verify after branch movement.
- The toolchain engine now supports `Inventory`, `Plan`, `Apply`, `Verify`, `Repair`, and `Bootstrap`, but `schemas/harness/android-toolchain-result.schema.json` still has an operation enum listing *only the first five*. This is demonstrable schema/protocol drift; repair exactly rather than disabling validation.
- The engine intentionally makes `Inventory` and `Plan` return `result=SUCCESS` even with `MISSING_ANDROID_CLI` and `MISSING_ANDROID_STUDIO` in `reason_codes`. This means inspection completed, not operational readiness. The `Bootstrap` path requires both explicit mutation authorization and an approved private `adminbox_reference` host profile, then an independently promoted immutable pin.
- AGENTS.md and the operator-command-handoff skill mandate registered CMD front doors and compositional path → refresh → network intent → command → restoration. `sas next` already serves a different AutoLogon operator context, not Android role readiness.
- TokenCorridor #142 still lacks its canonical P04 manifest schema and executable dispatcher. Cursor Task W1 workers were observed historically in #539's local receipt, not as a new invocation in this scout.

**DERIVED PATTERN:** The tools are capable, but a person still reconciles multiple receipts and manually chooses from `Apply`, `Bootstrap`, source approval, host profile, license, and SDK verification. Those dependencies should be represented mechanically and deterministically.

**STRATEGIC HYPOTHESIS:** Existing read-only producers can be combined into an action-selection projection without expanding installation authority or introducing a second runtime or GUI.

## Competing strategic theses and falsification

| Thesis | Evidence/leverage/timing | Cost and alternative | Falsification result |
| --- | --- | --- | --- |
| **A — Deterministic Next/readiness router on existing CMD front door** | Explicit statuses exist; unresolved user-action synthesis repeats; improves developer install and SAS runtime independently | Small/medium bounded glue + schema/tests. Maybe `Plan` already does everything; inspection shows it emits missing package actions but not independently gated host/pin review transitions or consolidated readiness | **SURVIVES**. Reject if a current Android-specific equivalent proves the complete state/action graph in one registered route |
| **B — Auto-promote candidate SHA and generate RESOLVED host profile from machine facts** | Would superficially remove both human stops | Overrides independent approval and turns hardware identification into authority | **REJECTED**; current organizational trust/host policy expressly forbids it |
| **C — Repair TokenCorridor #142 dispatcher before anything else** | Clear cross-repo autonomy gap; removes agent orchestration burden | Bigger different owner; does not automatically yield user-facing Next semantics | **DEFERRED**; pursue upstream independently |
| **D — New web dashboard with action buttons and privilege escalation** | Attractive presentation | Adds hosted auth/UX/data leakage and duplicates registered CMD; no proven multi-user need | **DEFERRED** until the one-command flow proves insufficient |
| **E — Skip UX and proceed straight to Admin Box Apply** | Actual missing SDK/CLI/Studio matters | Private authority absent; cannot be fixed from CI/GitHub, and the same manual stop returns | **DEFERRED AS LIVE MUTATION**, remains the #534 acceptance gate |

**Comparison:** A has the strongest evidence, broadest immediate operator leverage, small reversible integration and clear success measures. B violates policy; C does not solve current interaction semantics; D is premature; E waits on genuine external approval. No fabricated numeric weighting.

## Cheapest discriminating investigation

Trace one existing **real read-only Inventory receipt + independent pin-resolution outcome + private host-profile presence** through current canonical source and its registered command route. Verify the proposed two-track action graph can be computed without any host/device mutation and without calling an unapproved model. Use a small synthetic decision table as the comparator to existing `Plan` output. If inputs are genuinely insufficient, identify the smallest missing *observation*, not another package runner.

### Proposed P07 operator contract (not implemented by P141)

Existing registered entrypoint: `Manage-AdminBoxAndroidToolchain.cmd Next`, a **read-only new operation**. Existing wrapper must still resolve the canonical machine-neutral checkout and complete the operator command handoff. This command never invokes `Apply` or `Bootstrap` itself.

Expose two independent capability tracks:
- `DEVELOPER_STACK = VERIFIED | NEEDS_INSTALL | VERIFY_REQUIRED | POLICY_BLOCKED | UNKNOWN`
- `SAS_ADB = QUALIFIED | NEEDS_APPROVAL | NEEDS_PREPARE | VERIFY_REQUIRED | UNKNOWN`

Emit a private ignored receipt and compact sanitized stdout including:
1. `INSPECTION_COMPLETE` vs `OPERATIONAL_READY` explicitly; raw result SUCCESS from Inventory may NOT be surfaced as provisioned.
2. Ranked next actions, each with stable `action_id`, `allowed_now`, `requires_authority`, `preconditions`, `proof_ref`, `command_owner` and `why_blocked`. No fabricated absolute paths/commits/capabilities. Deterministic ordering and typed unknowns.
3. An **approver-ready, unapproved** local review packet for the blocked Google ZIP row (candidate versioned URL, candidate hash source vs independently approved digest, reviewer decision required, binding approval reference) and a separate private host-profile authority request (real machine manufacturer/model captured locally, permission set, evidence reference to be approved, policy owner). The agent assembles packets; the human/authority actually decides. No invented approval, no public raw host data.
4. One safe action per independent track. Approved developer install may progress even while independent SAS pin approval is blocked. `Next` never upgrades permissions.
5. Current allowed trusted launcher + freshness/network/restore policy; never emit bare unvalidated user commands, unqualified SDK/PATH adb, PIN_AUTO_APPROVED or firmware steps.

**Examples, not actual success claims:**
- Inventory SUCCESS with absent CLI/Studio and no host profile → developer `NEEDS_INSTALL / HOST_PROFILE_AUTHORITY_REQUIRED`, SAS `NEEDS_APPROVAL / INDEPENDENT_APPROVAL_REQUIRED`. Both review packets can be prepared automatically and independently.
- Authorized developer installation and no approved SAS pin → show developer capability verified, provider blocked. Do not mark both ready.
- Approved host, approved pin, refreshed source and runtime rollback proof → suggest qualified Bootstrap through registered command, requiring explicit `-MutationAuthorized`; do not silently execute it.

### Mandatory contract repairs/validation

- Reconcile the `Bootstrap` operation enum and any actual receipt schema type drift against production emitted fixtures **before** adding `Next`. Preserve `additionalProperties: false` and other strict validation.
- Negative cases: missing/malformed private host profile, unapproved/zero/stale/candidate-only pin, protected network, source mismatch, multiple approved pins, SDK absent, license absent, PTop/DTop confusion, no user consent, stale receipts, unqualified SDK adb, interrupted runtime/rollback, clean two-track independent progression and no host/network mutation from `Next`.
- Use existing command, outcome, artifact, validator, policy and skill owners. Avoid cross-repo dispatcher in SAS and new browser/app server.
- Actual release proof requires focused regression + hosted CI/PR merge and separately verified native Windows Admin Box read-only Next receipt; not a claim of installed tools, qualified SAS runtime or connected reader.

**P141 proof ceiling:** Strategic recommendation based on inspected repository and reported real-host evidence; no local OpenCode worker launched, source/host approvals granted, installer run or device contacted in this scout.