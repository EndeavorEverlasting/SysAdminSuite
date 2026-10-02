# H&H CC Reader — P5 read-only estate session runbook

Status: operator procedure
Pinned policy floor: `main` @ `204a3bb93609d4c4e1751dddd7ea466918ef7b05` (refresh before use)
Lane: P5 management-plane discovery only — **not** P6 pilot mutation

## Authority

| Surface | Role |
| --- | --- |
| `harness/api/hh-cc-reader-firmware-policy.json` → `proven_path_acceptance` | Machine PROVEN_PATH acceptance |
| `harness/api/hh-cc-reader-firmware-policy.json` → `readonly_estate_checklist` | Ordered 12-item checklist + forbidden actions |
| `harness/api/hh_cc_reader_estate_authority.py` | Executable evaluator |
| `docs/HH_CC_READER_NETSTAT_BASELINE.md` | Durable P5 ledger + packet prose |
| `docs/examples/hh-cc-reader-proven-path-authority-packet.template.json` | Sanitized fill-in template (not a second authority) |

This runbook does **not** replace the machine policy. If prose and policy disagree, policy + evaluator win.

## Goal

Use **one** already-authorized read-only session on **one** eligible surface, complete the 12 observations, fill the seven authority fields, then evaluate. Stop at the first real discriminator the evaluator returns.

Eligible `mechanism_id` values (pick exactly one):

- `payment-fusion-control-center`
- `paxstore-ota-push`
- `provider-auto-update`

Ineligible: `terminal-tms-pull` (`NOT_APPLICABLE` — do not restage local TMS/NTMS menus).

You do **not** need three live sessions. One complete path is enough for P5.

## Preconditions

1. Refresh SysAdminSuite to current `main` (expect firmware policy + evaluator present).
2. Confirm you already have authorized read access to exactly one eligible surface. If not, stop: disposition remains `CREDENTIAL_GATE` / `next_gate=AUTHORIZED_READONLY_SESSION`.
3. Copy the template to an **external** operator workspace (not Git):

```text
docs/examples/hh-cc-reader-proven-path-authority-packet.template.json
  → external fill copy (private evidence workspace)
```

4. Assign a non-secret `AUTHORITY_PACKET_ID` before capturing restricted artifacts.
5. Set `MUTATION_PERFORMED=false`, `mutation_intent=false`, `mutation_actions_observed=[]`.

## Forbidden during discovery

Do not: push, assign, activate, approve, reset, sideload, enroll, reassign, change network, change package, change policy, or write. Observing an affordance is allowed; invoking it is not.

## Minimum read role by surface

| mechanism_id | Minimum role |
| --- | --- |
| `payment-fusion-control-center` | authorized read exposing representative terminal, firmware/software state, and automatic-update policy or assignment controls |
| `paxstore-ota-push` | Readonly Firmware List + Terminal Management |
| `provider-auto-update` | authorized read of Control Center/IngEstate or PAXSTORE estate views for update-policy, job, and package state |

Full/write/push is **not** required for discovery.

## Ordered session procedure

Copy the template's `evaluator_inputs` and update fields as each step succeeds. Mark the matching `checklist_satisfied.<id>=true` only when the observation is actually made.

### 1. `confirm-authorized-readonly-session`

- Open the chosen eligible surface with the already-authorized account.
- Set `authorized_readonly_session=true`.
- Set `mechanism_id` to that surface's id.
- If login fails or entitlement is missing: `access_state=BLOCKED_AUTHORITY`, stop. Do not widen into reader diagnostics.

### 2. `confirm-minimum-read-role`

- Confirm the session meets the minimum role table above.
- Set `role_scope_ok=true` only when confirmed.
- Else stop; evaluator next gate is `CONFIRM_MINIMUM_READ_ROLE`.

### 3. `locate-representative-a80`

- Locate the representative H&H A80 record **without** add / activate / reassign / enroll.
- If not found: stop at `BIND_REPRESENTATIVE_A80` / locate failure — do not create the terminal.

### 4. `bind-reader-identity-ref`

- Set `reader_identity_ref` to a **non-secret** external index key only.
- Set `representative_terminal_bound=true`.
- Live serial/IP/MAC stay outside Git and outside this packet.

### 5. `observe-current-firmware`

- Record the authoritative current firmware/package shown for that terminal.
- Put the sanitized version string into acceptance `CURRENT_FIRMWARE_OBSERVED`.
- Set `current_firmware_observed=true`.

### 6. `inspect-automatic-update-policy`

- Inspect automatic-update policy / job / package state.
- Do not initiate, alter, approve, or cancel a task.

### 7. `resolve-target-package-visibility`

- Resolve whether planning candidate `2.0.15.260522` is exposed.
- Set `package_exposed_for_target` to `YES` | `NO` | `UNKNOWN`.
- If `YES`: set `package_release_id` to the exact sanitized release/list id.
- If `NO`: set `package_release_id` to `NONE_OBSERVED` (package conflict, not substitution).
- If `UNKNOWN`: add `unknown_reasons.PACKAGE_EXPOSED_FOR_2_0_15_260522` with an explicit reason (≥ 8 characters).

### 8. `record-assignment-method`

- Record the surface's own assignment/update verb/affordance.
- Observe only; do not invoke.
- Map into `assignment_method` / `ASSIGNMENT_METHOD`.

### 9. `record-reboot-reconnect-behavior`

- Record required reboot / reconnect / wait behavior from the same authority → `reboot_reconnect_behavior`.

### 10. `record-rollback-exception-path`

- Record rollback / cancel / exception handling → `rollback_exception_path`.

### 11. `record-post-update-acceptance`

- Record the authority's post-update success criterion → `post_update_acceptance`.

### 12. `emit-sanitized-authority-packet`

- Ensure all seven required packet fields are answered (or UNKNOWN + reason).
- Set `access_state=PROVEN_ACCESS` only when the session truly proved access for that surface.
- Set `authority_packet_id` to the non-secret packet id.
- Index external artifacts (terminal view, package view, affordance text, reboot/rollback/acceptance text) outside Git.
- Set `SOURCE_SURFACE` / `MANAGEMENT_OWNER` as **outputs** of this observation, not as something a coworker must invent first.

## Evaluate (required)

From a refreshed SysAdminSuite checkout on current `main`:

```bash
python -c "import json; from harness.api.hh_cc_reader_estate_authority import evaluate; print(json.dumps(evaluate(<evaluator_inputs>), indent=2, sort_keys=True))"
```

Or paste `evaluator_inputs` into a local throwaway script. Do not invent a second evaluator.

### Expected terminal states

| Condition | Typical result |
| --- | --- |
| No session | `BLOCKED_AUTHORITY` / `CREDENTIAL_GATE` / `AUTHORIZED_READONLY_SESSION` |
| Role insufficient | `INCOMPLETE` / `CONFIRM_MINIMUM_READ_ROLE` |
| Reader unbound | `INCOMPLETE` / `BIND_REPRESENTATIVE_A80` |
| Firmware not observed | `INCOMPLETE` / `OBSERVE_CURRENT_FIRMWARE` |
| Checklist incomplete | `INCOMPLETE` / `COMPLETE_READONLY_CHECKLIST` |
| Packet fields incomplete | `INCOMPLETE` / `COMPLETE_ESTATE_AUTHORITY_PACKET` |
| Access not proven | `INCOMPLETE` / `SET_ACCESS_STATE_PROVEN_ACCESS` |
| Complete + package YES | `COMPLETE` / `PROVEN_PATH` / `mutation_authorized=false` / `P6_SEPARATE_PILOT_AUTHORIZATION` |
| Complete + package NO | `COMPLETE` / `PROVEN_PATH` / `package_conflict=true` / `RESOLVE_PACKAGE_CONFLICT_BEFORE_P6` |
| Forbidden mutation observed | `REJECTED` / `DISCOVERY_MUTATION_FORBIDDEN` |

A `PROVEN_PATH` proposal still leaves `mutation_authorized=false`. P6 remains a separately authorized one-reader pilot.

## Explicit non-goals

- Public owner hunting or generic package archaeology
- Local reader-menu / TMS/NTMS restaging
- Logging into all three eligible surfaces “for completeness”
- Committing live identifiers or restricted screenshots
- Treating this runbook or the JSON template as machine promotion authority
- Firmware push / assign / activate under any reading of a complete packet

## Proof ceiling

Completing this runbook + evaluator pass proves **management-path observation for planning**. It does not prove site execution authority, fleet readiness, or pilot authorization.
