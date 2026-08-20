# Field Workflow Skill

Use this skill for technician commands, launchers, menus, QR command capsules, operator runbooks, dashboard entry guidance, and organization-scoped shared-printer management.

## Capability dependencies

- [Field Command Design](../../capabilities/field-command-design.md)
- [Language Runtime Selection](../../capabilities/language-runtime-selection.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)

## Canonical references

Load only the references that match the selected field lane:

- Printer mapping use-case registry: [`harness/api/printer-mapping-use-case-registry.json`](../../../harness/api/printer-mapping-use-case-registry.json)
- Printer mapping use-case workflow: [`harness/workflows/printer-mapping-use-case-routing.yaml`](../../../harness/workflows/printer-mapping-use-case-routing.yaml)
- Printer mapping use-case skill: [`harness/skills/printer-mapping-use-case-routing/SKILL.md`](../../../harness/skills/printer-mapping-use-case-routing/SKILL.md)
- Northwell reversible printer management: [`START-HERE-NORTHWELL-PRINTER-MANAGEMENT.md`](../../../START-HERE-NORTHWELL-PRINTER-MANAGEMENT.md)
- Northwell technician hub: [`Manage-NorthwellPrinters.cmd`](../../../Manage-NorthwellPrinters.cmd)
- Northwell quick map: [`Map-NorthwellPrinter-SystemWide.cmd`](../../../Map-NorthwellPrinter-SystemWide.cmd)
- Northwell quick unmap: [`Unmap-NorthwellPrinter-SystemWide.cmd`](../../../Unmap-NorthwellPrinter-SystemWide.cmd)
- Northwell undo: [`Undo-LatestNorthwellPrinterChange.cmd`](../../../Undo-LatestNorthwellPrinterChange.cmd)
- Northwell local-default editor: [`Edit-NorthwellPrinter-Defaults.cmd`](../../../Edit-NorthwellPrinter-Defaults.cmd)
- Northwell batch editor: [`Edit-NorthwellPrinter-Batch.cmd`](../../../Edit-NorthwellPrinter-Batch.cmd)
- Northwell batch manager: [`Map-NorthwellPrinters-Batch.cmd`](../../../Map-NorthwellPrinters-Batch.cmd)
- Canonical Northwell printer state engine: [`mapping/Invoke-NorthwellPrinterState.ps1`](../../../mapping/Invoke-NorthwellPrinterState.ps1)
- Northwell printer evidence precedence: [`harness/api/northwell-printer-mapping-evidence-policy.json`](../../../harness/api/northwell-printer-mapping-evidence-policy.json)
- Copy-safe capsule source policy: [`harness/api/copy-safe-operator-command-policy.json`](../../../harness/api/copy-safe-operator-command-policy.json)
- Dashboard front door and fallback: [`docs/DASHBOARD_ENTRYPOINT.md`](../../../docs/DASHBOARD_ENTRYPOINT.md)
- Software deployment tutorial: [`docs/tutorials/SOFTWARE_DEPLOYMENT_DRY_RUN_AND_PILOT.md`](../../../docs/tutorials/SOFTWARE_DEPLOYMENT_DRY_RUN_AND_PILOT.md)
- Software installation safety contract: [`docs/SOFTWARE_INSTALL_HARNESS.md`](../../../docs/SOFTWARE_INSTALL_HARNESS.md)
- Executable fixture proof: [`docs/SOFTWARE_INSTALL_E2E.md`](../../../docs/SOFTWARE_INSTALL_E2E.md)
- Software-install result presentation: [`docs/SOFTWARE_INSTALL_RESULT_INSPECTION.md`](../../../docs/SOFTWARE_INSTALL_RESULT_INSPECTION.md)

## Source freshness before field continuation

Before emitting a next command for a registered field capsule, **reconcile current repository truth** rather than reusing a branch/SHA from an earlier handoff.

- Once the capability is merged or superseded, canonical `main` is the executable source of truth.
- A historical PR branch or pinned SHA may be used to review or reproduce that exact old state, but it is not an operator retry source after merge.
- If a branch no longer equals a previously expected SHA, treat the mismatch as a supersession/reconciliation signal. Do not ask the technician to chase the old commit, force the branch backward, or create a detached worktree for a superseded implementation.
- Resolve the current tracked launcher from the capsule policy and use the current canonical implementation.

## Printer mapping context gate

Before applying **any** printer-mapping or printer-unmapping implementation:

1. Read `harness/api/printer-mapping-use-case-registry.json`.
2. Treat organization and site/hospital as part of printer-management identity, not optional descriptive context.
3. Select an exact `site_override` first when one exists; otherwise use the registered organization default.
4. If the organization is unknown, the site is known to operate independently without an override, or the selected record is `discovery_required`, stop before mutation and surface the discovery requirements.
5. Load mapping scope, queue conventions, execution identity, launcher, engine, and proof rules only from the selected `proven` use case.
6. **Northwell rules are not portable defaults.** Never infer another organization uses SYSTEM, `/ga`, `/gd`, UNC queues, HKLM registration, or the same network/authentication model merely because Northwell does.
7. **Health & Hospitals is currently `discovery_required`.** Do not route it to any Northwell map, unmap, undo, batch, or proof workflow until a separate Health & Hospitals implementation is learned, tracked, and validated.
8. Newly acquired or independently operated hospitals that differ from their parent organization require an explicit `site_override`; do not silently inherit the organization default.
9. Runtime acceptance and failure evidence apply only to the same selected use case and organization/site context that produced them.

## Northwell reversible printer-management route

Only after `northwell.shared-printer.organization-default` is selected, when a technician asks to map, add, install, connect, unmap, remove, disconnect, reverse, or undo a printer change on a Northwell Windows PC:

1. Treat **system-wide/per-computer** state as a hard client requirement because the workstation may have multiple users.
2. Ask only for missing operational inputs: target PC hostname(s), print-server hostname(s), and printer queue(s). Do not require the technician to run from a specific PC or checkout path.
3. Accept printer queue input as `\\server\queue`, `//server/queue`, or queue name only. Do not ask for or recommend a printer IP address.
4. Prefer the unified technician hub `Manage-NorthwellPrinters.cmd` when the operator has not already chosen a specific action. Direct routes remain valid:
   - **Map:** `Map-NorthwellPrinter-SystemWide.cmd`.
   - **Unmap:** `Unmap-NorthwellPrinter-SystemWide.cmd`.
   - **Reverse latest observed transitions:** `Undo-LatestNorthwellPrinterChange.cmd`.
   - **Maintain one approved local default pair:** `Edit-NorthwellPrinter-Defaults.cmd`; this edits only `Config\northwell-printer-defaults.local.json` and does not mutate a target.
   - **Repeated/tabular map or unmap:** edit with `Edit-NorthwellPrinter-Batch.cmd`, then run `Map-NorthwellPrinters-Batch.cmd`.
5. Root CMD launchers resolve their checkout with `%~dp0`. Never hard-code an operator profile such as `C:\Users\...`, a specific admin box, or one developer workstation as a product dependency.
6. Live Northwell printer-device actions may proceed through any route accepted by the shared Northwell network authority: WAB Wi-Fi, live `DomainAuthenticated` non-Wi-Fi hardwire/LAN, authenticated VPN/non-Wi-Fi, or explicitly configured protected-route evidence. Do not require one adapter product name or exact IP address when stronger live authority is present.
7. Map drives the requested queue to `Present` using SYSTEM + `PrintUIEntry /ga`. Unmap drives it to `Absent` using SYSTEM + the paired `PrintUIEntry /gd`. Already-present maps and already-absent unmaps are safe no-ops.
8. Unmapping removes only the requested per-computer shared-queue registration. Do not delete printer ports, use `Remove-Printer`, or substitute a per-user removal path.
9. For unmapping with a known full `\\server\queue`, do not require the retired/unreachable print server to resolve before the stale machine-wide registration can be removed.
10. Every live map/unmap run must capture requested queue state before and after mutation. `UndoPlan.json` may contain only queues whose state was actually observed to change; never create inverse work merely because a command was attempted.
11. `Undo-LatestNorthwellPrinterChange.cmd` must display the exact state-derived inverse plan and require exact `UNDO` confirmation before live mutation. The undo run produces its own `UndoPlan.json`, making the undo itself reversible when a transition succeeds.
12. In the batch CSV, `Action` is `Map` or `Unmap`; older local files without `Action` default to `Map`. One row applies its action to every queue in that row on every computer in that row. Use semicolons inside `ComputerName` and `QueueName` cells for multiple values.
13. Never commit a live print server/queue as a default or example. Tracked examples use synthetic `REPLACE-WITH-*` values only. Approved convenience defaults and live assignments remain gitignored.
14. Batch performs a local-only shape/placeholder pass first. It must then pass the shared Northwell network authority **before** any AD/DNS-backed queue resolution.
15. Batch must display/write the complete mixed map/unmap plan and require exact `APPLY` confirmation before live mutation unless an advanced caller explicitly supplies `-ConfirmBatch`.
16. Batch and undo are orchestration only. They must delegate state mutation to `mapping\Invoke-NorthwellPrinterState.ps1`; do not implement competing printer mutation engines.
17. Do not substitute `Utilities\Map-Printer.ps1` or `Add-Printer -ConnectionName`, which are per-user paths.
18. Do not call map or unmap successful merely because a command launched. The canonical state engine proves SYSTEM identity plus the requested queue's desired HKLM per-computer state.
19. If the user was already signed in when `/ga` ran, explain that sign-out/sign-in may be needed before a newly mapped printer becomes visible in that user's shell session; do not remap it per-user as a workaround.
20. If the operator reports that a real requested document printed successfully after canonical mapping, treat that as **runtime acceptance evidence that the mapped print path works**. Do not request another test page, remove/rebuild the printer, or reinterpret the mapping as failed solely because local `PortName`, `WorkOffline`, CIM, RPC, SMB, or remote `Get-Printer` telemetry looks contradictory. Preserve that lower-ranked telemetry as diagnostic context unless a later observed print failure reopens the incident.
21. `Repair-NorthwellPrinter-Queue-Evidence.cmd` is **artifact reclassification only**. Use it only when preserved local JSON explicitly records `physical_output_observed=true` and the derived classifier is wrong. Do not use it merely because a real requested document already printed successfully.
22. On failure, direct diagnosis to run-scoped evidence. Quick state runs use `ResolvedPlan.json`, `Controller.log`, `Summary.json`, `UndoPlan.json`, and per-target `Status.json`/`Agent.log`; batch adds `BatchPlan.json` and child group evidence; undo preserves its source and inverse execution evidence.

## Workflow

1. Identify the field user, organization, site/hospital when relevant, target environment, and mutation posture.
2. For printer management, resolve the registered organization/site use case before selecting any launcher or implementation.
3. Reconcile the current repository floor before reusing any branch, SHA, worktree, or next-command from a prior chat/handoff.
4. Prefer an existing launcher, profile, menu, or wrapper.
5. Reduce the technician action to one short entrypoint when practical.
6. Put target validation, elevation, retries, teardown, progress, evidence, reversibility, and classification inside the repo-owned workflow.
7. For software-install results, use `Inspect-LatestSoftwareInstall.cmd` as the field front door. Agents invoke `scripts/Show-SasSoftwareInstallResult.ps1` immediately after the install, when recovering an interrupted run, and before saying deployment succeeded.
8. Keep developer diagnostics separate from the field front door.
9. Provide a dry-run or review mode before mutation when the operation supports it.
10. Validate the launcher contract and the delegated workflow separately.

## Guardrails

- Do not require technicians to memorize run IDs or reconstruct long commands when state can be stored locally and safely.
- Do not hide scope, mutation, reversibility, or failure classifications.
- A launcher ACK is not proof that the intended behavior occurred.
- Installer completion is not package-level post-install acceptance; present the remaining verification gate.
- For merged registered capsules, do not emit historical PR branches or pinned SHAs as normal operator retry sources.
- For printer management, do not select an implementation until the organization/site use case is registered and proven.
- Never use one organization's printer-management rules as another organization's defaults.
- For Northwell printer management, direct-IP installation and per-user-only mapping/removal are blocking contract violations, not fallbacks.
- Never commit `mapping\NorthwellPrinterBatch.csv` or `Config\northwell-printer-defaults.local.json`; they may contain live assignment/infrastructure data. Only synthetic examples are tracked.
- For Northwell batch management, network authority must precede AD/DNS-backed resolution and production mutation requires displayed-plan `APPLY` confirmation (or explicit advanced `-ConfirmBatch`).
- For Northwell undo, inverse work must come from observed before/after transitions in `UndoPlan.json`, not from guessed prior state.
- For Northwell printer diagnosis, successful real-world document output after canonical mapping outranks contradictory diagnostic telemetry. Do not turn a proven working mapping into a repair target solely to make lower-level telemetry look cleaner.
