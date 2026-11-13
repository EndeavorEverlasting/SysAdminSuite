# PAX A80 — read-only local version discovery (H&H Kiosk4)

**Owned goal:** capture a real installed software/OS/firmware version *and its exact screen label* from the same H&H PAX A80; bind it to the existing private reader identity and source evidence. **Not:** extract protected firmware, perform an update, circumvent PIN/merchant protections, or make the accepted campaign target into an observed value.

**State at publication:** source-backed candidate paths and offline classifiers. No live Kiosk4 firmware-version reading was observed in this change. Current `BASELINE_LOCKED` remains `BLOCKED_EVIDENCE` until the correct independent gate passes.

## What is actually established

- Kiosk4's earlier wired keyboard accepted alphanumeric text in certain diagnostic fields but not the numeric-only second Settings credential prompt. See `HH_CC_READER_KIOSK4_MENU_CAPABILITY_MAP.md`. This is a specific field/UI capability finding; repeating FUNC, HID, password guesses or the whole menu crawl without a new discriminator is forbidden.
- Earlier micro-USB/OTG on Admin Box enumerated **no Android/ADB/MTP/PTP client** even when cable seating was operator-confirmed. Existing `hh_cc_reader_adb_control_plane.py` classifies that configuration as an exhausted ADB route. Repeated cable reseating is not a new experiment.
- Upstream `morluto/rea` can analyze *accessible* APKs or already acquired firmware images; it cannot make a USB device enumerate or read protected firmware merely by being installed.
- Existing `Classify-HHCCReaderVersionDomain.cmd`, `Evaluate-HHCCReaderFirmwareRoundtrip.cmd baseline`, private Kiosk4 capture template, and `Capture-HHCCReaderAdbInventory.cmd` remain authoritative. Do not build another data/identity master.

## New source-backed, *conditional* local paths

| Candidate and evidence source | Exact read-only action if available | What it actually measures | Stop condition |
| --- | --- | --- | --- |
| **PAX service diagnostics** — [PAX technical guide, PaxSPManager](https://pax-us.atlassian.net/wiki/spaces/PAXTKB/pages/4431413372/How%2Bto%2Baccess%2BPaxSPManager%2Bto%2Bconfirm%2BA80%2Bprinter%2Bissue) | On an authorized test reader *where Calculator is already accessible and service diagnostics are permitted*: Calculator → documented diagnostic access → `SP Terminal Info` → `PosPrnInfo` → `PRT_FIRM`. Capture the exact field/value privately | **Printer-controller firmware**, *not* the main PayDroid build nor H&H payment application release | Calculator/service app unavailable or diagnostic permission absent -> `LOCAL_SERVICE_DIAGNOSTIC_UNAVAILABLE`; do not side-load, guess access codes or change settings |
| **Android Settings / About device** — [Android Help](https://support.google.com/android/answer/7680439) | If Settings/About is **already authorized and accessible**, capture **Build number**, Android version and any `Software version` field, with exact heading | PayDroid-formatted build string can identify the **OS/build family**; not a substitute for an independently labeled installed firmware / campaign app version | Known numeric-only second Settings credential path unchanged -> `SETTINGS_GATE_PREVIOUSLY_CLOSED`; do not retry the same credential/input experiment |
| **Processor payment-app About** — [Viva A80 app instructions](https://ukhelp.viva.com/en/articles/10006070-how-do-i-update-pax-paydroid-terminals-a50-a77-a80-a910-a920-a920pro) and [Planet A80 guide](https://www.weareplanet.com/sites/default/files/Customer%20Resources/HTML/A80%20Setup%20and%20User%20Guide_0.html) | If *this installed app* exposes `System > About` or `Config > Info`, read its exact `Version`, `App version`, `FW PACKAGE`, and headings without selecting Update | Application/provider package info; these **other providers' example menus are not asserted to exist in H&H's AxiaMed installation** | No corresponding visible menu -> `APP_ABOUT_NOT_EXPOSED`; do not recreate a broad AxiaMed menu crawl |
| **Authorized management-plane read** — existing [PR #561](https://github.com/EndeavorEverlasting/SysAdminSuite/pull/561) and [PAXSTORE terminal API](https://github.com/PAXSTORE/paxstore-openapi-java-sdk/blob/master/docs/TERMINAL_API.md) | If a legitimate entitled H&H provider/PAXSTORE/Control Center integration is *already* accessible, use existing read-only installed-firmware + installed-app + Android-version API/UI observation | Provider-advertised installed firmware and app metadata, subject to response currency and same identity | Absent entitlement/data -> exact `AUTHORIZED_SOURCE_UNAVAILABLE`; no repeat of exhausted public PAXSTORE reseller registration |
| **PC-connected client** — existing `Probe-HHCCReaderAdb.cmd` and `Capture-HHCCReaderAdbInventory.cmd` | **Only with a materially new USB-client/ADB enumeration discriminator** (different authorized device mode/interface/hardware evidence), use approved host tooling for a read-only `getprop` inventory | `ro.build.display.id`, `ro.build.version.incremental`, PAX properties; *not* automatic firmware image extraction | Same `USB_DEVICE_NOT_ENUMERATED` as the exhausted configuration -> stop, do not reseat or enable Developer Options / debugging |

PAX's `PRT_FIRM` documentation shows that a local service-information surface exists on supported builds, **not** that the H&H Kiosk4 image exposes the Calculator/service route or that `PRT_FIRM` means the reader's main OS firmware. The vendor-specific Planet/Viva screen names and menu entry points are analogous evidence only; no cross-processor configuration is presumed.

## Local read-only capture and classification, without touching a reader

Use the existing private evidence template `docs/examples/hh-cc-reader-kiosk4-version-evidence-capture.template.json`. On the authorized host, save a completed private copy outside Git and record these required fields:

- `source_surface`: `pax_sp_manager_readonly`, `android_about_device_readonly`, `payment_app_about_readonly` or an existing recognized management/ADB value; never invent a source that was not observed.
- `observed_at`: actual timestamp; `device_identity`/identity binding: privately bound **same A80**, not a typed guess or unrelated terminal.
- `navigation_path`, `labeled_observations[].section`, `field_heading`, `value`: copied **exactly**, preferably from a timestamped private screenshot or still; `evidence_reference` points to the private record.
- Preserve firmware, OS build, printer-controller, payment-app and package versions as separate observations. **Do not backfill the missing main-firmware field from a peripheral version or the planned campaign target `2.0.15.260522`.**

The existing machine-neutral CMD runner classifies the private capture:

```cmd
Classify-HHCCReaderVersionDomain.cmd --input "PRIVATE_CAPTURE.json" --output "PRIVATE_RECEIPT.json"
```

`harness/api/hh_cc_reader_version_domain.py` now recognizes *properly labeled* `PaxSPManager > SP Terminal Info > PosPrnInfo / PRT_FIRM` as `printer_controller_firmware` and `Settings > About device / Build number` containing a PayDroid-format build as `paydroid_os_build`. **Both are real version observations when seen, but neither independently satisfies `CURRENT_FIRMWARE_BOUND` or `BASELINE_LOCKED`.** Unlabeled, unrelated-model, stale and generic `Version` values remain fail-closed. The existing roundtrip mechanism remains the only baseline owner.

## Next operator-owned physical gate

**Do one new discriminating observation**, not an open-ended expedition: check whether Calculator/PAXSPManager is present under the site's permitted read-only support procedures, and if it is, photograph the `SP Terminal Info` and labeled version fields. If unavailable, record that typed fact once and continue the *already in-flight* authorized provider path in PR #561; attempt direct PC ADB only if genuinely new USB-client enumeration evidence exists. Stop at any access/approval prompt rather than bypassing it.

If the vendor support diagnostic shows only printer firmware, treat that as valuable component inventory but explicitly **not** a solved main-firmware gate. No test transaction, password guessing, debug enable, firmware push, bootloader operation, network scan, service-mode mutation or payment-data capture is required for this discovery.
