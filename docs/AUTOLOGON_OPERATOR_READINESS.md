# AutoLogon operator readiness

## Purpose

This closes the controller-side handoff between an administrator-prepared sealed `C:\SASAL` runtime and a
different true standard-user operator session. It **does not deploy** AutoLogon, contact a target, weaken the
protected-network gate, or create a second deployment implementation.

The existing authorities remain unchanged:

- machine-wide universal entrypoint: `%ProgramData%\SysAdminSuite\bin\sas.cmd`;
- network-aware routing: `%ProgramData%\SysAdminSuite\bin\Invoke-SasNetworkAwareField.ps1`;
- sealed runtime authority: `C:\SASAL`;
- machine-portable manifest: `C:\SASAL\.git\sas-autologon-short-runtime.json`;
- full seal audit: `C:\SASAL\scripts\Test-SasAutoLogonRuntimeSeal.ps1`;
- AutoLogon Remote execution: the existing network-aware universal dispatcher and sealed crash-safe bootstrap.

## Administrator installation

First refresh/stage current SysAdminSuite on **Guest / Internet** using the repository-owned `sas refresh`
workflow. Then, from the refreshed `C:\SASAL` runtime, run the readiness installer from an elevated terminal:

```cmd
C:\SASAL\Install-AutoLogonOperatorReadiness.cmd
```

The installer requires the machine-wide ProgramData launcher and the runtime-local v2 manifest to already
exist. It adds the ProgramData bin to **Machine PATH** when necessary, grants BUILTIN\Users read/execute on
that installer-owned bin and on the sealed `C:\SASAL` runtime, installs the verifier, creates a Public Desktop
delegate named `SysAdminSuite - AutoLogon Remote.cmd`, and prepares the two deliberately writable evidence roots:

```text
C:\SASAL\runs
C:\Users\Public\Documents\SysAdminSuite
```

`C:\SASAL\runs` is already excluded by the repository `runs/` ignore rule and is the exact output root used by
`Invoke-SasAutoLogonOnsite.ps1`. Standard users receive Modify only on that generated evidence subtree; tracked
runtime content remains read/execute only. The Public Documents directory stores public-safe readiness receipts.
Those receipts are deliberately **non-authoritative** and are never a manifest, runtime, deployment, or
authorization source.

## True standard-user proof

Open a **new, non-elevated PowerShell session from an account that is not a member of the local
BUILTIN\Administrators group** and run:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File "$env:ProgramData\SysAdminSuite\bin\Test-SasAutoLogonOperatorReadiness.ps1" `
  -RequireStandardUser
```

A pass requires all of the following under that exact token/account:

1. the token is not elevated and the account is not a local Administrators member (UAC-filtered admin accounts are rejected);
2. Machine PATH contains the ProgramData SysAdminSuite bin;
3. `Get-Command sas.cmd` resolves to that ProgramData command in the new process;
4. the exact installed `sas.cmd platform` command executes successfully;
5. a create/write/read/delete probe succeeds in the ignored `C:\SASAL\runs` deployment evidence root;
6. the Public Desktop AutoLogon delegate is an exact SHA-256 match to the canonical ProgramData copy and retains the fixed network-aware `autologon Remote` routing contract;
7. the runtime-local manifest authority is readable and resolves without ambiguity;
8. the canonical full tracked-file seal audit returns `AUTOLOGON_RUNTIME_SEAL_VERIFIED`.

The final classification is:

```text
AUTOLOGON_OPERATOR_READINESS_VERIFIED
```

Public receipts:

```text
C:\Users\Public\Documents\SysAdminSuite\autologon-runtime-seal-verification.json
C:\Users\Public\Documents\SysAdminSuite\autologon-operator-readiness.json
```

Neither receipt is accepted by the deployment code as authority.

## Public Desktop deployment delegate

`scripts/SasAutoLogonPublicDesktop.cmd` is the tracked canonical template. The installer copies it unchanged to
ProgramData and to the Public Desktop as `SysAdminSuite - AutoLogon Remote.cmd`. The verifier requires an exact
SHA-256 match before readiness can pass. The delegate asks the operator for one authorized hostname/FQDN. The
target is held only in the process environment long enough to pass it as data to the installed
`Invoke-SasNetworkAwareField.ps1` entrypoint. The CMD does not store a target, collect credentials, bypass
confirmation, duplicate the AutoLogon transaction, or call the crash-safe engine directly.

The normal network canary, protected Northwell admission, sealed-runtime verification, recovery checks,
and crash-safe evidence chain still own the deployment attempt.

## Validation and proof ceiling

Repository/CI proves the static delegate boundary, Windows PowerShell 5.1 parsing, Machine PATH/ACL intent,
true-standard-user rejection contract, bounded run-root write-probe contract, receipt non-authority, canonical
resolver/auditor reuse, and whitespace cleanliness.

Only a live Admin Box run from a new true standard-user token can prove
`AUTOLOGON_OPERATOR_READINESS_VERIFIED` on that workstation. A readiness pass still does not prove target
reachability, AutoLogon mutation, restart, automatic sign-in, application behavior, or acceptance.
