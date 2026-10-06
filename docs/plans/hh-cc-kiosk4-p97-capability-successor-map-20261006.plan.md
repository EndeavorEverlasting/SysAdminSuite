# Plan — Kiosk4 P97 Capability Frontier Successor Map

Date: 2026-10-06  
Status: `ACCEPTED_RESEARCH_FLOOR`  
Canonical research owner: `docs/research/hh-cc-kiosk4-p97-android-remote-capability-frontier-20261006.md`  
Repository floor at authoring: `origin/main@534dbb4e2bc26004e06e52f92e45201cf108a820`  
Mutation authority: `false` until a separate explicit gate

## Completed floor (P97)

- Exhaustive capability frontier with ≥35 evidence-typed hypotheses across ≥10 families.
- Systemic correction: prior AirViewer/ADB/network exclusions were sprint-local, not global irrelevance.
- Read-only workstation proof: ADB client not on PATH; private capture remains empty stub.
- Firmware gate unchanged and parallel: `BASELINE_LOCKED=false`, missing `current_firmware_value`.

## Forbidden (global until explicit authority)

- Production firmware push; app install/uninstall; enable Developer Options / USB debugging / network ADB
- Management enrollment changes; wipe/reboot for experimentation; parameter/payment/network mutation
- Credential brute-force; exploit; TLS MITM; PAN/PHI/secret ingestion into Git
- Reopen closed local menu crawls or broad inbound scans

## Successor phases (dependency-aware)

### Phase 0 — Firmware label (parallel; existing owner)

- **Owner:** existing observation program / P82 post-observation path
- **Action:** fill authorized labeled observation → classify → baseline attempt
- **Does not block** Phases 1–3 research/access work
- **Gate:** `BASELINE_LOCKED` or exact fail-closed blocker

### Phase 1 — Control-plane identity bind (P82)

- **Owner:** P82 with Kurt/Dennis access coordination
- **Hypothesis:** same Kiosk4 SN appears on at least one authorized console with inventory fields
- **Measure:** terminal record present; fields (apps/firmware/online/AirViewer); which plane
- **Artifact:** sanitized observation receipt (private) + public checklist update
- **Gate:** `CONTROL_PLANE_BOUND` or `PLANE_ACCESS_BLOCKED=<exact>`

### Phase 2 — Package / agent architecture proof (P82 → P07 docs)

- **Depends on:** Phase 1 access
- **Action:** enumerate management-related packages/agents (PAXSTORE, AirViewer, TMS, AxiaMed, etc.)
- **Gate:** `MANAGEMENT_AGENT_CLASSIFIED`

### Phase 3 — Remote-support trial design (authority-gated)

- **Depends on:** Phase 2 showing AirViewer or equivalent
- **Action:** one scheduled view-only session; document approve UX; no config changes
- **Gate:** `REMOTE_VIEW_PROVEN` or `REMOTE_SUPPORT_ABSENT`

### Phase 4 — Passive outbound fingerprint (P82)

- **Depends on:** netops approval; can run parallel to Phase 1 if SPAN ready
- **Action:** DNS/SNI/timing during console refresh; no MITM; no payment payloads
- **Gate:** `OUTBOUND_OWNER_CLUSTER_LABELED`

### Phase 5 — Lab twin bootstrap (procurement / lab)

- **Owner:** Kurt procurement + lab ops
- **Action:** non-prod A80; authorized ADB; procedure library for getprop/pm/dumpsys/scrcpy
- **Gate:** `LAB_TWIN_READY`

### Phase 6 — Fleet visibility seam (P07; after Phase 1–2)

- **Action:** map console exports into existing estate-packet / tracker enrichment contracts — do not invent duplicate orchestrator
- **Gate:** `FLEET_HEALTH_SCHEMA_BOUND`

### Phase 7 — Governed lifecycle (only after baseline + restore + authority)

- **Depends on:** Phase 0 `BASELINE_LOCKED`, live restore proof, explicit mutation authority
- **Action:** staged app/firmware/parameter rings with verification receipts
- **Gate:** existing firmware mutation gates in live-execution boundary

## P04 factoring — winning opportunities (do not spawn 20 sprints)

Select **one** implementation slice after Phase 1 evidence:

1. **Highest information value / lowest authority cost:** control-plane bind + package inventory runbook (Phases 1–2).
2. **Highest operational leverage:** remote-support trial (Phase 3) if agent present.
3. **Lowest production risk adjunct:** passive outbound fingerprint (Phase 4) and/or lab twin (Phase 5).

## Proof ceiling

Phases 1–5 remain observation/lab until explicit mutation gates. Research must not be promoted to production capability claims.

## Next executable action

```text
Owner: operator + Kurt/Dennis
Dependency: authorized Experian/CC or PAXSTORE Administrator Center (or provider console) for same Kiosk4 identity
Action: open read-only terminal detail; capture sanitized field inventory (no push)
Expected artifact: private observation notes + update to live-execution boundary next_action if plane proven
Completion gate: CONTROL_PLANE_BOUND or exact access blocker named
```

Parallel firmware track remains: fill `%TEMP%\hh-cc-kiosk4-labeled-firmware-observation.json` with one labeled installed-version row — without inventing values.
