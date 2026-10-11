# Preserved Android developer toolchain

## Admin Box 1 cold-start — mandatory successor implementation (2026-10-10)

Admin Box 1 is the intended OpenCode coordinating laptop and **has not had the Android SDK or Google Android CLI bootstrap performed on PTop**. Do not presume PTop installation results apply to Admin Box 1. The shared `Invoke-SasAndroidToolchain.ps1` lifecycle is now role-factored: `Manage-AndroidToolchain.cmd` remains the preserved `ptop_lab` front door, and `Manage-AdminBoxAndroidToolchain.cmd` is the tracked Admin Box 1 front door that forces `adminbox_reference` through `scripts/Start-SasAdminBoxAndroidToolchain.ps1` and the sanitized `Config/android-adminbox-toolchain-profile.json` desired state. Calling either front door with a spoofed role, overriding the Admin Box role, or bypassing `Assert-PTopProfile` / `Assert-HostProfileForRole` remains forbidden.

**First read/execute** `docs/handoff/android-adminbox1-bootstrap-opencode-20261010.md` and `docs/plans/android-adminbox1-coldstart-bootstrap-p04-20261010.plan.md`. They task OpenCode on actual approved Admin Box 1 with implementing a **profile-aware reuse of this same engine**, adding a tracked Admin Box-specific developer front door, sanctioned official package acquisition (Android CLI, Studio, JDK, Android SDK and scoped optional components), private host authorization and license/elevation barriers, idempotent Inventory/Plan/Apply/Verify/Repair, fresh CMD/PowerShell executable resolution and actual Kotlin debug APK/emulator proof when feasible. The B1-CONTRACT implementation of that role factoring, sanitized Admin Box desired-state profile and tracked front door has landed and is guarded by `Tests/survey/test_android_adminbox_toolchain_profile_contracts.py`; actual Admin Box package installation and fresh-shell runtime proof remain separate authorized execution work. Preserve PTop-specific role/source/security/tests. The P04 dependency contract is guarded by `Tests/survey/test_android_adminbox_coldstart_dispatch_contracts.py` and Android Toolchain CI. **Planning and static CI alone do not install anything.**

The developer `platform-tools/adb.exe` produced by SDK bootstrap never qualifies for `Run-SasAndroidProvider.cmd`. That provider continues to require a separate official archive with an independently approved SHA-256 and a selected `--expected-commit` for sealed/offline execution. If site policies prohibit acquiring tools, emit a typed authorized acquisition/staging gate, not an arbitrary manual download procedure or safety bypass.


`Manage-AndroidToolchain.cmd` and `Manage-AdminBoxAndroidToolchain.cmd` both delegate to
`scripts/Invoke-SasAndroidToolchain.ps1` for Inventory, Plan, Apply, Verify and
Repair under their declared node role. This workflow owns the authorized
developer toolchain for the preserved PTop role and the Admin Box 1 reference
role only. It does not change the AndroidProvider role model or provision
another workstation.

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

Apply acquires missing Studio, Android CLI and independent JDK through exact
vendor WinGet identities, without license-acceptance switches. Existing executable
paths take precedence over package-manager metadata and are preserved.
The synthetic suite directly exercises prerequisite, role, SDK coherence, disk,
and fixture mutation gates. Other failure fixtures exercise propagation of
supplied synthetic observations, not actual network, installer, license prompt,
GUI, device or emulator failures. These limits must remain visible in closeout.

SAS readiness remains owned by `Run-SasAndroidProvider.cmd` and its declared
node-role contract. The toolchain engine routes provider verification with the
requested role and never spoofs `ptop_lab` from an Admin Box run. Studio SDK ADB
is never a SAS fallback. A complete official
Windows Platform-Tools archive requires an independently approved SHA-256;
hashing a newly downloaded file does not approve it. Without that authority,
report `QUALIFICATION_AUTHORITY_REQUIRED`. Emulator visibility is not physical
device or production reader proof. Device scans, firmware writes, debugging
enablement and network ADB transitions are outside this toolchain workflow.

Run `python Tests/survey/test_android_toolchain_contracts.py` for the synthetic
contract gate and `python harness/validators/validate-harness-registries.py` for
registration integrity. Actual installation and runtime proof require the
authorized Windows host and private receipts from the engine.

The launcher resolves the canonical checkout through the repository path authority.
Apply requires `-MutationAuthorized`; Verify can request `-LaunchStudio`,
`-BuildSmoke`, and `-BootEmulator`. `-JavaHome` selects an independently installed
JDK explicitly. User environment changes are backed up before additive updates;
machine PATH may still take precedence in a new terminal and must be measured.
Apply and Repair also require a private resolved host authority at
`%LOCALAPPDATA%/SysAdminSuite/android-toolchain/host-profile.json` (or `-HostProfile`).
It binds the approved node role, manufacturer/model, allowed operation and
operator evidence reference. A caller-selected role alone never admits mutation.
The `ptop_lab` role fails closed with the preserved `PTOP_*` authority codes; the
`adminbox_reference` role fails closed with `ADMINBOX_PROFILE_AUTHORITY_REQUIRED`,
`ADMINBOX_PROFILE_AUTHORITY_INVALID` or `ADMINBOX_EQUIPMENT_PROFILE_MISMATCH`, and
its private authority may only narrow the sanitized operation ceiling declared in
`Config/android-adminbox-toolchain-profile.json`.
Every non-fixture operation uses canonical source admission; a freshness update
restarts the engine before further execution. Existing Studio sessions are reused
to preserve user work rather than opening duplicate instances.

`-TcpPipeFallback` scopes a JDK Unix-domain temporary-path override to the smoke
build, selecting the JDK's built-in TCP pipe fallback when Windows Unix sockets
fail. It never changes global JVM, firewall, or security configuration. The receipt
records that compatibility workaround. Studio process observation alone is
`GUI_PROCESS_OBSERVED`, not complete visual interaction proof.

Emulator verification uses only the selected AVD, a separate loopback ADB server,
disabled USB and mDNS discovery, and exact emulator cleanup. SDK ADB in this lane
is emulator development proof only, never SAS qualification or physical-device
authority. SAS preparation remains blocked until independent qualification
authority supplies the approved archive digest.

Native execution is owned by `Invoke-SasNativeProcess` in
`scripts/SasBoundedNative.psm1`; the Android adapter owns log files, failure
classification and validated CMD composition. Stdout and stderr remain separate,
including empty stdout and stderr-only success. Timeout and incomplete stream
drain fail closed. Sealed runtimes must seal this module alongside the engine.
S4U reconciliation and independent ADB source qualification remain separate.

Streams spool incrementally to adapter-owned log files while commands run.
Returned text is bounded to 1048576 characters per stream; truncated capture
fails closed as SUBPROCESS_CAPTURE_LIMIT, with full file evidence retained.
This preserves partial diagnostics during interruption without retaining
unlimited stdout/stderr strings in memory.
