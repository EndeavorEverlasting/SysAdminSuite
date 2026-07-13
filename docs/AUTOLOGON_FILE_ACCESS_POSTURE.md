# AutoLogon file-access posture

## Purpose

AutoLogon changes the interactive user context. A workstation may show correct AutoLogon registry
state while the resulting account still cannot use a required local application directory, profile
folder, or working path.

This companion evidence lane records:

- bounded NTFS ACL signals for common and operator-supplied target-local directories;
- the expected AutoLogon account and Windows profile path;
- loaded shell-folder redirection metadata;
- mapped-drive registry metadata;
- before/after changes and review decisions.

Entrypoint:

```text
scripts\Invoke-SasAutoLogonFileAccessPosture.ps1
```

The collector complements:

```text
scripts\Invoke-SasAutoLogonStateDelta.ps1
scripts\Invoke-SasAutoLogonDeployment.ps1
```

It does not install software or change permissions.

## What it answers

The output helps operators answer:

```text
Does the expected AutoLogon account have direct or broad ACL grant signals on the local
directories we care about, is there an explicit deny or missing path to review, and are
user folders or drive letters redirected toward a file share?
```

The answer is a posture signal, not a full Windows authorization calculation.

## Safety and interpretation boundaries

The collector:

- reads ACL metadata with `Get-Acl`;
- inspects only explicit targets;
- caps a run at 25 workstations;
- caps operator-supplied local paths at 12;
- rejects UNC paths, wildcards, relative paths, and parent traversal in `-PermissionPath`;
- records user-shell-folder and mapped-drive registry values without contacting those shares;
- does not enumerate directory contents;
- does not read files;
- does not impersonate the AutoLogon user;
- does not calculate group-expanded or token-based effective access;
- does not modify ACLs, ownership, registry values, profiles, shares, or drive mappings;
- writes SysAdminSuite evidence only on the admin workstation.

Therefore, an ACL allow signal does not prove effective access. A real AutoLogon session remains
required to verify that the account can open, create, modify, and save where the application needs
to work.

## Default local paths

Each target automatically checks:

| Path | Purpose |
|---|---|
| `C:\Users\Public` | Common user-facing local exchange path |
| `C:\ProgramData` | Shared application-data read posture |
| `C:\Temp` | Common local temporary-work path when present |
| expected profile path | The profile matching the configured or hostname-derived AutoLogon account |

The actual system drive and ProgramData values are resolved on each workstation.

Use `-PermissionPath` for local application directories that matter to the deployment:

```powershell
-PermissionPath @(
  'C:\ProgramData\VendorApp',
  'C:\Northwell',
  'D:\LocalExchange'
)
```

Do not pass a file share to `-PermissionPath`. UNC paths are captured only when they already appear
in loaded shell-folder redirection or mapped-drive metadata.

## ACL signals

For each local directory, the snapshot records:

- path source and intended capability signal;
- existence;
- owner;
- whether inheritance is protected;
- relevant direct or broad ACL rules;
- expected-account rule count;
- read allow signal;
- write allow signal;
- deny signal;
- posture;
- review requirement.

Relevant identities are limited to the expected account and broad Windows identities such as
`Everyone`, `Authenticated Users`, `Users`, `Domain Users`, and `INTERACTIVE`. Other ACL entries are
not copied into the evidence artifact.

Possible path postures:

| Posture | Meaning |
|---|---|
| `allow_signal_present` | A relevant allow ACE contains the requested read or read/write signal. |
| `explicit_deny_review` | A relevant deny ACE contains read or write rights and needs review. |
| `no_relevant_grant_observed` | No direct or selected broad allow signal was found. Group-expanded effective access is still unknown. |
| `missing` | The directory was not present. Expected-profile and operator-supplied missing paths may require review. |
| `acl_unavailable` | The directory existed but its ACL could not be read. |

## File-share roundabout metadata

When the expected profile exists and its user hive is loaded, the collector reads bounded metadata
from:

```text
HKEY_USERS\<SID>\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders
HKEY_USERS\<SID>\Network
```

It records selected shell-folder redirection values and mapped drive letters. It classifies the
stored path as local, UNC, an environment expression, or another form.

The collector does not contact those shares and does not claim that the AutoLogon account can reach
them. Remote share availability, share permissions, NTFS permissions on the server, authentication,
and network timing must be validated separately in the actual user session.

## Before AutoLogon deployment

Use the same approved target manifest as the deployment:

```powershell
$accessBefore = .\scripts\Invoke-SasAutoLogonFileAccessPosture.ps1 `
  -Mode Before `
  -TargetsCsv .\targets\local\autologon-pilot.csv `
  -PermissionPath @(
    'C:\ProgramData\VendorApp',
    'C:\Northwell'
  ) `
  -TechnicianLabel 'AutoLogon pilot'

$accessRunId = $accessBefore.run_id
```

Evidence is written under:

```text
survey\output\autologon_file_access\<run_id>\
```

## After AutoLogon deployment

Reuse the emitted run ID and the same approved target manifest:

```powershell
.\scripts\Invoke-SasAutoLogonFileAccessPosture.ps1 `
  -Mode After `
  -RunId $accessRunId `
  -TargetsCsv .\targets\local\autologon-pilot.csv `
  -PermissionPath @(
    'C:\ProgramData\VendorApp',
    'C:\Northwell'
  ) `
  -TechnicianLabel 'AutoLogon pilot'
```

Review:

```text
autologon_file_access_summary.csv
autologon_file_access_summary.json
delta\<target>.json
operator_handoff.txt
```

## Decisions

Each After comparison receives one decision:

| Decision | Meaning |
|---|---|
| `ACCESS_POSTURE_IMPROVED` | No final path review is flagged and the profile, ACL, shell-folder redirection, or mapped-drive posture changed. |
| `NO_MATERIAL_ACCESS_CHANGE` | No relevant before/after access-posture change was detected. |
| `ACCESS_POSTURE_REVIEW` | The final state still contains an explicit deny, missing required path, unreadable ACL, or no selected allow signal on an expected/custom path. |
| `ACCESS_REGRESSION_REVIEW` | The final state introduced or increased review conditions. |
| `INCONCLUSIVE` | A baseline or final snapshot was unavailable. |

A decision does not replace a user-session test.

## Pilot acceptance

Before expanding beyond the pilot, require:

1. AutoLogon registry/software state evidence is complete.
2. File-access Before and After captures succeeded for the same targets.
3. No unexpected explicit deny exists on the expected profile or required local application directories.
4. Expected and operator-supplied paths are present or their absence is understood.
5. Shell-folder redirection and mapped drive metadata point to the intended file-share roundabout when that design is required.
6. No directory contents or share paths were contacted by the evidence collector.
7. A real AutoLogon session confirms the user can open the application and perform the required read/write/save workflow.
8. A real AutoLogon session confirms the intended file share is reachable when local directories are intentionally unavailable.

The ACL snapshot proves only the recorded ACL and profile posture. The real session proves the user
experience.
