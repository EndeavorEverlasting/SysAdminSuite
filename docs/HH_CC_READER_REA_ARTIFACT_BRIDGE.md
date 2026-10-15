# H&H CC Reader Suite — optional REA local-artifact bridge

**Owner:** SysAdminSuite, linked to [issue #545](https://github.com/EndeavorEverlasting/SysAdminSuite/issues/545). **State:** implementation with offline fixture tests; no live reader extraction, firmware file, or pilot certification implied.

## Why this exists

[REA (morluto/rea)](https://github.com/morluto/rea) contributes *two distinct lanes* that should not be conflated:

1. **Acquisition:** REA's `inspect-adb-client`, `list-adb-devices`, `inspect-adb-device`, `list-adb-packages`, `pull-adb-package` and `pull-adb-file` can inspect or export **only Android-visible, accessible files and APKs**, and only when an ADB transport is already qualified and authorized. It does not acquire protected OS/security partitions, unlock a device, or guarantee that firmware update packages are exportable. Generic AndroidProvider and the established H&H ADB control plane remain authoritative. Do not duplicate their enrollment.
2. **Offline analysis:** An independently sourced firmware image can be inspected with `rea inspect-firmware-regions`, and supported structures extracted with `rea extract-firmware`, under REA's [Linux x64 / Binwalk / Unblob limitations](https://github.com/morluto/rea/blob/main/docs/firmware-analysis.md). An acquired APK can be inspected with `rea inspect-android-package` with supported JADX/JDK prerequisites. REA is not installed by this adapter.

**Source branch remains critical:** legitimate artifact through H&H's existing Bank of America Payment Fusion / IngEstate or provider TMS/PSP catalog, supported vendor/distributor channel, or an *already accessible* authorized reader file export. Gordon's earlier update method is an internal source lead, not proof of any image. See #543. Do **not** repeat public PAXSTORE registration, disconnected Kiosk4 OTG steps, generic TCP port discovery, or sensitive-partition exploration.

## Existing floor to preserve

- Client target `2.0.15.260522` and accepted `2.0.14.221110` remain *unresolved version-domain strings* until labeled from the relevant app, package, firmware, OS or provider context.
- `harness/api/hh_cc_reader_firmware_source_portability.py` supplies artifact class and clone-exclusion assessment. This adapter consumes that established logic, not a new independent trust system.
- `harness/api/hh_cc_reader_version_domain.py` and `harness/api/hh_cc_reader_firmware_roundtrip.py` still own the subsequent domain/baseline/restore gates. An APK **does not** become firmware because REA can inspect it.
- Output always states `mutation_authorized=false`, `deployment_ready=false`, and `firmware_extracted_from_reader=false`. Even a successful REA result neither proves a vendor signature nor authorizes deployment.
- Do not check in private manifests, serials, IP/MAC/TID, artifacts, REA output or receipts. REA and extracted outputs must stay in private local directories. On Windows, an npm-provided `.cmd`/ `.bat` REA shim is not auto-executed by the Python bridge because shell-based private path forwarding has not been qualified; it emits `REA_SHELL_SHIM_NOT_QUALIFIED`. Local Windows APK analysis remains available once an independently verified direct executable/entrypoint is integrated.

## Operator artifact manifest (private, example)

```json
{
  "source_authority": "AUTHORIZED_VENDOR_OR_PROVIDER",
  "artifact_path": "C:\\PrivateArtifacts\\reviewed-firmware.zip",
  "expected_sha256": null,
  "artifact": {
    "artifact_class": "VENDOR_SIGNED_FULL_OTA",
    "name": "reviewed-firmware.zip",
    "source_control_plane": "authorized_vendor",
    "acquisition_method": "authorized_vendor_distribution",
    "vendor_signed": false,
    "included_state": []
  }
}
```

The values above are **illustrative, not a discovered H&H package or independently verified signature**. Use a vendor-supplied digest if available; a self-computed digest proves identity only. `source_authority` records an independently justified route. Recording the value is not permission to manufacture authority. For synthetic fixtures, use `SYNTHETIC_FIXTURE`. An APK descriptor must use `APK_OR_SPLIT_APK` and cannot be promoted to an OS image.

## Machine-neutral Windows launcher

```cmd
Evaluate-HHCCReaderReaArtifact.cmd "C:\\PrivateArtifacts\\candidate.json" plan
Evaluate-HHCCReaderReaArtifact.cmd "C:\\PrivateArtifacts\\candidate.json" inspect
```

The launcher stores a private local receipt under `%LOCALAPPDATA%\SysAdminSuite\cc-reader\rea\rea-TIMESTAMP-NONCE.json`. Each run retains a uniquely named receipt; invoked REA stdout/stderr evidence is captured alongside it in a private directory. It never contacts a CC reader. `inspect` explicitly invokes an already-installed `rea` executable only when the preflight is `ANALYSIS_READY_NOT_EXECUTED`; otherwise it returns the typed blocker. Firmware on Windows returns `FIRMWARE_ANALYSIS_REQUIRES_LINUX_X64` instead of trying unsupported native Windows Binwalk/Unblob. This does not require moving the production reader to Linux; only the *acquired artifact* is analyzed on a qualified Linux host.

On a qualified Linux x64 analysis environment, use the Python module against a private manifest, e.g. `python3 harness/api/hh_cc_reader_rea_bridge.py --input /private/candidate.json --output /private/receipts/receipt.json --invoke`. For an explicit offline extraction operation (writes local destination only), use `--invoke --extract-output /private/new-absent-output-dir`; REA's output directory must not already exist. Windows CMD offers the equivalent `extract` mode only when all host gates pass; real firmware extraction still routes to Linux x64.

**Dependency qualification:** REA's own installation is separate and needs Node.js/npm. For firmware, Binwalk 3.1.x and Unblob 26.6.x and their external extractor dependencies must be supplied and verified on Linux x64, with the required `prlimit`/process facilities. The adapter performs no `npm install`, privilege elevation, USB debugging, ADB install, network activity, source download, upload, partition read, firmware flash or terminal state mutation.

## Typed result contract

`ARTIFACT_NOT_ACQUIRED`, `SOURCE_AUTHORITY_REQUIRED`, `UNTRUSTED_ACQUISITION_REJECTED`, `SENSITIVE_OR_DEVICE_UNIQUE_ARTIFACT_REJECTED`, `NOT_A_LOCAL_ANALYZABLE_IMAGE`, `FIRMWARE_ANALYSIS_REQUIRES_LINUX_X64`, `INVALID_ARTIFACT_PATH`, `UNSUPPORTED_INPUT_SIZE`, `SOURCE_DIGEST_MISMATCH`, `ANALYSIS_READY_NOT_EXECUTED`, `REA_NOT_INSTALLED_OR_NOT_ON_PATH`, `REA_FINISHED_ANALYSIS_UNVERIFIED`, or a bounded execution failure. These describe artifact analysis only, **not** device firmware retrieval or release qualification.

## Acceptance

Run `python Tests/survey/test_hh_cc_reader_rea_bridge_contracts.py` plus the existing source-portability, version-domain, firmware-roundtrip, AndroidProvider and ADB control-plane tests. Then execute an actual REA run on a *synthetic/public fixture* on a qualified host and retain raw REA evidence privately. A firmware model/target signature and source-build match must be independently validated prior to pilot admission. Close the parent issue **only** after the actual reader update pilot and independently accepted before/after proof, not on this bridge merge.
