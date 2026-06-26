# Dashboard Toolbox Tutorial

The dashboard **Toolbox Check** layer probes every tool the suite cares about, writes live status JSON for the browser, and auto-opens a glowing wizard when something is missing or outdated.

## What gets probed

| Tool | Tier | Auto-ensure | Tutorial fix |
|------|------|-------------|--------------|
| Repo / updates | required | Opt-in launcher update | Re-run `START-HERE-SysAdminSuite-Dashboard.bat` |
| Git Bash | required | No (hard launcher gate) | Install Git for Windows |
| CMD / Windows PowerShell | required | n/a | Informational |
| PowerShell 7 | recommended | `bash/apps/sas-install-apps.sh` | Copy install guidance |
| Python 3 | recommended | `bash/apps/sas-install-apps.sh` | Copy install guidance |
| .NET ASP.NET Core RT | required | `bash scripts/ensure-dotnet-runtime.sh` | Copy ensure command |
| .NET Windows Desktop RT | required | same | same |
| .NET 8 SDK | workflow | `bash scripts/ensure-dotnet-sdk.sh` | Source checkout only; n/a on field release |
| Dashboard host | required | Launcher bootstrap | Re-run launcher |
| naabu | workflow | `bash survey/sas-ensure-naabu.sh` | Copy ensure command |
| nmap | workflow | **Manual install only** | Doc link — no auto-download |
| curl / unzip | required | Git Bash bundle | Repair Git Bash |

## Architecture

1. **Manifest** — [`Config/toolbox-dependencies.json`](../Config/toolbox-dependencies.json) lists tools, tiers, pins, and ensure actions.
2. **Probe** — [`scripts/sas-probe-toolbox.sh`](../scripts/sas-probe-toolbox.sh) read-only check; always exit 0.
3. **Writer** — [`scripts/sas-write-toolbox-status.sh`](../scripts/sas-write-toolbox-status.sh) adds `actionNeeded` / `summary`; writes [`dashboard/toolbox-status.json`](../dashboard/toolbox-status.json) (gitignored).
4. **Browser** — [`dashboard/js/launch-toolbox-tutorial.js`](../dashboard/js/launch-toolbox-tutorial.js) fetches status; toolbox wizard first when `actionNeeded`, else repo-setup for `?tutorial=setup`.

Pinned versions align with:

- [`Config/dotnet-bootstrap.json`](../Config/dotnet-bootstrap.json)
- [`Config/cybernet-naabu-profiles.json`](../Config/cybernet-naabu-profiles.json)
- [`Config/sources.yaml`](../Config/sources.yaml) (PowerShell 7, Python)

## Glow behavior

Reuses `.sas-guide-glow` and `.sas-guide-panel` from the existing workflow tutorials:

- One wizard step per failing tool (dynamic, not static).
- Copy Command glows until copied → Next glows → final step Re-check glows.
- Checklist row for the current tool also glows.
- Banner glows when `actionNeeded`.

## Re-check flow

After running an ensure script outside the dashboard, either:

- Click **Re-check toolbox** in the wizard footer, or
- Re-run `START-HERE-SysAdminSuite-Dashboard.bat` (launcher rewrites status JSON).

## Sample fixtures

Committed under `dashboard/samples/` for manual smoke:

- `toolbox-status-all-ok.json`
- `toolbox-status-missing-naabu.json`
- `toolbox-status-update-available.json`

Copy a sample to `dashboard/toolbox-status.json` to test the banner and wizard without re-probing.

## Doctrine

- **No winget/choco** in probe or tutorial commands.
- **nmap**: detect and guide only.
- **Git Bash**: launcher hard gate unchanged (exit 2).
- **Consent-gated updates**: dashboard never silently mutates the repo.

## Related docs

- [`DASHBOARD_ENTRYPOINT.md`](DASHBOARD_ENTRYPOINT.md)
- [`DASHBOARD_DEPENDENCY_BOOTSTRAP.md`](DASHBOARD_DEPENDENCY_BOOTSTRAP.md)
- [`NAABU_CYBERNET_PROFILES.md`](NAABU_CYBERNET_PROFILES.md)
- [`APPROVED_UPDATE_FLOW.md`](APPROVED_UPDATE_FLOW.md)

## Validation

```bash
bash scripts/sas-probe-toolbox.sh --dry-run | python3 -m json.tool
bash Tests/bash/test_toolbox_probe_contracts.sh
bash Tests/bash/test_dashboard_toolbox_tutorial_contracts.sh
```
