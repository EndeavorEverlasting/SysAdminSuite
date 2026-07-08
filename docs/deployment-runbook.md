# Authorized Application Deployment Runbook

This lane is for manifest-driven internal software deployment from one authorized admin/orchestrator machine to approved internal hostnames. It is a mutation lane, not a survey lane.

## Safety posture

- Dry-run is the default; target changes require `-Execute`.
- Production hostnames live in the manifest, not in the script.
- Use `-SingleHost` first, then `-TargetLimit` for bounded batches.
- Installers are staged only under `C:\ProgramData\SysAdminSuite\DeploymentTemp\<deployment-id>\` on the target.
- Cleanup removes only files below that script-created deployment temp root.
- The main script is never self-deleted.
- Event, Security, PowerShell, WinRM, Defender, EDR, and audit logs are never cleared, deleted, mutated, suppressed, or disabled.

## Dry-run example

```powershell
.\scripts\Invoke-AuthorizedAppDeployment.ps1 -ManifestPath .\examples\deployment-manifest.example.csv -TargetLimit 1
```

## Execute example

```powershell
.\scripts\Invoke-AuthorizedAppDeployment.ps1 -ManifestPath .\approved\deployment-manifest.csv -SingleHost WORKSTATION001 -Execute
```

## Outputs

Runtime evidence is local-only and gitignored under `output/deployments/<deployment-id>/`:

- `deployment-summary.md`
- `deployment-results.json`
- `deployment-results.csv`
- `validation-report.json`
- `logs/`

Proof level in this repository is contract/static harness proof unless a future operator runs the script in an authorized live deployment environment and records that runtime evidence.
