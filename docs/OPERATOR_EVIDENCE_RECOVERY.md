# Operator Evidence Recovery

Use this page when a SysAdminSuite terminal closed, crashed, was disconnected, or scrolled past the useful output and the operator needs to answer two questions:

1. **Where did the result go?**
2. **What is the next safe action?**

Do not redeploy a target merely to recreate console output.

## One command

From any terminal where the current SysAdminSuite operator command is installed:

```powershell
sas evidence
```

This command is **offline and read-only with respect to targets**. It performs no network activity, no target contact, no software-share access, and no target mutation.

Useful variants:

```powershell
sas evidence All
sas evidence Cybernet
sas evidence AutoLogon
sas evidence Runtime
sas evidence Open
```

`Open` opens the folder containing the newest matching evidence after the bounded local search.

When the installed `sas` command has not yet been refreshed, run the repo-local fallback:

```powershell
.\Find-SasEvidence.cmd
```

## Checkout locations considered

Technician machines do not need one universal repository path. Evidence recovery considers the current repo, the cached `sas repo` location, `SAS_REPO_ROOT`, and bounded common per-user layouts beneath:

- `%USERPROFILE%`
- `%OneDrive%`
- `%OneDriveCommercial%`
- `%OneDriveConsumer%`

Known checkout names include:

- `SysAdminSuite`
- `SysAdminSuite-portable-onsite`
- `SysAdminSuite-Live`

and common placements such as:

```text
<profile>\SysAdminSuite
<profile>\dev\SysAdminSuite
<profile>\Desktop\dev\SysAdminSuite
<OneDrive>\Desktop\dev\SysAdminSuite
<OneDrive>\OG Laptop Backup\Desktop\dev\SysAdminSuite
```

The recovery command does **not** recursively scan the whole workstation. It searches only known SysAdminSuite output roots beneath bounded candidate checkouts plus the runtime evidence directory explicitly named by a local `targets\local\autologon-runtime.json` config when present.

## Critical evidence locations

### Full Cybernet software deployment

```text
survey\output\runs\cybernet-software-deployment\cybernet-software-deployment-*\cybernet_software_deployment_result.json
```

Successful terminal state:

```text
CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED
```

### AutoLogon-only restart-complete deployment

```text
survey\output\runs\autologon-s4u-deployment\autologon-s4u-deployment-*\autologon_s4u_deployment_result.json
```

Successful terminal state:

```text
AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED
```

### Historical/internal S4U pre-reboot apply

```text
survey\output\runs\autologon-kerberos-s4u\...\autologon_kerberos_s4u_pilot_result.json
```

The classification:

```text
KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING
```

proves the pre-reboot AutoLogon apply gate only. Preserve it. It does not by itself prove the current restart-complete deployment state.

### Five-application clinical-core stage

```text
survey\output\runs\cybernet-clinical-core\...\cybernet_clinical_core_deployment_summary.json
```

`CLINICAL_CORE_DEPLOYMENT_COMPLETED` means the five clinical applications are complete. Preserve that state rather than reinstalling them merely to reach AutoLogon.

### Package-controller evidence

```text
bash\apps\output\*.results.csv
bash\apps\output\*.log
```

The recovery command indexes result CSVs. Logs remain available in the same controller output directory for focused diagnosis.

### Optional actual-session runtime proof

The runtime proof writes:

```text
<evidence_directory>\autologon-runtime-*\runtime-proof-summary.json
```

The `evidence_directory` comes from the technician-local `targets\local\autologon-runtime.json` configuration. When that config is present in a discovered checkout, `sas evidence` also searches that explicit evidence directory.

## Stable local pointer

Every `sas evidence` run writes a local index here:

```text
%LOCALAPPDATA%\SysAdminSuite\last-evidence.json
```

That file records the discovered local artifact paths, timestamps, public state fields, and the next-action interpretation. It is machine-local evidence and must not be committed.

## Recovery rules

- A closed terminal does **not** erase an artifact that was already written to disk.
- Do not rerun deployment merely because console output disappeared.
- `CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED` means full Cybernet software deployment completed through restart.
- `AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED` means AutoLogon-only deployment completed through restart.
- `KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING` is an older/internal pre-reboot ceiling, not current deployment completion.
- `CLINICAL_CORE_DEPLOYMENT_COMPLETED` means preserve the five installed applications and continue only with the remaining AutoLogon state when required.
- A failed/blocked artifact must be preserved and diagnosed before another target mutation. Do not blindly retry.
- Absence of local evidence does not prove success or failure. It means no conclusion should be manufactured from the missing console window.

## Refresh the portable operator command

After pulling a repository version that changes the portable `sas` surface, refresh it for the current Windows user:

```powershell
.\Install-SasOperatorCommand.cmd
```

The launcher caches the resolved repository path under `%LOCALAPPDATA%\SysAdminSuite\repo-root.txt` and can rediscover the supported Desktop/OneDrive layouts if the checkout moves.
