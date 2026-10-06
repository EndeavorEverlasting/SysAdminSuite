# P97 — Kiosk4 Android / Remote Capability Frontier

Date: 2026-10-06
Mode: `P97_EXHAUSTIVE_CAPABILITY_FRONTIER`
Repository: `EndeavorEverlasting/SysAdminSuite`
Floor: `origin/main@534dbb4e2bc26004e06e52f92e45201cf108a820` (contains PR #498 / `aeff924c`)
Mutation authority: `false` (research + durable analysis only)
Firmware gate (unchanged): `BASELINE_LOCKED=false`, `MUTATION_AUTHORIZED=false`, missing=`current_firmware_value`

## Purpose

Determine, evidence-first, what is technically possible with the provisioned PAX A80 / Android SmartPOS endpoint and its surrounding management, USB, application, telemetry, automation, and remote-support surfaces — **now** and in plausible **authorized** successor states.

Firmware remediation is **one row**, not the boundary of the problem.

Rule preserved throughout:

```text
ANDROID_SUPPORTS != KIOSK4_PROVEN
REAL_WORLD_CAPABILITY ≠ PROJECT_EVIDENCE
```

## Systemic correction

Earlier firmware-gate sprints correctly **excluded** AirViewer, ADB, and generic remote/network work **inside those narrow lanes**. That exclusion is **not** a permanent declaration that those mechanisms are worthless.

| Prior sprint exclusion | Correct interpretation after P97 |
| --- | --- |
| AirViewer / remote view blocked during firmware observation | Wrong tool for labeling `current_firmware_value`; still a high-leverage remote-support mechanism when estate-provisioned |
| ADB / USB-ADB blocked | Must not be enabled on production without authority; still the canonical lab introspection mechanism and a discriminator if already present |
| Broad inbound scans closed | Value is outbound/device-initiated control planes, not listening-port hunting |
| Local AxiaMed menu closed | Interesting capabilities are not primarily exposed through that UI |

## Proven Kiosk4 floor (do not rediscover)

From PR #498 / live-execution boundary / private capture recovery:

| Fact | State |
| --- | --- |
| Identity | `UNIQUE_TARGET_RESOLVED` |
| Capture file | `%TEMP%\hh-cc-kiosk4-labeled-firmware-observation.json` exists |
| Capture schema | `sas-hh-cc-reader-kiosk4-version-evidence-capture/v1` |
| Capture content | `AWAITING_FIELD_OBSERVATION`, `labeled_observations=0` |
| Classifier | `VERSION_DOMAIN_UNRESOLVED` / primary null |
| Baseline | `BASELINE_INCOMPLETE` / missing `current_firmware_value` |
| Mutation | `MUTATION_AUTHORIZED=false` |
| Local AxiaMed menu | Closed (Connectivity Test, Netstat, Network Settings, FUNC/ALPHA discovery) |
| PAXSTORE access discovery | App Store reached; Administrator Center entitlement `UNPROVEN` |
| Protocol portfolio | Additive: Experian/CC → TMS/NTMS → provider automatic → PAXSTORE → lab PayDroid tool |

This P97 sprint **does not** invent the missing firmware label.

## Read-only experiments run this sprint

| Experiment | Result | Proof level |
| --- | --- | --- |
| Refresh `origin/main` + containment of `aeff924c` | Contained in `534dbb4e` | Repository |
| Private capture schema/state inspect (no secrets committed) | Exists; empty stub; `mutation_authorized=false` | Local runtime metadata |
| `adb` on operator PATH / `adb devices` | **ADB client not present on PATH** | `ADB_STATE=NOT_CURRENTLY_AVAILABLE` (workstation tooling) |
| Broad inbound rescan | **Not run** (closed) | N/A |
| Enable Developer Options / USB debugging | **Forbidden / not attempted** | Authority gate |

Interpretation: absence of `adb` on this workstation does **not** prove the reader lacks ADB; it proves this sprint cannot exercise ADB introspection without installing/locating an authorized client **and** an already-enabled device seam.

---

## Prior-art lanes (summary)

### Lane A — PAX / MAXSTORE / PAXSTORE / AirViewer

Official/public sources establish MAXSTORE/PAXSTORE as a cloud estate platform with:

- app distribution / policy-based push (incl. group templates; Open API `createTerminalApk`);
- firmware subscribe + push (Open API firmware push; **documented no-downgrade after upgrade**);
- parameter variables (marketplace / merchant / terminal; partial push on newer releases);
- terminal management inventory + Terminal Monitor (CPU/RAM/battery/storage);
- monitoring / estate dashboards / alerts / webhooks;
- CloudMessage;
- CheckUp hardware self-test + Logcat download (per AirViewer QRG);
- Terminal Center remote **restart** (docs tie to PUK certificate);
- **AirViewer** remote view + remote control (Premium Marketplace / VAS);
- **AirLauncher** VAS (settings lockdown / keep-app-foreground kiosk patterns);
- GoInsight analytics;
- Geofencing (Premium lock/unlock claims);
- Rhino RKI (remote key injection) as a documented VAS (authority-gated; not pursued here).

AirViewer requirements (PAXSTORE AirViewer QRG v1.3):

1. Active PAXSTORE terminal profile;
2. Terminal powered on + Internet;
3. AirViewer app installed/enabled (auto-push possible on first PAXSTORE connect);
4. Role permission for AirViewer (and separately Unattended Mode);
5. Terminal-user approve for view; second approve for full control (60s timeout) unless unattended mode authorized;
6. Unattended path (model whitelist): no answer ~15s → auto-connect; idle disconnect ~5 min.

Lane A residual deltas retained after parallel prior-art completion (still `DOCUMENTED_UNVERIFIED`; not Kiosk4-proven):

| Delta | Operational consequence |
| --- | --- |
| Firmware **cannot be downgraded** after OTA upgrade (Admin Guide) | Phase 7 restore story cannot assume FW rollback via lower image; need alternate restore proof |
| Terminal Center **remote restart** + PUK | Sharpens remote-reboot hypothesis as PAXSTORE-native, not only Android DPC |
| AirLauncher VAS | Separate from AirViewer; candidate for reducing local misconfig truck rolls if estate-licensed |
| Open API rate limit / External System Access + egress IP allowlist | Matches existing repo observe seam; entitlement still the gate |
| Geofence Premium lock | Low priority for fixed hospital kiosk; retain as UNKNOWN/low unless theft/loss use case appears |

Sources:

- https://www.pax.us/marketplace/airviewer/
- https://www.pax.us/wp-content/uploads/2024/02/PAXSTORE-AirViewer-QRG-11-05-2023-V1.3.pdf
- https://www.paxtechnology.com/maxstore-vas
- https://www.pax.us/marketplace/
- https://www.pax.us/marketplace/airlauncher/
- https://marketing.paxtechnology.com/blog/understanding-paxstore-value
- https://faqs.pax.us/wp-content/uploads/2020/05/PAXSTORE-Marketplace-Admin-Guide_v1.0-2.pdf
- https://github.com/PAXSTORE/paxstore-openapi-java-sdk

### Lane B — Android Enterprise / DPC

Official Android Device Owner / dedicated-device (COSU) patterns support lock-task, app allowlists, remote reboot (`DevicePolicyManager.reboot`), remote bugreport (`requestBugreport`), security/process logging, system-update policy, and hardware restrictions.

**Portability caveat:** PayDroid/PAX estates commonly use **vendor privileged agents** and PAXSTORE/MAXSTORE rather than Google's standard Android Enterprise DPC stack. Patterns are conceptually portable; APIs are not assumed present on Kiosk4.

Sources:

- https://developer.android.com/work/dpc/dedicated-devices/lock-task-mode
- https://developer.android.com/work/dpc/security
- https://developer.android.com/work/dpc/device-management
- https://developer.android.com/work/dpc/dedicated-devices/cookbook

### Lane C — ADB / scrcpy / diagnostics

Authorized ADB enables read-only introspection (`getprop`, `pm`, `dumpsys`, `logcat`, `bugreport`). `scrcpy` mirrors/controls without root or permanent app install, but **requires USB debugging already authorized**.

Sources:

- https://github.com/Genymobile/scrcpy
- https://developer.android.com/studio/command-line/adb

### Lane D — SysAdminSuite evidence

Canonical owners already model multi-plane observation (Experian/CC, TMS/NTMS, provider automatic, PAXSTORE, lab PayDroid), PAXSTORE OpenAPI observe seams, version-domain classification, live-execution boundary, and Kiosk4 menu closure. No prior `docs/research/*p97*` owner existed; this file is the new canonical frontier.

### Lane E — Network / control plane

Inbound listener hunting is closed (`REMOTE_ENDPOINT_CANDIDATE=NONE` on the preserved Netstat/Connectivity discriminator set — do not restage another physical reader window for a newer `RUN_ID`).

Modern SmartPOS management is typically **device-initiated outbound TLS**. Existing Kiosk4-adjacent evidence already records a device-side Connectivity Test label **PAX Store Push Service Primary (443)** plus a truncated second PAX push entry (`docs/HH_CC_READER_NETSTAT_BASELINE.md`). That is a **correlation candidate** for a PAXSTORE phone-home path — not estate ownership proof, not a resolved DNS/SNI/flow fingerprint, and not firmware authority.

Still missing: a sanitized outbound DNS/SNI/timing fingerprint bound to this identity during an authorized console action. Passive SPAN/gateway correlation is the correct next discriminator — not another port scan or Connectivity Test replay.

### Lane F — Kurt / fleet leverage

Highest operational value clusters around: (1) authorized management-plane inventory + remote diagnostics, (2) AirViewer-class remote support if provisioned, (3) app/firmware/parameter lifecycle without truck rolls, (4) ticket enrichment from device health evidence, (5) fail-closed SysAdminSuite contracts already built for observation → baseline → (later) mutation.

---

## Evidence / disposition vocabulary

**Evidence states:** `OBSERVED_IMPLEMENTED` | `DOCUMENTED_UNVERIFIED` | `INFERRED` | `ABSENT` | `UNKNOWN`

**Dispositions:** `ADOPT` | `ADAPT` | `REJECT` | `UNKNOWN`

**Bands:**

- **A** — Proven / immediately read-only
- **B** — Authority-ready (credible; needs estate/vendor access)
- **C** — Lab prototype
- **D** — Reject / not worth pursuing for production

---

## Capability hypothesis matrix (≥35)

| ID | Capability | Real-world prior art | P97 evidence state | Kiosk4 evidence | Safe read-only discriminator | Required authority | Operational value | Fleet leverage | Risk | Disposition | Band | Next owner |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| H01 | Android/PayDroid release introspection | A80 datasheets Android 6/7/10; `getprop` | DOCUMENTED_UNVERIFIED | Android SmartPOS known; exact build unobserved | Settings→Software versions OR authorized console OS field OR ADB `getprop` if already enabled | Device UI / console / ADB-if-present | High — pins security/patch expectations | High | Low if read-only | ADOPT | A/B | Operator observation / P82 |
| H02 | Build fingerprint / security patch | Android `ro.build.*` | DOCUMENTED_UNVERIFIED | Absent in capture | Same as H01 | Same | Medium | Medium | Low | ADAPT | B | Observation lane |
| H03 | Kernel / uptime / storage / mem pressure | `dumpsys` / management telemetry | DOCUMENTED_UNVERIFIED | Unknown on device | Console health widgets; ADB dumpsys if present | Console/ADB | Medium diagnostics | High if fleet | Medium log risk via ADB | ADAPT | B | Management access |
| H04 | Device-policy / Device Owner posture | Android DPC `dumpsys device_policy` | UNKNOWN | No DO evidence; AxiaMed kiosk-like UI | Package/admin inventory via console or ADB | Console/ADB | High architecture clarity | High | Low read-only | UNKNOWN | B | P82 package/policy probe |
| H05 | Installed package inventory | `pm list packages`; PAXSTORE App & Firmware tab | DOCUMENTED_UNVERIFIED | Not enumerated on Kiosk4 | PAXSTORE TM / Control Center app list / ADB pm | Estate entitlement | **Critical** — reveals management agent | High | Low | ADOPT | B | PAXSTORE/CC observe |
| H06 | Management-agent package detection | PAXSTORE agent / AirViewer / TMS clients | INFERRED | Likely present somehow (provisioned reader) | Search package names for paxstore/airviewer/tms/ingestate/axiamed | Same as H05 | Critical | High | Low | ADOPT | B | Same |
| H07 | Experian/AxiaMed Control Center remote mgmt | PAX×AxiaMed public partnership; protocol portfolio | DOCUMENTED_UNVERIFIED | Preferred protocol when evidenced; not live-proven for Kiosk4 | Open authorized CC for same SN; capture enrollment | Experian/CC account | Highest estate-native path | High | Low observe | ADOPT | B | Kurt/Dennis / CC access |
| H08 | Provider TMS / NTMS | Device-initiated TMS prior art; protocol portfolio | UNKNOWN | Not confirmed | Local TMS config read (no endpoint change) | Device UI owner | High if bound | Medium | Config-view only | UNKNOWN | B | Field observe |
| H09 | PAXSTORE Terminal Management inventory | Official Admin/Reseller guides | DOCUMENTED_UNVERIFIED | App Store reached; Admin Center **UNPROVEN** | Prove Administrator Center / TM role for estate | Reseller/admin entitlement | High corroboration | High | Low observe | ADOPT | B | Entitlement chase |
| H10 | PAXSTORE OpenAPI terminal observe | Repo seam `Observe-HHCCReaderPaxstoreTerminal.cmd` | OBSERVED_IMPLEMENTED (code) | Credentials/entitlement unknown | Env-gated observe or fixture-only (fixture ≠ live) | API key + estate authority | High automation | High | Secret handling | ADAPT | B | Harness + credentials |
| H11 | AirViewer remote screen view | Official AirViewer QRG/product page | DOCUMENTED_UNVERIFIED | Not proven provisioned | Console: AirViewer icon + on-device app present | Premium MP + role + merchant approve | **Very high** truck-roll reduction | High | Session audit / screen content | ADOPT | B | Estate owner |
| H12 | AirViewer remote input/control | Same; dual approve | DOCUMENTED_UNVERIFIED | Unknown | Apply-for-control + approve path works | Same + control permission | Very high | High | Higher than view | ADOPT | B | Same |
| H13 | AirViewer unattended mode | QRG role permission | DOCUMENTED_UNVERIFIED | Unknown; may be inappropriate for attended kiosk | Role flag exists? | Explicit unattended policy | High for true kiosks | Medium | PCI/ops policy | ADAPT | B | Security/ops approval |
| H14 | Vendor remote help-desk (non-AirViewer) | Payment Fusion / IngEstate support tooling | UNKNOWN | Named in contracts; live UI unknown | Authorized console remote-assist menu | Provider console | High | High | Session content | UNKNOWN | B | Provider access |
| H15 | ADB USB already enabled | Android USB debugging | ABSENT (workstation) / UNKNOWN (device) | `adb` not on PATH; device state unknown | Locate authorized platform-tools; `adb devices` only — **do not enable** | None if already on | High lab/introspect | Low on prod fleet | High if forced enable | UNKNOWN | A/B | Workstation tooling check |
| H16 | scrcpy-style mirror | Genymobile scrcpy | DOCUMENTED_UNVERIFIED | Not usable without ADB | Lab only if ADB authorized | LAB ADB | High lab support | Lab | Production REJECT without estate path | ADAPT | C | Lab twin |
| H17 | Remote reboot | DPC reboot; MAXSTORE remote ops claims | DOCUMENTED_UNVERIFIED | Unknown | Console reboot action exists? | Mutation authority | High MTTR | High | Service interruption | ADAPT | B | Authority gate |
| H18 | Connectivity / IP / link state remote | PAX monitoring; dumpsys connectivity | DOCUMENTED_UNVERIFIED | Local Network Settings closed as crawl | Console network widgets | Console | High pre-dispatch triage | High | Low | ADOPT | B | Console |
| H19 | App health / crash / last-seen | Estate telemetry / GoInsight | DOCUMENTED_UNVERIFIED | Unknown | Online/offline + app status fields | Console | High dispatch filter | High | Low | ADOPT | B | Console |
| H20 | Hardware CheckUp diagnostics | AirViewer QRG CheckUp app | DOCUMENTED_UNVERIFIED | Unknown installed | Push/observe CheckUp results | PAXSTORE role | Medium onsite reduction | Medium | Low | ADAPT | B | PAXSTORE |
| H21 | Sanitized log / Logcat retrieval | CheckUp Logcat download; bugreport | DOCUMENTED_UNVERIFIED | Risk of payment content | Prefer console sanitized bundles; redact | RISK_GATED | High hard cases | Medium | **PCI/log content** | ADAPT | B | Security review |
| H22 | Full bugreport | Android `bugreport` / DO remote bugreport | DOCUMENTED_UNVERIFIED | Unknown | Only if authorized + redaction pipeline | RISK_GATED / LAB | High forensics | Low | High — secrets/PAN risk | ADAPT | C/B | Security |
| H23 | Outbound management heartbeat TLS | SmartPOS device-initiated control planes | INFERRED | Connectivity label **PAX Store Push Service Primary (443)** is a correlation candidate; Netstat/Connectivity closed with `REMOTE_ENDPOINT_CANDIDATE=NONE`; no DNS/SNI/flow fingerprint yet | Passive SPAN DNS/SNI/timing during console refresh — no MITM; do not replay Connectivity/Netstat | Network observe approval | Architecture clarity | High | Metadata-only | ADOPT | B | Netops + P82 |
| H24 | Distinct Experian vs PAX vs TMS endpoint clusters | Multi-protocol portfolio | UNKNOWN | Protocols modeled; live endpoints not bound | Correlate DNS names to owner | Same | Escalation routing | High | Low metadata | UNKNOWN | B | P82 network |
| H25 | App push independent of firmware | PAXSTORE app push | DOCUMENTED_UNVERIFIED | Entitlement unproven | Admin Center Push App UI/API | Push authority | High lifecycle | High | Change control | ADAPT | B | Estate |
| H26 | Firmware OTA push | PAXSTORE firmware push; MAXSTORE OTA | DOCUMENTED_UNVERIFIED | Baseline incomplete blocks mutation | Inventory-only first | Firmware mutation authority | Core program | High | High | ADAPT | B | Firmware program |
| H27 | Parameter / config push | Parameter Variables QRG | DOCUMENTED_UNVERIFIED | Unknown | Parameter report / variables UI | Parameter authority | High config drift fix | High | Payment config risk | ADAPT | B | Estate |
| H28 | Messaging to device | CloudMessage VAS | DOCUMENTED_UNVERIFIED | Unknown | Message send UI exists? | Messaging role | Medium tech notice | Medium | Low | UNKNOWN | B | Estate |
| H29 | Update completion proof / health confirm | Estate push status + post-check | DOCUMENTED_UNVERIFIED | Roundtrip harness exists in repo | Push status + re-observe version | Observe+mutate | Critical closure | High | Low observe | ADOPT | B | Harness |
| H30 | Rollback cohort | Platform-dependent | UNKNOWN | Restore live-unknown in checkpoint | Explicit restore path proof before mutate | Restore authority | Critical safety | High | High if missing | UNKNOWN | B | Firmware program |
| H31 | Fleet inventory / drift detection | MAXSTORE dashboards; SysAdminSuite estate packet | INFERRED | Tracker/estate seams exist; live fleet sync unproven | Estate packet + console export | Estate data access | Executive visibility | **Very high** | Privacy of inventory | ADAPT | B | P07 estate |
| H32 | Rollout rings / canary | Standard fleet practice + PAXSTORE groups | DOCUMENTED_UNVERIFIED | Not implemented for readers | Group assignment exists? | Change board | High risk control | Very high | Medium | ADAPT | B | Ops design |
| H33 | Ticket auto-enrichment | Device identity → health → ticket | INFERRED | H&H tracker exists; auto-enrich unbuilt | Define event schema only | ITSM owner | High Kurt value | High | PII | ADAPT | B | P04/P07 later |
| H34 | QR/on-device support workflow | Camera on A80; enterprise patterns | DOCUMENTED_UNVERIFIED | Camera may exist by SKU | Lab prototype only | PROVIDER_APPROVAL | Medium | Medium | Prod app install risk | ADAPT | C | Lab |
| H35 | Printer diagnostic receipt | A80 printer; CheckUp printer test | DOCUMENTED_UNVERIFIED | Unknown | Console/CheckUp printer test | Low | Medium onsite | Medium | Consumables | ADAPT | B/C | Support |
| H36 | Custom diagnostic Android app on prod | Android APK distribute | DOCUMENTED_UNVERIFIED | Inappropriate without provider | Reject prod unless approved | Provider + PCI | Speculative | — | **High** | REJECT | D | — |
| H37 | Enable USB debugging on production | Android Dev Options | DOCUMENTED_UNVERIFIED | Forbidden this sprint | Do not enable | Explicit security authority | Tempting but dangerous | Low | **PCI/security** | REJECT | D | — |
| H38 | TLS MITM of payment/management traffic | Generic network attack tooling | ABSENT (forbidden) | Forbidden | Never | None | None legitimate | — | Illegal/unsafe | REJECT | D | — |
| H39 | Broad inbound port rescan | Prior closed scans | ABSENT (closed) | Closed | Do not repeat | None | Low vs outbound | — | Noise | REJECT | D | — |
| H40 | Tracker/history as live firmware | Spreadsheet authority fallacy | OBSERVED_IMPLEMENTED (rejected by policy) | Explicitly forbidden | — | — | Misleading | — | Wrong baseline | REJECT | D | — |
| H41 | AxiaMed menu as capability discovery | Menu map closed | OBSERVED_IMPLEMENTED (closed) | Exhausted | — | — | Done | — | Time sink | REJECT | D | — |
| H42 | Lab A80 twin for automation research | Industry lab practice | INFERRED | No lab twin evidenced in repo | Acquire lab unit; ADB OK there | Hardware budget | Unlocks C-band safely | High future | Cost | ADOPT | C | Kurt procurement |
| H43 | Geolocation / geofence alerts | PAXSTORE marketplace claims | DOCUMENTED_UNVERIFIED | Unknown need | Console geolocation feature present? | Privacy/ops | Low for fixed kiosk | Low | Privacy | UNKNOWN | B | Ops |
| H44 | Remote file transfer via AirViewer | AirViewer file management claim | DOCUMENTED_UNVERIFIED | Unknown | File panel in session | Session + file policy | Medium | Medium | Data exfil risk | ADAPT | B | Security |
| H45 | Certificate / attestation inventory | Android keystore / enterprise | UNKNOWN | Unobserved | Console cert fields; avoid private key export | Security | Medium | Medium | High if misused | UNKNOWN | B | Security |
| H46 | Lock-task / kiosk mode detection | Android lock-task APIs | INFERRED | AxiaMed appears dedicated-app UX | dumpsys activity / policy | ADB/console | Explains UI constraints | Medium | Low | UNKNOWN | B | Introspection |
| H47 | Zero-touch / auto-init profiles | MAXSTORE auto initialization claims | DOCUMENTED_UNVERIFIED | Provisioned estate suggests some central init | Profile assignment visible in console | Estate admin | High redeploy speed | Very high | Medium | ADAPT | B | Estate |
| H48 | Single-click diagnostic bundle for tickets | Support engineering pattern | INFERRED | Not built | Compose from console exports + harness receipts | Ops | High Kurt | High | Redaction | ADAPT | B | P07 later |
| H49 | AirLauncher settings lockdown / kiosk keep-foreground | PAX AirLauncher VAS | DOCUMENTED_UNVERIFIED | Unknown licensed | Console shows AirLauncher / locked settings items | Premium/private MP | Medium (prevents local misconfig) | Medium | Changes device UX | ADAPT | B | Estate if licensed |
| H50 | PAXSTORE Terminal Center remote restart | Admin Guide RESTART + PUK | DOCUMENTED_UNVERIFIED | Unknown | Restart action present for SN | PUK/terminal-center rights | High MTTR | High | Service interruption | ADAPT | B | Authority gate |
| H51 | Firmware OTA with no-downgrade constraint | Admin Guide explicit | DOCUMENTED_UNVERIFIED | Unproven on estate | Push UI omits lower FW / rejects downgrade | Firmware authority | Core + **restore risk** | High | **High** — irreversible upgrade | ADAPT | B | Firmware program |

---

## Band ranking

### Band A — Proven / immediately read-only

1. Consume existing contracts/evidence (this frontier, protocol portfolio, menu map, PAXSTORE access discovery, live-execution boundary).
2. Private capture remains empty stub — firmware observation still the firmware critical path (parallel, not blocking P97).
3. Workstation ADB client absence recorded.
4. Closed-branch discipline (no menu/scan rediscovery).

### Band B — Authority-ready (highest Kurt leverage)

1. **Prove which control plane owns Kiosk4** (Experian/CC vs TMS vs PAXSTORE Admin vs hybrid) via authorized read-only console observation.
2. **Package/agent inventory** on that plane (reveals AirViewer/TMS/PAXSTORE agents).
3. **AirViewer or equivalent remote support** entitlement + trial view session on a non-disruptive window.
4. **Remote health**: online/offline, app/firmware inventory, network state, last-seen.
5. **Passive outbound fingerprint** correlated to console actions (no MITM).
6. **App/parameter/firmware lifecycle** inventory-before-mutate; keep mutation behind existing gates.

### Band C — Lab prototype

1. Lab A80 twin with authorized ADB + scrcpy for procedure development.
2. Sanitized bugreport/log redaction pipeline.
3. Optional QR/support-code workflows — provider approval before any prod install.

### Band D — Reject (with rationale)

| Item | Why rejected |
| --- | --- |
| Enable USB debugging on production | Security/PCI; authority-forbidden |
| TLS MITM / payment intercept | Forbidden / illegal / useless for authorized ops |
| Broad inbound rescans | Closed; low value vs outbound |
| Tracker-as-firmware | False authority |
| Custom unpaid/unapproved apps on prod readers | PCI + provider ownership |
| AxiaMed menu rediscovery | Exhausted |
| scrcpy on production without estate ADB | Would require forbidden enablement |

---

## Answers to required high-value questions (compressed)

1. **Android/build metadata without mutation:** Yes via Settings Software versions, authorized console, or ADB-if-present — currently **UNOBSERVED** on Kiosk4.
2. **Package info reveals management architecture:** Yes — **highest information-value discriminator** after control-plane login.
3. **PAX/Experian/acquirer agent on-device:** **UNKNOWN**; inferred likely; needs inventory.
4. **Device Owner / Admin:** **UNKNOWN**; do not assume Google AE.
5. **AirViewer requires:** PAXSTORE profile, Internet, AirViewer app, role permission, user approve (unless unattended).
6. **AirViewer provisioned?** **UNKNOWN** — Admin Center entitlement itself unproven.
7–18. **Console status/logs/remote-view/reboot/network/apps/firmware/app-push/params/message/completion/rollback:** All **DOCUMENTED_UNVERIFIED** for MAXSTORE/PAXSTORE generally; **UNPROVEN** for this estate until Admin/CC access.
19. **ADB seam present?** Workstation client **ABSENT**; device **UNKNOWN**. Do not enable.
20. **Vendor diagnostic plane equivalent:** AirViewer + CheckUp + estate consoles — preferred production path.
21–23. **Outbound connections / owners / passive metadata:** Architecture hypothesized; device-side **PAX Store Push Service Primary (443)** label is a retained correlation candidate only; Netstat/Connectivity closed (`REMOTE_ENDPOINT_CANDIDATE=NONE`); **no sanitized DNS/SNI/flow fingerprint** yet — next is passive SPAN correlation during console refresh, not another local scan.
24–26. **Fleet health / ticket enrichment / truck-roll reduction:** Technically yes **if** Band B access lands; AirViewer is the standout field-visit reducer.
27. **Lab twin:** Strongly recommended (**H42**).
28–29. **Inappropriate/custom prod apps / PCI rejects:** See Band D.
30. **Most exciting + realistic + valuable:** **Authorized remote support (AirViewer or PFCC equivalent) + package/firmware inventory on the true control plane**, unlocking remote diagnosis and eventually governed lifecycle — without waiting solely on the firmware label.

---

## Kurt lens (executable)

| Opportunity | What it lets us do | What we know today | Access/owner needed | Smallest safe proof | Why Kurt cares |
| --- | --- | --- | --- | --- | --- |
| Control-plane identity | Stop guessing Experian vs PAX vs TMS | Protocols modeled; live bind missing | Dennis/provider + CC/PAXSTORE admin | Read-only open same SN; screenshot sanitized fields | One escalation path |
| Package/agent inventory | See actual management stack | Not enumerated | Same | Export/app list | Ends architecture debates |
| AirViewer / remote assist | Fix without truck roll | Product exists; estate unknown | Premium/role + merchant approve | One view-only session | Minutes vs site visit |
| Remote health widgets | Triage before dispatch | Documented platform-wide | Console | Online + app status for Kiosk4 | Dispatch discipline |
| Passive outbound fingerprint | Prove who the device phones home to | Inferred only | Netops SPAN | DNS/SNI during console refresh | Escalation certainty |
| Lab twin | Safe ADB/scrcpy procedures | No twin | Procurement | Lab ADB getprop | Speed without prod risk |
| Firmware label (parallel) | Unlock baseline | Empty capture stub | Authorized observation | Fill labeled observation | Still required for mutate |

Qualitative savings only until measured: **MEASUREMENT_NEEDED** for technician-minutes.

---

## P82 admission — next experiment

**Selected thesis:** The provisioned Kiosk4 reader maintains a device-initiated management relationship whose **owner and agent** can be identified by combining (a) authorized console inventory and (b) passive outbound metadata — without firmware mutation.

**Falsifiable hypothesis:** Within one authorized read-only console session for the same Kiosk4 identity, either (i) an enrolled management record with app/firmware fields is visible, or (ii) no estate console shows the device — falsifying current “remote plane likely” operational assumption for that plane.

**Baseline:** Admin Center entitlement UNPROVEN; CC live bind unproven; capture empty; ADB unavailable here.

**Prototype boundary:** Read-only console observation + optional passive DNS/SNI metadata. No push, no ADB enable, no MITM.

**Measure:** Presence/absence of terminal record; fields available (apps, firmware, online, AirViewer); destination owners from metadata.

**Decision rule:**

- **PROMOTE** → P07 entitlement/runbook + remote-support trial design if record+fields found.
- **WEAKEN** → try next protocol in portfolio order.
- **REJECT** remote-plane thesis only if all preferred planes confirm non-enrollment (unlikely given provisioned reader).
- **INCONCLUSIVE** → access blocked; remain Band B blocked.

---

## Residual-compute sweep

Checked additional families: certificate lifecycle, geolocation, CloudMessage, RKI (noted as VAS, not pursued), file transfer, lock-task, zero-touch profiles, diagnostic bundles, printer self-test, QR workflows. Parallel Lane A completion added H49–H51 (AirLauncher, Terminal Center restart, FW no-downgrade) without changing Band A/B priority order.

Fixed point for **research**: evidence-typed frontier + successor map. Remaining uncertainty is **access-bound**, not imagination-bound.

## Proof ceiling

This artifact proves **research completeness and prioritization**. It does **not** prove AirViewer on Kiosk4, Device Owner state, live firmware, mutation authority, or production remote control.

## Related owners

- `harness/api/hh-cc-reader-firmware-protocols.v1.json`
- `harness/api/hh-cc-reader-live-execution-boundary.v1.json`
- `docs/HH_CC_READER_KIOSK4_MENU_CAPABILITY_MAP.md`
- `docs/HH_CC_READER_PAXSTORE_ACCESS_DISCOVERY.md`
- `docs/HH_CC_READER_NETSTAT_BASELINE.md` (Push Service Primary 443 correlation; closed discriminators)
- `docs/evidence/hh-cc-reader/kiosk4/2026-10-05/iteration-1-firmware-gate-checkpoint.md`
- Successor map: `docs/plans/hh-cc-kiosk4-p97-capability-successor-map-20261006.plan.md`
