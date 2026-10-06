# Plan — Kiosk4 P97 Capability Frontier Successor Map

Date: 2026-10-06
Status: `SUPERSEDED_CRITICAL_PATH_BY_ADMIN_BOX_ADB`
Canonical research owner: `docs/research/hh-cc-kiosk4-p97-android-remote-capability-frontier-20261006.md`
Canonical execution owner after operator decision 2026-10-06: `docs/plans/hh-cc-kiosk4-p04-p82-adminbox-adb-control-plane-20261006.plan.md`
Repository floor at authoring: `origin/main@534dbb4e2bc26004e06e52f92e45201cf108a820`
Hypothesis bookkeeping: **H01–H51 (51 hypotheses)**. H48 is the single-click diagnostic-bundle row; H49–H51 are AirLauncher, Terminal Center restart, and firmware no-downgrade. Do not report "48" as the canonical total.
Mutation authority: `false` until a separate explicit gate

## Operator decision (do not re-litigate)

The Admin Box is the control plane. ADB is the first vendor-independent transport.
Vendor management consoles remain documented optional/parallel estate capability.
They are not the critical path and are not a prerequisite for Admin Box ADB work.

## Completed floor (P97)

- Exhaustive capability frontier with **51** evidence-typed hypotheses (H01–H51) across research families.
- Systemic correction: prior AirViewer/ADB/network exclusions were sprint-local, not global irrelevance.
- Read-only workstation proof at P97 time: ADB client not on PATH (repository `REPOSITORY_CAPABILITY` gap, not a Kiosk4 `DEVICE_CAPABILITY` proof).
- Firmware gate unchanged and parallel: `BASELINE_LOCKED=false`, missing `current_firmware_value`.

## Forbidden (global until explicit authority)

- Production firmware push; app install/uninstall; wipe/reboot for experimentation; parameter/payment/network mutation
- Enabling Developer Options / USB debugging / persistent network ADB when those controls are currently off
- Management enrollment changes
- Credential brute-force; exploit; TLS MITM; PAN/PHI/secret ingestion into Git
- Reopen closed local menu crawls or broad inbound scans

Authorized now: Admin Box official Platform-Tools; USB/PnP; `adb devices`; authorization observation; read-only ADB inventory; exact-target network ADB live-cert with revert; view-only remote display.

## Successor phases (dependency-aware)

### Phase 0 — Firmware label (parallel; existing owner)

- **Owner:** existing observation program / Admin Box ADB inventory adapter
- **Action:** fill authorized labeled observation (console **or** authorized ADB getprop adapter) then classify then baseline attempt
- **Does not block** Admin Box ADB transport work
- **Gate:** `BASELINE_LOCKED` or exact fail-closed blocker

### Phase 1 — Admin Box ADB control-plane bind (P04/P82) — CURRENT CRITICAL PATH

- **Owner:** SysAdminSuite technician CMDs on the Admin Box
- **Hypothesis:** official Platform-Tools plus USB ADB can establish a typed session to the authorized Kiosk4
- **Measure:** typed host/USB/device/auth states; `unauthorized` is transport proof
- **Artifact:** ignored `survey/output/hh-cc-reader/` receipts plus private raw evidence
- **Gate:** `ADB_DEVICE_READY` or exact attended RSA retry / USB discriminator
- **Not this phase:** Experian/PAXSTORE login

### Phase 2 — Read-only Android inventory plus firmware adapter (depends on Phase 1 ready)

- **Action:** getprop/pm/ps/ip/dumpsys; adapt into `Classify-HHCCReaderVersionDomain.cmd`
- **Gate:** `ADB_READONLY_INVENTORY_CAPTURED` or `_PARTIAL`; firmware domain bind or explicit unbound

### Phase 3 — Exact-target network ADB transaction (depends on ready plus identity bound)

- **Action:** USB tcpip 5555 then exact-IP connect then read-only proof then USB revert proof
- **Gate:** `NETWORK_ADB_CERTIFIED` plus `NETWORK_ADB_REVERTED` (or `NETWORK_ADB_REVERT_FAILED`)
- **Forbidden:** subnet scan; persistence-by-accident

### Phase 4 — View-only remote display (depends on proven ADB)

- **Action:** scrcpy-equivalent `--no-control` if a local tool already exists
- **Gate:** `REMOTE_VIEW_PROVEN` or attended inconclusive
- **Separate:** remote-control/input certification

### Phase 5 — Optional/parallel vendor-estate capability (not blocking)

- **Owner:** Kurt/Dennis access coordination when useful
- **Action:** read-only Experian/CC, TMS, or PAXSTORE Admin inventory
- **Gate:** `ESTATE_PLANE_OBSERVED` or exact access blocker
- **Note:** optional evidence source; overlap with ADB inventory is explicit (`DEVICE_CAPABILITY` vs estate console)

### Phase 6 — Lab twin / fleet seams / governed lifecycle

Unchanged from prior P97 map; still after baseline plus restore plus explicit mutation authority.
Firmware OTA remains documented non-downgradable.

## P04 factoring — winning opportunities

1. **Now:** Admin Box ADB control plane (Phases 1–4).
2. **Parallel optional:** vendor-console inventory (Phase 5) when credentials exist.
3. **Firmware:** Phase 0 using ADB-adapted labeled observations when USB ready.

## Proof ceiling

Phases 1–4 prove Admin Box transport and read-only observation. They do not authorize mutation.
Vendor-console research is retained, not erased.

## Next executable action

```text
Owner: technician on Admin Box
Dependency: none on proprietary consoles
Action: Evaluate-HHCCReaderAdbControlPlane.cmd
Expected artifact: typed receipt under survey/output/hh-cc-reader/
Completion gate: highest typed live state or exact attended RSA retry
```
