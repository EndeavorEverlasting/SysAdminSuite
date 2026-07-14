# AutoLogon session access proof

## Purpose

ACL inspection from an administrative session is useful evidence, but it does not prove what the
AutoLogon account can actually do after Windows signs it in. Group expansion, explicit deny rules,
share permissions, network timing, profile loading, and authentication can all change the result.

This runtime proof must therefore run **inside the real AutoLogon desktop session** after reboot:

```text
AutoLogon account signs in
  -> verify current identity matches the expected hostname account
  -> open each explicit local, mapped-drive, or UNC directory
  -> optionally create one unique zero-byte marker
  -> immediately remove the marker
  -> report one session-level decision
```

Entrypoint:

```text
scripts\Invoke-SasAutoLogonSessionAccessProof.ps1
```

## What this proves

A successful live run with `-AllowWriteProbe` proves that the current AutoLogon user token could:

- resolve and open each explicit directory;
- authenticate to each explicit UNC share or mapped-drive destination;
- create a new file in each tested directory;
- remove the exact marker it created.

The proof covers both share and NTFS enforcement because the operation is performed by the real
signed-in account rather than an administrator inspecting ACL metadata.

It does not prove that every application workflow succeeds. Applications may require a particular
subdirectory, file extension, lock behavior, database, service, or launch sequence. Test the exact
application working directory when that path is known.

## Safety boundaries

- Run interactively in the real AutoLogon session. Do not use `runas`, alternate credentials,
  PowerShell remoting, a scheduled task, or an administrative service account.
- The current identity is checked before any path is contacted.
- Supply no more than 12 explicit paths per run.
- Paths must be drive-rooted or complete UNC share paths.
- Wildcards, relative paths, and `..` traversal are rejected.
- Directory entry names and file contents are never returned.
- Write testing requires the explicit `-AllowWriteProbe` switch and PowerShell confirmation.
- The marker uses `FileMode.CreateNew`, so it cannot overwrite an existing file.
- The marker name is unique and begins with `.sas-autologon-access-`.
- The marker is removed immediately after creation.
- No ACLs, ownership, registry values, credentials, event logs, services, tasks, or persistence are
  changed.
- The script returns an object to the pipeline; it does not leave a SysAdminSuite report on the
  workstation.

## Pilot command

After the workstation reboots and the expected AutoLogon account visibly signs in, open PowerShell
inside that session and run the script from the approved read-only tooling share or a previously
approved local copy.

Replace the example paths with the exact application and file-share roundabouts used by the site:

```powershell
$result = & '\\approved-server\approved-tools\scripts\Invoke-SasAutoLogonSessionAccessProof.ps1' `
  -Path @(
    'C:\ProgramData\VendorApp',
    'Z:\OperationalData',
    '\\approved-fileserver\approved-share\OperationalData'
  ) `
  -RetryCount 3 `
  -RetryDelaySeconds 5 `
  -AllowWriteProbe `
  -Enforce `
  -Confirm:$false

$result | ConvertTo-Json -Depth 12
```

The default expected user is the workstation hostname. Use `-ExpectedUserName` only when the
approved AutoLogon account naming contract differs:

```powershell
-ExpectedUserName 'APP-AUTOLOGON-01'
```

Do not pass a password. The script has no credential parameter.

## Network timing

Mapped drives and UNC shares may not be ready immediately after logon. The proof supports a bounded
retry window:

- `RetryCount`: 0 through 5 retries;
- `RetryDelaySeconds`: 1 through 30 seconds;
- no continuous monitoring or background retry process.

A delayed success is still reported with the number of attempts. A failure after the bounded retry
window remains a pilot blocker rather than triggering an uncontrolled loop.

## Decisions

| Decision | Meaning |
|---|---|
| `SESSION_ACCESS_CONFIRMED` | Identity matched and every explicit path passed the required open/write/cleanup checks. |
| `SESSION_ACCESS_PARTIAL` | Identity matched and at least one path passed, but another path failed. |
| `SESSION_ACCESS_FAILED` | Identity matched, but no path met the required access contract. |
| `IDENTITY_MISMATCH` | The current session was not the expected AutoLogon account, so path tests were skipped. |

A fixture run returns `SESSION_ACCESS_CONFIRMED` only as offline contract proof and records
`runtime_proof: false`.

## Evidence fields

The returned summary includes:

```text
actual_identity
expected_user_name
identity_match
runtime_proof
decision
path_count
confirmed_path_count
failed_path_count
write_probe_authorized
path_contents_recorded: false
credentials_collected: false
impersonation_used: false
persistence_created: false
```

Each path result records the path, path kind, attempt count, directory-open result, write result,
cleanup result, status, and sanitized error category. It does not include directory listings or file
contents.

## Acceptance gate

Do not expand beyond the pilot until each test workstation has:

1. a successful AutoLogon state transition;
2. a real reboot and visible sign-in by the expected account;
3. `SESSION_ACCESS_CONFIRMED` for every required local application directory;
4. `SESSION_ACCESS_CONFIRMED` for every required mapped drive or UNC roundabout;
5. real application read/write/save behavior in its working location;
6. no leftover `.sas-autologon-access-*.tmp` marker;
7. clean SysAdminSuite deployment staging.

The session proof closes the current-token and share-authentication gap. It complements rather than
replaces the administrative ACL/profile/redirection posture report.

## Offline fixture

```powershell
$result = .\scripts\Invoke-SasAutoLogonSessionAccessProof.ps1 `
  -ExpectedUserName SAMPLE001 `
  -Path @('C:\ProgramData\VendorApp', '\\fileserver\roundabout') `
  -AllowWriteProbe `
  -FixtureMode `
  -Confirm:$false

$result | ConvertTo-Json -Depth 12
```

Expected fixture posture:

```text
decision: SESSION_ACCESS_CONFIRMED
runtime_proof: false
path_contents_recorded: false
credentials_collected: false
impersonation_used: false
```
