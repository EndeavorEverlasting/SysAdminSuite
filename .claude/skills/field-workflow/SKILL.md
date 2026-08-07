# Field Workflow Skill

Use this skill for technician commands, launchers, menus, QR command capsules, operator runbooks, dashboard entry guidance, and Northwell shared-printer mapping.

## Capability dependencies

- [Field Command Design](../../capabilities/field-command-design.md)
- [Language Runtime Selection](../../capabilities/language-runtime-selection.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)

## Canonical references

Load only the references that match the selected field lane:

- Northwell shared-printer mapping: [`START-HERE-NORTHWELL-PRINTER-MAPPING.md`](../../../START-HERE-NORTHWELL-PRINTER-MAPPING.md)
- Northwell technician front door: [`Map-NorthwellPrinter-SystemWide.cmd`](../../../Map-NorthwellPrinter-SystemWide.cmd)
- Canonical Northwell printer engine: [`mapping/Invoke-NorthwellPrinterMapping.ps1`](../../../mapping/Invoke-NorthwellPrinterMapping.ps1)
- Dashboard front door and fallback: [`docs/DASHBOARD_ENTRYPOINT.md`](../../../docs/DASHBOARD_ENTRYPOINT.md)
- Software deployment tutorial: [`docs/tutorials/SOFTWARE_DEPLOYMENT_DRY_RUN_AND_PILOT.md`](../../../docs/tutorials/SOFTWARE_DEPLOYMENT_DRY_RUN_AND_PILOT.md)
- Software installation safety contract: [`docs/SOFTWARE_INSTALL_HARNESS.md`](../../../docs/SOFTWARE_INSTALL_HARNESS.md)
- Executable fixture proof: [`docs/SOFTWARE_INSTALL_E2E.md`](../../../docs/SOFTWARE_INSTALL_E2E.md)
- Software-install result presentation: [`docs/SOFTWARE_INSTALL_RESULT_INSPECTION.md`](../../../docs/SOFTWARE_INSTALL_RESULT_INSPECTION.md)

## Northwell printer mapping route

When a technician asks to map, add, install, or connect a printer on a Northwell Windows PC:

1. Treat **system-wide/per-computer** mapping as a hard client requirement because the workstation may have multiple users.
2. Ask only for missing operational inputs: target PC hostname(s) and printer queue(s).
3. Accept printer queue input as `\\server\queue`, `//server/queue`, or queue name only. Do not ask for or recommend a printer IP address.
4. Route the technician to **double-click `Map-NorthwellPrinter-SystemWide.cmd`**. The launcher owns elevation, prompts, terminal persistence, and delegation to the validated PowerShell engine.
5. Do not substitute `Utilities\Map-Printer.ps1` or `Add-Printer -ConnectionName`, which are per-user paths.
6. Let the canonical runner resolve queue-only input from Active Directory, normalize short Northwell hostnames, reject IP/URL inputs, run the endpoint action as SYSTEM, and use `PrintUIEntry /ga`.
7. Do not call the mapping successful unless the run returns SYSTEM identity plus the requested queue under the HKLM per-computer printer-connection registry evidence.
8. If the user was already signed in when `/ga` ran, explain that sign-out/sign-in may be needed before the printer becomes visible in that user's shell session; do not remap it per-user as a workaround.
9. On failure, direct diagnosis to the run-scoped `ResolvedPlan.json`, `Controller.log`, per-target `Status.json`/`Agent.log`, and `Summary.json` instead of reconstructing the vanished terminal output.

## Workflow

1. Identify the field user, target environment, and mutation posture.
2. Prefer an existing launcher, profile, menu, or wrapper.
3. Reduce the technician action to one short entrypoint when practical.
4. Put target validation, elevation, retries, teardown, progress, evidence, and classification inside the repo-owned workflow.
5. For software-install results, use `Inspect-LatestSoftwareInstall.cmd` as the field front door. Agents invoke `scripts/Show-SasSoftwareInstallResult.ps1` immediately after the install, when recovering an interrupted run, and before saying deployment succeeded.
6. Keep developer diagnostics separate from the field front door.
7. Provide a dry-run or review mode before mutation when the operation supports it.
8. Validate the launcher contract and the delegated workflow separately.

## Guardrails

- Do not require technicians to memorize run IDs or reconstruct long commands when state can be stored locally and safely.
- Do not hide scope, mutation, or failure classifications.
- A launcher ACK is not proof that the intended behavior occurred.
- Installer completion is not package-level post-install acceptance; present the remaining verification gate.
- For Northwell printer mapping, direct-IP installation and per-user-only mapping are blocking contract violations, not fallbacks.