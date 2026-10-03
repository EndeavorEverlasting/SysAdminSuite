# H&H CC Reader Live Execution Boundary

Date: 2026-10-03  
Status: P95 IMPLEMENTED  
Repository: `EndeavorEverlasting/SysAdminSuite`

## Decision

**Live firmware execution is the primary program.**

Harness work is a supporting lane. It may interrupt the live firmware lane only when a **confirmed harness defect** prevents the current live gate from consuming otherwise-valid evidence or safely performing the already-authorized step.

Everything else stays out of the critical path.

## Why this exists

The firmware program had begun accumulating useful harness, publication, and cross-repository work while the actual Kiosk4 deployment remained blocked on one live fact: the authoritative current firmware value.

That is a program-routing defect. A support system must not become the project it supports.

P95 therefore fixes ownership and call-stack routing rather than adding another deployment mechanism.

## Program owners

| Concern | Owner |
| --- | --- |
| live reader identity, baseline, eligibility, restore proof, mutation and runtime verification | SAS H&H CC-reader firmware program |
| harness architecture/refactoring not needed for the current gate | separate harness-maintenance successor lane |
| ticket/project roll-up and publication | `EndeavorEverlasting/nyc-hh-fieldops-lab` |
| operator credentials/MFA/physical device interaction | operator/runtime boundary |

## Call stack

```text
current proved live state
  -> identify the next firmware gate
  -> ask what actually blocks that gate
     -> no blocker / evidence available
        -> CONTINUE_LIVE_EXECUTION
     -> credentials, MFA, physical observation, or missing live value
        -> LIVE_RUNTIME_OR_OPERATOR_BOUNDARY
        -> obtain the evidence
        -> resume the same gate
     -> demonstrated harness defect rejects valid evidence or prevents the gate
        -> HARNESS_REPAIR_THEN_RESUME
        -> bounded repair only
        -> narrow validation
        -> resume the same live gate
     -> non-blocking architecture/harness improvement
        -> DEFER_HARNESS_MAINTENANCE
     -> tracker / Drive / OneDrive / project publication work
        -> DEFER_DOWNSTREAM_PROJECT_WORK
     -> stale repository/runtime
        -> REFRESH_RUNTIME_THEN_CONTINUE
     -> mutation authority or safety gap
        -> STOP_MUTATION_RESOLVE_AUTHORITY
```

The router is `harness/api/hh_cc_reader_live_execution_boundary.py`.

The machine contract is `harness/api/hh-cc-reader-live-execution-boundary.v1.json`.

## Harness-preemption test

Harness work may preempt the live lane only when all of these are true:

1. the defect is demonstrated, not speculative;
2. it blocks the current live gate;
3. a concrete evidence reference identifies the failure;
4. the repair can be bounded to that blocker;
5. after repair, execution resumes the same live gate.

A useful improvement, cleanup opportunity, schema enhancement, dashboard change, publication mechanism, or future batch feature does not satisfy this test.

## What is not a harness defect

These are operational boundaries and must not trigger a coding detour:

- missing estate credentials or MFA;
- missing authenticated firmware observation;
- need for physical `Software versions` capture;
- package/entitlement values that only the estate surface can expose;
- OneDrive unavailability;
- Google Drive/tracker publication delay;
- a desire for better generic architecture when the current live command already works.

## Current Kiosk4 application

Current proved state:

```text
UNIQUE_TARGET_RESOLVED
BASELINE_INCOMPLETE
BLOCKED_AUTHORITY / CREDENTIAL_GATE
```

Current gate:

`BASELINE_LOCKED`

Missing evidence:

`current_firmware_value` from an authoritative observation bound to the same Kiosk4 identity.

P95 classification:

```text
work_class = EXTERNAL_ACCESS_OR_LIVE_EVIDENCE
route = LIVE_RUNTIME_OR_OPERATOR_BOUNDARY
harness preemption = false
```

Immediate next action:

1. use an authorized Payment Fusion / Control Center / IngEstate or PAXSTORE terminal-management session;
2. bind the selected terminal to the already-proved Kiosk4 serial/MAC;
3. record the authoritative current firmware/build;
4. rerun the existing baseline evaluator;
5. require `BASELINE_LOCKED`;
6. continue immediately to eligibility and restore-path proof.

Fallback when the management surface cannot bind the terminal:

capture `Software versions` on the same physical Kiosk4 and use that observation in the private baseline input.

Do **not** respond to the current blocker with another network-discovery pass, generic public package search, tracker/publication work, or harness refactor.

## Failure prototype

A valid live firmware observation is supplied, but the existing baseline evaluator rejects it because its parser cannot represent the real portal value.

That is a demonstrated gate-blocking harness defect:

```text
BASELINE_LOCKED blocked by valid evidence rejection
-> HARNESS_REPAIR_THEN_RESUME
-> repair parser/schema only
-> focused regression
-> rerun BASELINE_LOCKED
```

The repair does not authorize redesign of unrelated firmware, publication, dashboard, or batch systems.

## Proof ceiling

This decision proves lane ownership and deterministic routing only.

It does not prove current Kiosk4 firmware, estate access, package entitlement, mutation authorization, forward deployment, rollback, final target deployment, or runtime verification.
