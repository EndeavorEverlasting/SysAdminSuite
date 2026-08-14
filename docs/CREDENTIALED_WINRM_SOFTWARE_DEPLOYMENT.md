# Credentialed WinRM approved software deployment

## Purpose

Provide an admin-box transport for approved software when the operator can authenticate to the target with an authorized administrator account but the target should not be required to authenticate back to the software share.

The operator runs `Deploy-ApprovedSoftwareCredentialed.cmd TARGET_FQDN PACKAGE_ID` or calls `scripts/Invoke-SasCredentialedApprovedSoftwareInstall.ps1` directly. If no `PSCredential` is supplied, the PowerShell entrypoint calls `Get-Credential` once and holds the resulting credential in memory only.

## Security boundary

This lane does **not** disable or modify UAC/LUA. It does not write `EnableLUA`, `LocalAccountTokenFilterPolicy`, WSMan TrustedHosts, firewall policy, or WinRM configuration. If Windows authenticates the credential but returns a filtered/non-administrator remote token, the deployment fails closed.

The credential is never exported, serialized, converted to plaintext, embedded in a command line, written to JSON, or committed. Evidence records only that runtime credential mode was used.

## Transport model

1. Prove the existing protected-network gate.
2. Resolve every requested target to one canonical FQDN.
3. Require the existing operator-local host eligibility policy for each FQDN.
4. Load one package from `configs/software-packages/approved-apps.json`.
5. Require an explicit package-level credentialed WinRM opt-in.
6. Access the approved software source from the admin box.
7. Open an authenticated `New-PSSession -Credential ... -Authentication Negotiate` to the target.
8. Prove that the remote session holds an Administrator token.
9. Capture a bounded before snapshot.
10. Copy the installer with `Copy-Item -ToSession`; the target never authenticates to the source share.
11. Compare source and target SHA-256.
12. Execute the EXE or MSI in the authenticated administrator session.
13. Capture bounded after-state evidence.
14. Remove only `%ProgramData%\SysAdminSuite\CredentialedSoftwareInstall\<run_id>`.
15. Persist the result and event stream under `%LOCALAPPDATA%\SysAdminSuite\field-runs\credentialed-winrm`.

The stable pointer is `%LOCALAPPDATA%\SysAdminSuite\last-credentialed-winrm-run.json`, so a lost terminal is not a reason to blindly redeploy.

## Package promotion

Normal use requires `credentialed_winrm_install_enabled: true` in the approved catalog. A one-target experiment requires `credentialed_winrm_qualification_enabled: true` plus `-QualificationOnly`.

At introduction:

- `bca` is enabled for normal credentialed WinRM deployment because its MSI and unattended arguments are already cataloged.
- `autologon` is **qualification-only**. The earlier LocalSystem qualification remains failed and unchanged. The new lane tests the separate hypothesis that the installer requires an administrator user context.
- `allscripts-touchworks-22-1` remains blocked because vendor-validated live arguments are not yet cataloged.
- `epic-satellite` remains blocked because its installer filename is not pinned.

A credentialed AutoLogon qualification cannot promote itself. Promotion requires review of the result, post-restart technician acceptance, and a separate catalog change.

## AutoLogon privacy rule

For the Winlogon profile, the qualification snapshot may record `AutoAdminLogon` state and whether `DefaultUserName`, `DefaultDomainName`, and `DefaultPassword` value names exist. It never reads or records the `DefaultPassword` value.

## Operator commands

Normal approved package:

```powershell
.\Deploy-ApprovedSoftwareCredentialed.cmd wpj075opr046.nslijhs.net bca
```

AutoLogon qualification:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasCredentialedApprovedSoftwareInstall.ps1 `
  -ComputerName wpj075opr046.nslijhs.net `
  -PackageId autologon `
  -QualificationOnly `
  -ConfirmDeployment
```

The AutoLogon qualification completion classification is:

`CREDENTIALED_WINRM_QUALIFICATION_COMPLETED_REVIEW_REQUIRED`

That classification is intentionally not a production deployment-complete marker.
