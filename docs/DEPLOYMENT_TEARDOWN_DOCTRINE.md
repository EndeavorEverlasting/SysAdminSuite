# Deployment teardown doctrine

Deployment, mapping, and staging tools are an authorized mutation lane. They are
not survey tools. The canonical validated-deployment front door is first-class;
only preserved compatibility tools remain gated as legacy.

## Rules

- Preserve working PowerShell and Windows deployment tools; do not delete them as
  part of Bash-first survey work.
- Require explicit legacy authorization before preserved compatibility mutation
  entrypoints run. Do not apply that gate to the canonical closed-request path.
- Treat copied payload scripts, launchers, status files, stop files, scheduled
  tasks, and temporary staging folders as transient unless a document says they
  are intentionally retained.
- Write operator evidence and logs locally. Do not use target workstations as an
  evidence store.
- On success, remove transient remote payloads and scheduled tasks.
- On failure or interruption, attempt best-effort cleanup and record the result
  in the local operator log.
- Do not describe cleanup as hiding activity or suppressing logs. Cleanup reduces
  residual operational clutter; normal endpoint and network telemetry may exist.

## Tool classes

| Class | Examples | Teardown expectation |
|-------|----------|----------------------|
| Printer mapping controller | `mapping/Controllers/Map-Run-Controller.ps1` | Remove scheduled task, launcher, payload script, status/stop files, and empty remote working dirs |
| Canonical software deployment | `scripts/Invoke-SasValidatedSoftwareDeployment.ps1` | Select WinRM or SMB/Task before mutation, retrieve closed results, delete the unique task, remove only `SoftwareInstall\<run-id>`, and verify both are absent |
| Bash compatibility wrapper | `bash/apps/sas-install-apps.sh` | `--request` delegates to the canonical PowerShell front door; preserved `--list`/`--package` behavior retains its AppInstall cleanup boundary and legacy gate until parity retirement |
| Installer staging | `bash/apps/sas-stage-fileshare.sh` | Retain by default for deployment cache; `--teardown-after` removes transient staged files |
| Shortcut deployment | `EnvSetup/Deploy-Shortcuts.ps1` | Shortcuts are the intended payload and are retained |

## Legacy enablement

Legacy enablement applies only to the preserved `--list`/`--package` compatibility
controller and other explicitly legacy tools. Use the smallest explicit opt-in:

```text
--allow-legacy
```

or:

```text
SAS_ALLOW_LEGACY_TOOLS=1
```

The opt-in only enables preserved legacy tooling. It does not expand target
scope, grant credentials, or change the need for authorized deployment intent.

## Local output

Deployment logs should stay on the operator machine, for example:

- `bash/apps/output/`
- `SysAdminSuite-Session-*`
- documented local report paths

If a tool intentionally leaves a deployment artifact on a target, the tool docs
must state whether that artifact is a desired payload, a retained cache, or a
transient file requiring teardown.
