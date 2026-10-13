# P07 W1-A — `Manage-AdminBoxAndroidToolchain.cmd Next` interaction contract

Date: 2026-10-12
Lane: W1-A interaction-contract (read-only designer)
Base inspected: `origin/main` @ `60b7cab23e5b91802fb7b32cf3b1f1393d2fc714`
Strategy: `docs/plans/p141-android-deterministic-toolset-interaction-20261012.md`
Handoff: `docs/handoff/android-adminbox1-next-action-p04-20261012.md`
Audience: P07 integrator (W2) only

**Proof ceiling:** analyzed contract against current engine, pin resolver, pin catalog, CMD front door, and result schema. Not product behavior. Not live Admin Box certification.

---

## 0. Scope and non-goals

### Owned by this contract

Deterministic projection of read-only `Next` through the existing registered Admin Box front door:

```text
Manage-AdminBoxAndroidToolchain.cmd Next
  → scripts/Start-SasAdminBoxAndroidToolchain.ps1
  → scripts/Invoke-SasAndroidToolchain.ps1 -NodeRole adminbox_reference -Operation Next
```

### Forbidden for `Next` (hard)

- Call or imply execution of `Apply`, `Repair`, or `Bootstrap`
- Accept licenses, elevate, install packages, mutate PATH/env, download archives
- Auto-promote pin catalog rows or write `status=RESOLVED` host profiles
- Contact devices, CC readers, emulators, or unqualified SDK/`PATH` `adb`
- Duplicate AutoLogon `sas next` semantics
- Publish private host manufacturer/model, absolute local paths, credentials, or raw receipts to GitHub

### Existing operation map (current engine, `Next` not present)

| Operation | Mutates host? | Current `result=SUCCESS` meaning |
| --- | --- | --- |
| `Inventory` | No | Inspection completed (may still emit `MISSING_*`) |
| `Plan` | No | Same as Inventory plus install-missing action hints |
| `Apply` / `Repair` | Yes (`-MutationAuthorized`) | Developer stack provisioned under host-profile authority |
| `Verify` | No (optional Studio/build/emulator probes) | Tools present and checks pass |
| `Bootstrap` | Yes (`-MutationAuthorized`) | SAS-owned Platform-Tools prepare/verify under pin + host-profile authority |
| **`Next` (new)** | **No** | **Projection complete; never means operational readiness** |

Schema note for W2 (do not edit in W1-A): `schemas/harness/android-toolchain-result.schema.json` currently enums `Inventory|Plan|Apply|Verify|Repair` and omits `Bootstrap`. Repair `Bootstrap` first, then add `Next`, preserving `additionalProperties: false`.

---

## 1. Developer-stack track states

Field: `tracks.developer_stack.state`

Independent of SAS-ADB. Derived only from Inventory observation + source/policy gates that block developer install diagnosis.

| State | Meaning | Primary signals |
| --- | --- | --- |
| `VERIFIED` | Required developer tools present and inventory shows no blocking developer reason codes; post-install Verify is optional but recommended when proof tokens absent | Inventory lacks `MISSING_STANDALONE_JDK`, `MISSING_ANDROID_CLI`, `MISSING_ANDROID_STUDIO`, `SDK_ROOT_MISMATCH`, `SDK_STUDIO_MISMATCH`; optional prior proof includes `CLI_VERIFIED` / `WINDOWS_INSTALLED` |
| `NEEDS_INSTALL` | Inspection found absent developer packages/tools | One or more of `MISSING_STANDALONE_JDK`, `MISSING_ANDROID_CLI`, `MISSING_ANDROID_STUDIO`, or Plan-style `INSTALL_MISSING` packages |
| `VERIFY_REQUIRED` | Tools appear present, but required verification proof is missing or stale relative to current source/profile | Tools found; no current `CLI_VERIFIED` (and/or required package readback) for this checkout/profile revision |
| `POLICY_BLOCKED` | Developer progression blocked by role/source/network/profile policy, not by missing bits | `NODE_ROLE_MISMATCH`, `ADMINBOX_ROLE_OVERRIDE_FORBIDDEN`, `SOURCE_POLICY_DENIED`, sealed-capability failure, protected-network denial for acquisition diagnosis |
| `UNKNOWN` | Inputs insufficient to classify without fabricating observations | Fixture-only gaps, unreadable inventory, source admission incomplete without typed code |

**Invariant:** Inventory `result=SUCCESS` with `MISSING_ANDROID_CLI` / `MISSING_ANDROID_STUDIO` ⇒ `NEEDS_INSTALL`, never `VERIFIED`.

---

## 2. SAS-ADB track states

Field: `tracks.sas_adb.state`

Independent of developer track. Derived from pin resolution, private host-profile presence typing, and (when safely observable) provider prepare/verify status. Never inferred from WinGet metadata or candidate ZIP hashing.

| State | Meaning | Primary signals |
| --- | --- | --- |
| `QUALIFIED` | Independently approved pin resolved for `adminbox_reference` and SAS provider verify/doctor evidence is current | Pin resolve success with `promotion_status=approved_for_provider_prepare`; provider proof tokens present (`PREPARED`/`VERIFIED`/`SAS_HOST_READY` as applicable) |
| `NEEDS_APPROVAL` | Catalog/candidate exists but independent organizational pin approval is missing or blocked | `INDEPENDENT_APPROVAL_REQUIRED` and/or `QUALIFICATION_AUTHORITY_REQUIRED` from `android_platform_tools_pin.resolve`; all-zero/PENDING/`blocked_pending_independent_sha256_pin` rows |
| `NEEDS_PREPARE` | Authorities present (approved pin + RESOLVED host profile allowing Bootstrap) but SAS bundle not yet prepared/verified | Pin resolves; host-profile typed `RESOLVED`; provider status not ready (`SAS_PROVIDER_NOT_READY` / missing prepare proof) |
| `VERIFY_REQUIRED` | Prepared/claimed runtime lacks current doctor/verify proof after source movement | Bundle path claimed; status/doctor/verify not re-proven on current expected-commit |
| `UNKNOWN` | Cannot classify pin/host/provider without overreach | Host-profile path unreadable beyond ABSENT/INVALID typing; pin catalog unreadable → prefer typed `SOURCE_POLICY_DENIED` over silent success |

**Independence rule:** Developer `VERIFIED` does not advance SAS-ADB. SAS `QUALIFIED` does not clear `MISSING_ANDROID_CLI` / Studio gaps.

---

## 3. Stable reason-code vocabulary

Reuse existing engine/pin codes. Do not invent parallel synonyms for the same failure.

### Authority / policy (prefer these for blocked actions)

| Code | Use when |
| --- | --- |
| `ADMINBOX_PROFILE_AUTHORITY_REQUIRED` | Default host-profile path absent for `adminbox_reference` |
| `ADMINBOX_PROFILE_AUTHORITY_INVALID` | Profile present but schema/status/role/ops invalid |
| `ADMINBOX_EQUIPMENT_PROFILE_MISMATCH` | Profile manufacturer/model ≠ live equipment |
| `INDEPENDENT_APPROVAL_REQUIRED` | Pin digest/approval_reference incomplete, zero, or PENDING |
| `QUALIFICATION_AUTHORITY_REQUIRED` | No approved pin for artifact/role (blocked/candidate-only catalog) |
| `SOURCE_POLICY_DENIED` | Catalog shape/URL/role policy violation |
| `MUTATION_AUTHORIZATION_REQUIRED` | Explaining why Apply/Bootstrap cannot run from Next (informational on blocked mutation actions) |
| `NODE_ROLE_MISMATCH` | Role/profile mismatch |
| `ADMINBOX_ROLE_OVERRIDE_FORBIDDEN` | Caller attempted `-NodeRole` override via Admin Box starter |

### Developer observation

| Code | Use when |
| --- | --- |
| `MISSING_STANDALONE_JDK` | java/javac absent |
| `MISSING_ANDROID_CLI` | Google Android CLI absent |
| `MISSING_ANDROID_STUDIO` | Android Studio absent |
| `MISSING_SDK_COMMANDLINE_TOOLS` | sdkmanager absent (Verify-class observation) |
| `SDK_PACKAGES_MISSING` | Required/native/system-image packages missing |
| `SDK_ROOT_MISMATCH` / `SDK_STUDIO_MISMATCH` | Conflicting SDK roots |
| `INSUFFICIENT_DISK_SPACE` | Below profile minimum free GiB |

### Source / runtime (surface when observed)

| Code | Use when |
| --- | --- |
| `PYTHON_REQUIRED` / `NATIVE_PROCESS_MODULE_REQUIRED` | Local runtime prerequisites missing |
| `ANDROID_TOOLCHAIN_CAPABILITY_NOT_SEALED` | Sealed runtime missing required files |
| `SAS_PROVIDER_NOT_READY` | Provider status/doctor/verify failed after authorities exist |

Projection may aggregate into `reason_codes` (union, unique, stable sort). Terminal copy must not translate these into softer language that implies approval or installation occurred.

---

## 4. Prioritized next-action rules

### Action object shape (every emitted action)

```json
{
  "action_id": "string",
  "allowed_now": false,
  "requires_authority": ["string"],
  "preconditions": ["string"],
  "proof_ref": "opaque-or-relative-ref",
  "command_owner": "Manage-AdminBoxAndroidToolchain.cmd",
  "why_blocked": "REASON_CODE_OR_null"
}
```

Rules:

- `allowed_now=true` only for read-only registered commands that Next itself may recommend as the immediate operator step without new authority.
- Mutation actions (`Apply`, `Bootstrap`) may appear in the ranked list with `allowed_now=false` until every listed authority/precondition is satisfied; Next still never executes them.
- `command_owner` for Admin Box lifecycle actions is always the registered CMD (or its documented sibling engine under that CMD). Never bare `winget`, naked `adb`, or unvalidated PowerShell one-liners.
- `proof_ref` is an opaque local receipt id, relative ignored path under `survey/output/…`, or catalog/approval reference string — never a fabricated absolute commit/capability claim.
- Deterministic sort key: `(priority_rank ASC, action_id ASC)`.

### Global priority ranks (lower runs first in presentation)

| Rank | `action_id` | Track | `allowed_now` when | `requires_authority` | Typical `why_blocked` |
| --- | ---: | --- | --- | --- | --- |
| 10 | `REFRESH_SOURCE_ADMISSION` | both | Source admission not current/clean and refresh is in policy | path/freshness authority | source reason if blocked |
| 20 | `DRAFT_HOST_PROFILE_REVIEW_PACKET` | developer gate for Apply; also Bootstrap | Host-profile typed `ABSENT` or `INVALID` | org host-profile approver | `ADMINBOX_PROFILE_AUTHORITY_REQUIRED` or `ADMINBOX_PROFILE_AUTHORITY_INVALID` |
| 30 | `DRAFT_PIN_INDEPENDENT_REVIEW_PACKET` | sas_adb | Pin not approved / blocked candidate | independent pin approver | `INDEPENDENT_APPROVAL_REQUIRED` or `QUALIFICATION_AUTHORITY_REQUIRED` |
| 40 | `RUN_INVENTORY` | both | Always safe; emit when inventory stale/missing in this session | none | null |
| 50 | `SUGGEST_APPLY_DEVELOPER` | developer | Never from Next execution; `allowed_now=true` only after host-profile `RESOLVED` allowing Apply, mutation flag still operator-supplied outside Next | host-profile + `-MutationAuthorized` | `ADMINBOX_PROFILE_AUTHORITY_REQUIRED` / `MUTATION_AUTHORIZATION_REQUIRED` |
| 60 | `SUGGEST_VERIFY_DEVELOPER` | developer | Tools present; Verify not yet proved | none for read-only Verify | null when tools present |
| 70 | `SUGGEST_BOOTSTRAP_SAS` | sas_adb | Never auto-run; `allowed_now` only when pin approved + host-profile `RESOLVED` with Bootstrap + operator will pass `-MutationAuthorized` separately | pin + host-profile + mutation | pin/profile/mutation codes |
| 80 | `SUGGEST_PROVIDER_VERIFY` | sas_adb | Bundle prepared; verify/doctor outstanding | none for read-only provider verify | null when prepare proof exists |
| 90 | `NO_SAFE_MUTATION` | both | Always available as informational terminal action when both tracks blocked on authority | n/a | dominant blocker codes |

### One safe progressive action per track

After sorting, select:

1. **Developer primary:** first action with track affinity developer whose preconditions are unmet, preferring packet draft → Inventory/Verify → suggested Apply (blocked until authority).
2. **SAS-ADB primary:** first sas_adb action likewise, preferring pin packet → prepare/Bootstrap suggestion (blocked) → provider verify.

Emit full ranked `actions[]` for machine consumers; terminal summary highlights only the two primaries plus global blockers.

### Ordering algorithm (normative)

```text
1. Collect observations: source admission, Inventory, pin resolve (catch typed codes),
   host_profile_presence, optional provider status (read-only; failures → reason codes).
2. Classify developer_stack.state and sas_adb.state (sections 1–2).
3. Set inspection_complete=true if Inventory observation finished without throw
   that prevents inventory attachment; else false.
4. Set operational_ready=true only if developer_stack=VERIFIED AND sas_adb=QUALIFIED
   AND inspection_complete=true. Inventory SUCCESS alone never sets this.
5. Build candidate actions from the priority table using only observed facts.
6. Sort; mark allowed_now; attach why_blocked for every false allowed_now mutation.
7. Write private receipt + sanitized stdout (sections 8–9).
8. Exit 0 when projection completes (Next success = projection success).
   Exit non-zero only when Next itself cannot inspect (source/runtime hard fail).
```

---

## 5. Read-only inspection semantics

| Claim | Allowed? |
| --- | --- |
| Inventory/Plan `result=SUCCESS` | Means inspection completed |
| `inspection_complete=true` | Same family; explicit Next field |
| `operational_ready=true` | Only dual-track ready (section 4 step 4) |
| Next SUCCESS ⇒ tools installed | **Forbidden interpretation** |
| Next SUCCESS ⇒ pin/host approved | **Forbidden interpretation** |
| Next invokes Apply/Bootstrap | **Forbidden behavior** |

`Next` may *read*:

- Existing Inventory path (or run Inventory-equivalent observation inline)
- `harness.api.android_platform_tools_pin.resolve('adminbox_reference')` (no network)
- Host-profile path existence + JSON shape/status typing
- Optional read-only provider `status`/`doctor`/`verify` when they do not mutate; classify failures as reason codes

`Next` must not set `$MutationAuthorized`, call WinGet install, fetch ZIP maps, or write authority files.

---

## 6. Source and evidence references

### Source

- Reuse AndroidProvider source admission (`admit_source` / `ExpectedCommit`) exactly as Inventory does.
- Receipt fields (additive):

```json
{
  "source": { "admission": "<opaque json or string as today>", "expected_commit": "<hex-or-null>" },
  "evidence_refs": {
    "pin_catalog": "configs/android-provider/sas-platform-tools-archive-pins.json",
    "desired_state_profile": "Config/android-adminbox-toolchain-profile.json",
    "host_profile_presence": "ABSENT|INVALID|RESOLVED",
    "inventory_receipt_ref": "<opaque local>",
    "pin_resolution": "BLOCKED|RESOLVED|DENIED",
    "approval_packet_refs": ["<opaque local draft ids>"]
  }
}
```

### Host-profile presence typing (no private host facts in public outputs)

| Type | Definition |
| --- | --- |
| `ABSENT` | Default `%LOCALAPPDATA%\SysAdminSuite\android-toolchain\host-profile.json` (or `-HostProfile`) not found |
| `INVALID` | File exists but fails schema/status/role/ops/equipment checks (emit `ADMINBOX_PROFILE_AUTHORITY_INVALID` or mismatch code; do not print manufacturer/model publicly) |
| `RESOLVED` | Passes `Assert-HostProfileForRole` for `adminbox_reference` against desired-state ceiling for the contemplated operation set |

Public/sanitized stdout may show only the enum above + reason codes + opaque `evidence_ref` token if already present in the profile. Raw CIM manufacturer/model stay in private ignored packets only.

### Pin resolution typing

| Type | Definition |
| --- | --- |
| `RESOLVED` | `resolve()` returned a single approved pin |
| `BLOCKED` | `QUALIFICATION_AUTHORITY_REQUIRED` or `INDEPENDENT_APPROVAL_REQUIRED` |
| `DENIED` | `SOURCE_POLICY_DENIED` |

---

## 7. Approval-required classifications

Packets are **drafts**, never approvals.

| Packet class | Trigger | Private output root (ignored) | Must include | Must not do |
| --- | --- | --- | --- | --- |
| `PIN_INDEPENDENT_REVIEW` | Pin typing `BLOCKED` | `survey/output/android-bootstrap-next/` | Candidate versioned URL from catalog, statement that WinGet/candidate hash ≠ org approval, required fields to reach `approved_for_provider_prepare`, `approval_reference` placeholder, reviewer decision checkbox | Rewrite catalog; set approved hash from download |
| `HOST_PROFILE_AUTHORITY_REVIEW` | Host presence `ABSENT` or `INVALID` | same root | Requested role `adminbox_reference`, requested ops subset of desired-state (`Apply`/`Bootstrap` as applicable), local evidence_ref to capture, policy owner channel | Write `status=RESOLVED`; invent permissions |

Separation rules:

- Pin approval ≠ host-profile approval.
- Draft packet emission does not change track state to `QUALIFIED` / developer `VERIFIED`.
- Humans/org authorities decide; agents only assemble.

---

## 8. Terminal presentation contract

Stdout is human-readable, two-track, sanitized. Suggested fixed sections:

```text
=== SAS Admin Box Android toolchain — Next ===
Role: adminbox_reference
Inspection: INSPECTION_COMPLETE|INSPECTION_INCOMPLETE
Operational: OPERATIONAL_READY|NOT_OPERATIONAL_READY

Developer stack: <STATE>
  reasons: <codes or none>
  next: <action_id> allowed_now=<bool> [<why_blocked>]

SAS-ADB: <STATE>
  reasons: <codes or none>
  next: <action_id> allowed_now=<bool> [<why_blocked>]

Authority packets: <none|PIN_DRAFT|HOST_DRAFT|BOTH> (private refs only)
Command owner: Manage-AdminBoxAndroidToolchain.cmd
```

Rules:

- Never print full private host-profile JSON, absolute user profile paths beyond the known default tokenized form, or archive SHA values in a way that implies approval.
- Do not label Inventory SUCCESS as “ready”.
- Exactly one highlighted next line per track (primaries from section 4).

---

## 9. Machine-readable action receipt contract

### Result envelope (W2 schema notes — W1-A does not edit schema)

Extend `sas-android-toolchain-result/v1` (or additive v1-compatible fields if strict schema requires a coordinated bump) as follows:

1. Add `"Bootstrap"` then `"Next"` to `operation` enum (Bootstrap drift fix first).
2. Keep required: `schema_version`, `operation`, `node_role`, `result`, `reason_codes`, `proof`, `actions`, `inventory`, `checks`, `source`.
3. For `operation=Next`, recommend additive properties (schema must allow them or version bump):

```json
{
  "schema_version": "sas-android-toolchain-result/v1",
  "operation": "Next",
  "node_role": "adminbox_reference",
  "result": "SUCCESS",
  "reason_codes": ["MISSING_ANDROID_CLI", "MISSING_ANDROID_STUDIO", "ADMINBOX_PROFILE_AUTHORITY_REQUIRED", "QUALIFICATION_AUTHORITY_REQUIRED"],
  "proof": ["NEXT_PROJECTION"],
  "actions": [],
  "inventory": {},
  "checks": [],
  "source": null,
  "inspection_complete": true,
  "operational_ready": false,
  "tracks": {
    "developer_stack": { "state": "NEEDS_INSTALL", "primary_action_id": "DRAFT_HOST_PROFILE_REVIEW_PACKET" },
    "sas_adb": { "state": "NEEDS_APPROVAL", "primary_action_id": "DRAFT_PIN_INDEPENDENT_REVIEW_PACKET" }
  },
  "evidence_refs": {
    "pin_catalog": "configs/android-provider/sas-platform-tools-archive-pins.json",
    "host_profile_presence": "ABSENT",
    "pin_resolution": "BLOCKED"
  },
  "approval_packets": [
    { "class": "HOST_PROFILE_AUTHORITY_REVIEW", "status": "PENDING_REVIEW", "ref": "opaque-local" },
    { "class": "PIN_INDEPENDENT_REVIEW", "status": "PENDING_REVIEW", "ref": "opaque-local" }
  ]
}
```

4. `actions[]` items for Next SHOULD use the section-4 field set (`action_id`, `allowed_now`, …). Legacy Plan items using `{action: INSTALL_MISSING, package}` remain valid for Plan only; Next projection normalizes to `action_id` vocabulary.
5. `result=SUCCESS` on Next means projection finished. `result=BLOCK` reserved for Next unable to inspect (hard source/runtime failure).
6. `proof` MUST include `NEXT_PROJECTION` and MUST NOT claim `WINDOWS_INSTALLED`, `PREPARED`, or `VERIFIED` unless those proofs were independently observed from prior operations (read-only reuse), never newly created by Next.

Private receipt path: existing `survey/output/android-toolchain/receipt-*.json` plus optional sibling drafts under `survey/output/android-bootstrap-next/`.

---

## 10. Example expected outcome (acceptance sample for W2/W1-C)

**Scenario (matches reported Admin Box 1 shape; synthetic acceptance, not a live claim):**

- Inventory completes with `result=SUCCESS`
- Reason codes include `MISSING_ANDROID_CLI`, `MISSING_ANDROID_STUDIO` (JDK may be present → omit `MISSING_STANDALONE_JDK` if observed)
- Host-profile presence: `ABSENT` → `ADMINBOX_PROFILE_AUTHORITY_REQUIRED`
- Pin catalog row 37.0.1 blocked (`blocked_pending_independent_sha256_pin`, zero digest, PENDING approval) → `QUALIFICATION_AUTHORITY_REQUIRED` and/or `INDEPENDENT_APPROVAL_REQUIRED`
- No Apply/Bootstrap invoked

**Expected track states**

| Track | State |
| --- | --- |
| `developer_stack` | `NEEDS_INSTALL` |
| `sas_adb` | `NEEDS_APPROVAL` |

**Expected flags**

- `inspection_complete=true`
- `operational_ready=false`
- `result=SUCCESS` (projection)
- `proof` contains `NEXT_PROJECTION` only (or plus prior fixtures if any)

**Expected primary actions (order)**

1. Developer primary: `DRAFT_HOST_PROFILE_REVIEW_PACKET` — `allowed_now=true` (drafting is read-only), `requires_authority=["adminbox_host_profile_approver"]`, `why_blocked=null` for the draft itself; companion `SUGGEST_APPLY_DEVELOPER` at rank 50 with `allowed_now=false`, `why_blocked=ADMINBOX_PROFILE_AUTHORITY_REQUIRED` (and still `MUTATION_AUTHORIZATION_REQUIRED` even after profile exists until operator authorizes Apply outside Next).
2. SAS primary: `DRAFT_PIN_INDEPENDENT_REVIEW_PACKET` — `allowed_now=true`; companion `SUGGEST_BOOTSTRAP_SAS` with `allowed_now=false`, `why_blocked=QUALIFICATION_AUTHORITY_REQUIRED` or `INDEPENDENT_APPROVAL_REQUIRED` (and profile code if also absent).

**Terminal sketch**

```text
Inspection: INSPECTION_COMPLETE
Operational: NOT_OPERATIONAL_READY
Developer stack: NEEDS_INSTALL
  next: DRAFT_HOST_PROFILE_REVIEW_PACKET allowed_now=true
SAS-ADB: NEEDS_APPROVAL
  next: DRAFT_PIN_INDEPENDENT_REVIEW_PACKET allowed_now=true
Authority packets: BOTH
```

**Negative assertions for tests**

- No subprocess for WinGet install, Fetch-Installers, or `android_provider_cli.py prepare`
- No write to host-profile.json with `RESOLVED`
- No pin catalog mutation
- `operational_ready` remains false while either track is non-ready
- AutoLogon `sas next` not invoked

---

## 11. Front-door and role binding

- Entrypoint: `Manage-AdminBoxAndroidToolchain.cmd Next`
- Starter forces `-NodeRole adminbox_reference`; `-NodeRole` override ⇒ `ADMINBOX_ROLE_OVERRIDE_FORBIDDEN`
- Desired-state ceiling: `Config/android-adminbox-toolchain-profile.json`
- Engine: `scripts/Invoke-SasAndroidToolchain.ps1` gains `Next` in ValidateSet (W2)
- PTop (`ptop_lab`) remains a separate role; Admin Box Next must not disguise PTop authority

---

## 12. Integrator checklist (W2)

1. Repair schema `operation` enum: add `Bootstrap`, validate against live Bootstrap receipts/fixtures.
2. Add `Next` to engine ValidateSet + schema enum; implement projection only.
3. Emit terminal + private JSON per sections 8–9.
4. Wire draft packet writers to ignored output roots; keep GitHub-sanitized.
5. Consume W1-C fixtures for ordering, independence, and no-mutation guarantees.
6. Do not require approvals merely to run Next.
7. Keep Apply and Bootstrap as separately gated registered operations.

---

## 13. Confidence and handoff

| Item | Confidence |
| --- | --- |
| Two-track state model matches P141 | HIGH |
| Reason-code reuse vs engine/pin | HIGH |
| Exact additive schema property names | MEDIUM (W2 may version-bump if `additionalProperties: false` blocks) |
| Live Admin Box packet channel owners | LOW (W1-B authority lane) |

**CHANGED:** this contract file only.
**PROVED:** static alignment to Inventory SUCCESS≠ready, blocked pin 37.0.1, Admin Box host-profile fail-closed codes, Bootstrap/schema drift note.
**NEXT:** W2 freeze this contract and implement; W1-C assert samples; W1-B supply private draft channel facts.
