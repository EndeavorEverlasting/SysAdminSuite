# Credentialed WinRM approved software deployment

## Purpose

Credentialed WinRM is an **additional** SysAdminSuite software transport for cases where an authorized administrator can authenticate from the admin box and the target should not need to authenticate back to the software share.

It does not replace:

- current-token WinRM in `Invoke-SasSoftwareInstall.ps1`;
- `Auto`, `WinRM`, or `SmbScheduledTask` selection in `Invoke-SasValidatedSoftwareDeployment.ps1`;
- AutoLogon `Remote`, `Recover`, Kerberos S4U, restart-observation, or crash-safe field deployment;
- Cybernet profiled clinical-core deployment.

One transport is selected **before mutation**. A failed lane leaves evidence. A later run may explicitly choose another lane, but credentialed WinRM never silently falls through to another transport after target mutation.

## Security and trust boundary

The credential is a runtime-only `PSCredential` acquired by `Get-Credential` unless one is supplied in memory by an authorized caller. It is never exported, serialized, converted to plaintext, embedded in a command line, or written to evidence.

This lane never modifies `EnableLUA`, UAC policy, `LocalAccountTokenFilterPolicy`, WinRM configuration, TrustedHosts, firewall policy, or other target security settings merely to obtain an administrator token. If authentication succeeds but the WinRM token is not an Administrator token, the run fails closed.

A pinned installer **filename is not enough**. Before any target PSSession is opened, the selected package must have an independently reviewed `credentialed_winrm_expected_sha256` in `configs/software-packages/approved-apps.json`. The admin box hashes the source bytes and refuses the run if that digest does not equal the catalog pin. After copy-through-session, the target file must equal the same independent pin.

Installer arguments are also closed: caller-supplied `-InstallerArguments` are accepted only when they exactly equal the catalog list, in order. They cannot override package policy. AutoLogon retains its approved-empty argument contract.

## Transport model

1. Prove protected Northwell network posture.
2. Resolve each requested target to one canonical FQDN.
3. Require the operator-local host eligibility policy for each FQDN.
4. Load one approved package from `configs/software-packages/approved-apps.json`.
5. Require explicit credentialed-WinRM package promotion or qualification opt-in.
6. For AutoLogon qualification, require `-EquipmentProfile Cybernet` and validate `Config/cybernet-client-preferences.json` as the profile authority.
7. Resolve the approved software source on the admin box.
8. Require and verify the independently pinned source SHA-256.
9. Require exact catalog installer arguments.
10. Acquire one runtime-only credential.
11. Open `New-PSSession -Credential ... -Authentication Negotiate`.
12. Prove an Administrator remote token.
13. Capture before-state evidence.
14. Create only the run-scoped target staging directory and immediately record the mutation boundary.
15. Copy the installer through the authenticated PSSession; the target never authenticates to the source share.
16. Verify the staged file against the same independent SHA-256 pin.
17. Execute the approved MSI/EXE and capture exit/reboot evidence.
18. Capture after-state evidence.
19. Remove only the exact run-scoped staging directory.
20. Fail with `CREDENTIALED_WINRM_CLEANUP_REQUIRED` if cleanup is unproven.
21. If an earlier target completed and a later target fails, emit `CREDENTIALED_WINRM_PARTIAL_COMPLETION_REVIEW_REQUIRED` instead of hiding the partial mutation behind a generic failure.
22. Persist result/event evidence under `%LOCALAPPDATA%\SysAdminSuite\field-runs\credentialed-winrm`.

The stable pointer is `%LOCALAPPDATA%\SysAdminSuite\last-credentialed-winrm-run.json`.

## Package promotion state

The transport is implemented, but **no package is automatically trusted merely because this code exists**.

At this revision:

- `bca`: cataloged filename and unattended arguments exist, but credentialed WinRM remains disabled until an independently reviewed MSI SHA-256 is committed and the package opt-in is promoted.
- `autologon`: retained as a separate administrator-user-context qualification hypothesis, but qualification remains disabled until an independent SHA-256 is committed and the qualification opt-in is promoted. It additionally requires the explicit Cybernet equipment profile.
- `allscripts-touchworks-22-1`: blocked by missing approved live arguments and SHA-256 pin.
- `epic-satellite`: blocked by missing installer filename and SHA-256 pin.

This intentionally separates **transport capability** from **package promotion**.

## AutoLogon profile and privacy rules

AutoLogon is forbidden on shared/user-login workstation profiles. The credentialed qualification lane therefore requires `-EquipmentProfile Cybernet` and validates the tracked Cybernet profile authority before it can proceed.

For Winlogon evidence, the lane may record `AutoAdminLogon` state and whether `DefaultUserName`, `DefaultDomainName`, and `DefaultPassword` value names exist. It never reads or records the `DefaultPassword` value.

A successful qualification cannot promote itself. Promotion still requires review of the run evidence, package/hash approval, technician post-restart acceptance, and a separate catalog change.

## Operator front door

Use synthetic examples in tracked documentation; live target identifiers belong only in operator/runtime input.

Normal package mode:

```cmd
Deploy-ApprovedSoftwareCredentialed.cmd authorized-cybernet.example.invalid bca
```

AutoLogon qualification mode:

```cmd
Deploy-ApprovedSoftwareCredentialed.cmd authorized-cybernet.example.invalid autologon QUALIFY
```

`QUALIFY` adds the explicit qualification switch and Cybernet equipment-profile selection. Both examples will still fail closed before target contact until the chosen package has an approved SHA-256 pin and transport opt-in in the catalog.

## Terminal classifications

- `CREDENTIALED_WINRM_DEPLOYMENT_COMPLETED`
- `CREDENTIALED_WINRM_QUALIFICATION_COMPLETED_REVIEW_REQUIRED`
- `CREDENTIALED_WINRM_PARTIAL_COMPLETION_REVIEW_REQUIRED`
- `CREDENTIALED_WINRM_CLEANUP_REQUIRED`
- `CREDENTIALED_WINRM_DEPLOYMENT_FAILED`

A cleanup-required or partial-completion result is not permission to blindly retry or switch transports. Inspect the durable result and explicitly select remaining work.
