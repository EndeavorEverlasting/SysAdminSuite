# Dashboard Toolbox Tutorial

The dashboard **Toolbox Check** layer is the live dependency checklist for the
local workstation. It covers the repo update state, Git Bash, CMD, Windows
PowerShell, PowerShell 7, Python, .NET runtimes and SDK, the dashboard host,
naabu, nmap, curl, and unzip.

This is not a .NET-only installer prompt. It is a unified toolbox health layer
with a glowing wizard that points technicians to the exact next action when a
tool is missing, outdated, blocked, or requires update review.

## How It Works

1. `START-HERE-SysAdminSuite-Dashboard.bat` runs the approved update check and
   exports `SAS_UPDATE_STATE` / `SAS_UPDATE_MODE`.
2. `Launch-SysAdminSuiteDashboard.Host.bat` keeps Git Bash as the hard launcher
   gate, prepares the dashboard host, then runs:

   ```bash
   bash scripts/sas-write-toolbox-status.sh
   ```

3. The writer calls `scripts/sas-probe-toolbox.sh`, enriches the result with
   `actionNeeded` and `summary`, and writes ignored runtime JSON:

   ```text
   dashboard/toolbox-status.json
   ```

4. `dashboard/js/launch-toolbox-tutorial.js` fetches that JSON. If
   `actionNeeded` is true, the Toolbox wizard opens before Repo Setup.

## Leaving a wizard

Every dashboard wizard (Toolbox Check, Repo Setup, Cybernet Survey, Software
Tracker Install) carries a persistent **← Back to dashboard** control at the top
of the wizard. It is always visible and never depends on the current step, so a
field user can always close the wizard and return to its hero/start action. The
step-level **← Previous Step** button is a separate control and may be disabled
on the first step; the Back to dashboard control is not. Closing a wizard hides
only the wizard chrome and does not clear loaded evidence.

## Probe Contract

The committed manifest is
[`Config/toolbox-dependencies.json`](../Config/toolbox-dependencies.json). Each
tool entry defines:

- `id`
- `displayName`
- `tier`
- `workflows`
- `pinnedVersion`
- `probe`
- `ensure`
- `installDoc`
- `statusHints`

Status values are:

```text
ok
missing
outdated
blocked
unknown
not_applicable
```

Pinned versions align with:

- [`Config/dotnet-bootstrap.json`](../Config/dotnet-bootstrap.json)
- [`Config/cybernet-naabu-profiles.json`](../Config/cybernet-naabu-profiles.json)
- [`Config/sources.yaml`](../Config/sources.yaml) for PowerShell 7 and Python

The probe is read-only and informational. It does not install tools, mutate the
repo, or broaden any survey scope.

## Dashboard Behavior

When a required or workflow tool needs attention:

- `#toolbox-status-banner` glows at the top of the dashboard.
- `#toolbox-checklist` shows one row per probed tool.
- Rows needing action get the same `.sas-guide-glow` cue used by existing
  dashboard tutorials.
- `#toolbox-tutorial` builds one wizard step per failing tool.
- The wizard glows **Copy Command**, then **Next**, then **Re-check toolbox**.

If all probed tools are ready, the dashboard proceeds to Repo Setup when opened
with `?tutorial=setup`.

## How Next Works

The dashboard wizards never run commands for the user. **Next only advances the
wizard.** When a step needs outside action, the technician copies the command,
runs it in the appropriate local shell, then returns to the dashboard and clicks
Next.

Every command panel shows one of three run states:

- `RUN IT YOURSELF` means copy the command and run it outside the dashboard.
- `NOTHING TO RUN` means the panel is showing reference text or file paths only.
- `JUST CLICK NEXT` means the step has no outside command.

Each panel also includes an always-visible summary and an expandable
**Explain each part** breakdown so technicians understand what the command or
reference text is for before moving on.

## What Gets Probed

| Tool | Tier | Auto-ensure | Tutorial fix |
|------|------|-------------|--------------|
| Repo / updates | required | Opt-in launcher update | Re-run `START-HERE-SysAdminSuite-Dashboard.bat` |
| Git Bash | required | No; hard launcher gate | Install Git for Windows or use field release |
| CMD / Windows PowerShell | required | n/a | Informational |
| PowerShell 7 | recommended | `bash/apps/sas-install-apps.sh` | Copy install guidance |
| Python 3 | recommended | `bash/apps/sas-install-apps.sh` | Copy install guidance |
| .NET ASP.NET Core Runtime | required | `bash scripts/ensure-dotnet-runtime.sh` | Copy ensure command |
| .NET Windows Desktop Runtime | required | same | same |
| .NET 8 SDK | workflow | `bash scripts/ensure-dotnet-sdk.sh` | Source checkout only; n/a on field release |
| Dashboard host | required | Launcher bootstrap | Re-run launcher |
| naabu | workflow | `bash survey/sas-ensure-naabu.sh` | Copy ensure command |
| nmap | workflow | Manual install only | Doc link; no auto-download |
| curl / unzip | required | Git Bash bundle | Repair Git Bash |

## Re-check Flow

After running an ensure script outside the dashboard, either:

- Click **Re-check toolbox** in the wizard footer.
- Re-run `START-HERE-SysAdminSuite-Dashboard.bat`, which rewrites status JSON.

## Sample Fixtures

Committed sanitized fixtures live under `dashboard/samples/`:

```text
dashboard/samples/toolbox-status-all-ok.json
dashboard/samples/toolbox-status-missing-naabu.json
dashboard/samples/toolbox-status-update-available.json
```

Copy one sample to the ignored runtime location to test the banner and wizard
without re-probing:

```bash
cp dashboard/samples/toolbox-status-missing-naabu.json dashboard/toolbox-status.json
```

Do not commit `dashboard/toolbox-status.json`; it is runtime machine state.

## Guardrails

- No `winget`, Chocolatey, or browser-driven installs are used in the toolbox
  probe or tutorial commands.
- nmap is detect-and-guide only on Northwell workstations. The dashboard never
  auto-downloads it.
- naabu install guidance uses `survey/sas-ensure-naabu.sh` and preserves the
  low-noise survey discipline from `survey/naabu_profiles.json`.
- Repo updates remain consent-gated in the launcher. The dashboard only points
  the user back to `START-HERE-SysAdminSuite-Dashboard.bat`.
- Git Bash remains a launcher-side hard gate because the browser cannot exist
  before the host bootstrap runs.

## Validation

```bash
bash scripts/sas-probe-toolbox.sh --dry-run | python -m json.tool
bash Tests/bash/test_toolbox_probe_contracts.sh
bash Tests/bash/test_dashboard_toolbox_tutorial_contracts.sh
```

## Related Docs

- [`DASHBOARD_ENTRYPOINT.md`](DASHBOARD_ENTRYPOINT.md)
- [`DASHBOARD_DEPENDENCY_BOOTSTRAP.md`](DASHBOARD_DEPENDENCY_BOOTSTRAP.md)
- [`NAABU_CYBERNET_PROFILES.md`](NAABU_CYBERNET_PROFILES.md)
- [`APPROVED_UPDATE_FLOW.md`](APPROVED_UPDATE_FLOW.md)
