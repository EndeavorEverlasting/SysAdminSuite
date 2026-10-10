# Preserved Android developer toolchain

`Manage-AndroidToolchain.cmd` delegates to `scripts/Invoke-SasAndroidToolchain.ps1`
for Inventory, Plan, Apply, Verify and Repair. This workflow owns the authorized
PTop developer toolchain only. It does not change the AndroidProvider role model
or provision another workstation.

Inventory and Plan inspect the existing Studio, Google Android CLI, SDK,
standalone JDK, native packages and AVDs. Apply and Repair require explicit
mutation authorization. Existing working installations and AVD data are
preserved; missing SDK packages use the official Android CLI. The repository
fetcher is the existing authority for separately staged archives. A project wrapper supplies Gradle rather than requiring
a global Gradle installation.

First-party license acceptance, administrator approval and physical hardware
remain separate operator gates. Authorization to install software does not
accept a license. An interrupted acquisition or failed package installation
must emit a failed or actionable receipt and be inspected before retrying.

Runtime receipts belong in ignored `survey/output/android-toolchain/` directories. They
record local paths and observed host facts and must never enter Git. Synthetic
fixtures contain no host identifiers, user directories, serials or credentials.

Package presence proves installation only. CLI invocation, Studio launch,
Kotlin APK production and emulator boot are separate capabilities. Build proof
requires a successful compatible Gradle Wrapper build and an actual APK;
emulator proof requires bounded boot observation and exact emulator identity.
Fixture execution and CI cannot establish those PTop runtime claims.

The initial engine fails closed when Studio, the Android CLI or an independent
JDK is missing; it does not yet acquire those prerequisite applications itself.
The synthetic suite directly exercises prerequisite, role, SDK coherence, disk,
and fixture mutation gates. Other failure fixtures exercise propagation of
supplied synthetic observations, not actual network, installer, license prompt,
GUI, device or emulator failures. These limits must remain visible in closeout.

SAS readiness remains owned by `Run-SasAndroidProvider.cmd` and its existing
`ptop_lab` contract. Studio SDK ADB is never a SAS fallback. A complete official
Windows Platform-Tools archive requires an independently approved SHA-256;
hashing a newly downloaded file does not approve it. Without that authority,
report `QUALIFICATION_AUTHORITY_REQUIRED`. Emulator visibility is not physical
device or production reader proof. Device scans, firmware writes, debugging
enablement and network ADB transitions are outside this toolchain workflow.

Run `python Tests/survey/test_android_toolchain_contracts.py` for the synthetic
contract gate and `python harness/validators/validate-harness-registries.py` for
registration integrity. Actual installation and runtime proof require the
authorized Windows host and private receipts from the engine.
