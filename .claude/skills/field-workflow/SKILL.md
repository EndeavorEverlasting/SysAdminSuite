# Field Workflow Skill

Use this skill for technician commands, launchers, menus, QR command capsules, operator runbooks, dashboard entry guidance, and organization-scoped shared-printer mapping.

## Capability dependencies

- [Field Command Design](../../capabilities/field-command-design.md)
- [Language Runtime Selection](../../capabilities/language-runtime-selection.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)

## Canonical references

Load only the references that match the selected field lane:

- Printer mapping use-case registry: [`harness/api/printer-mapping-use-case-registry.json`](../../../harness/api/printer-mapping-use-case-registry.json)
- Printer mapping use-case workflow: [`harness/workflows/printer-mapping-use-case-routing.yaml`](../../../harness/workflows/printer-mapping-use-case-routing.yaml)
- Printer mapping use-case skill: [`harness/skills/printer-mapping-use-case-routing/SKILL.md`](../../../harness/skills/printer-mapping-use-case-routing/SKILL.md)
- Northwell shared-printer mapping: [`START-HERE-NORTHWELL-PRINTER-MAPPING.md`](../../../START-HERE-NORTHWELL-PRINTER-MAPPING.md)
- Northwell quick technician front door: [`Map-NorthwellPrinter-SystemWide.cmd`](../../../Map-NorthwellPrinter-SystemWide.cmd)
- Northwell batch editor: [`Edit-NorthwellPrinter-Batch.cmd`](../../../Edit-NorthwellPrinter-Batch.cmd)
- Northwell batch mapper: [`Map-NorthwellPrinters-Batch.cmd`](../../../Map-NorthwellPrinters-Batch.cmd)
- Canonical Northwell printer engine: [`mapping/Invoke-NorthwellPrinterMapping.ps1`](../../../mapping/Invoke-NorthwellPrinterMapping.ps1)
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

Before applying **any** printer-mapping implementation:

1. Read `harness/api/printer-mapping-use-case-registry.json`.
2. Treat organization and site/hospital as part of printer-mapping identity, not optional descriptive context.
3. Select an exact `site_override` first when one exists; otherwise use the registered organization default.
4. If the organization is unknown, the site is known to operate independently without an override, or the selected record is `discovery_required`, stop before mapping and surface the discovery requirements.
5. Load mapping scope, queue conventions, execution identity, launcher, engine, and proof rules only from the selected `proven` use case.
6. **Northwell rules are not portable defaults.** Never infer another organization uses SYSTEM, `/ga`, UNC queues, HKLM registration, or the same network/authentication model merely because Northwell does.
7. **Health & Hospitals is currently `discovery_required`.** Do not route it to the Northwell launcher, engine, mapping mechanism, or proof policy until a separate Health & Hospitals implementation is learned, tracked, and validated.
8. Newly acquired or independently operated hospitals that differ from their parent organization require an explicit `site_override`; do not silently inherit the organization default.
9. Runtime acceptance and failure evidence apply only to the same selected use case and organization/site context that produced them.

## Northwell printer mapping route

Only after `northwell.shared-printer.organization-default` is selected, when a technician asks to map, add, install, or connect a printer on a Northwell Windows PC:

1. Treat **system-wide/per-computer** mapping as a hard client requirement because the workstation may have multiple users.
2. Ask only for missing operational inputs: target PC hostname(s), print-server hostname(s), and printer queue(s).
3. Accept printer queue input as `\\server\queue`, `//server/queue`, or queue name only. Do not ask for or recommend a printer IP address.
4. Choose the technician front door by task shape:
   - **Ad-hoc / one-off / one shared printer set:** double-click `Map-NorthwellPrinter-SystemWide.cmd`.
   - **Repeated or tabular assignments:** double-click `Edit-NorthwellPrinter-Batch.cmd`, edit `mapping\NorthwellPrinterBatch.csv`, then double-click `Map-NorthwellPrinters-Batch.cmd`.
5. In the batch CSV, one row means **every queue in that row maps to every computer in that row**. Use semicolons inside `ComputerName` and `QueueName` cells for multiple values. Do not invent a different batch format.
6. The known field-proven example `\\SYKPNHPHPS01V\LS001-EMS01` is a Northwell quick/batch starter only. The target computer never has a default; a technician must explicitly supply the intended host(s).
7. Batch mode is orchestration only. It must delegate each row to `mapping\Invoke-NorthwellPrinterMapping.ps1`; do not implement a second mapping engine in a batch helper.
8. Do not substitute `Utilities\Map-Printer.ps1` or `Add-Printer -ConnectionName`, which are per-user paths.
9. Let the canonical runner resolve queue-only input from Active Directory, normalize short Northwell hostnames, reject IP/URL inputs, run the endpoint action as SYSTEM, and use `PrintUIEntry /ga`.
10. Do not call the mapping successful merely because a command launched. The canonical mapping engine proves SYSTEM identity plus the requested queue under the HKLM per-computer printer-connection registry evidence.
11. If the user was already signed in when `/ga` ran, explain that sign-out/sign-in may be needed before the printer becomes visible in that user's shell session; do not remap it per-user as a workaround.
12. If the operator reports that a real requested document printed successfully after the canonical mapping workflow, treat that as **runtime acceptance evidence that the mapped print path works**. Do not request another test page, remove/rebuild the printer, or reinterpret the mapping as failed solely because local `PortName`, `WorkOffline`, CIM, RPC, SMB, or remote `Get-Printer` telemetry looks contradictory. Preserve that lower-ranked telemetry as diagnostic context unless a later observed print failure reopens the incident.
13. `Repair-NorthwellPrinter-Queue-Evidence.cmd` is **artifact reclassification only**. Use it only when preserved local JSON explicitly records `physical_output_observed=true` and the derived classifier is wrong. Do not use it merely because a real requested document already printed successfully.
14. On failure, direct diagnosis to the run-scoped evidence. Quick runs use `ResolvedPlan.json`, `Controller.log`, per-target `Status.json`/`Agent.log`, and `Summary.json`; batch runs add parent `BatchPlan.json`, parent `Summary.json`, and `Group-NNN` child engine evidence.

## Workflow

1. Identify the field user, organization, site/hospital when relevant, target environment, and mutation posture.
2. For printer mapping, resolve the registered organization/site use case before selecting any launcher or implementation.
3. Reconcile the current repository floor before reusing any branch, SHA, worktree, or next-command from a prior chat/handoff.
4. Prefer an existing launcher, profile, menu, or wrapper.
5. Reduce the technician action to one short entrypoint when practical.
6. Put target validation, elevation, retries, teardown, progress, evidence, and classification inside the repo-owned workflow.
7. For software-install results, use `Inspect-LatestSoftwareInstall.cmd` as the field front door. Agents invoke `scripts/Show-SasSoftwareInstallResult.ps1` immediately after the install, when recovering an interrupted run, and before saying deployment succeeded.
8. Keep developer diagnostics separate from the field front door.
9. Provide a dry-run or review mode before mutation when the operation supports it.
10. Validate the launcher contract and the delegated workflow separately.

## Guardrails

- Do not require technicians to memorize run IDs or reconstruct long commands when state can be stored locally and safely.
- Do not hide scope, mutation, or failure classifications.
- A launcher ACK is not proof that the intended behavior occurred.
- Installer completion is not package-level post-install acceptance; present the remaining verification gate.
- For merged registered capsules, do not emit historical PR branches or pinned SHAs as normal operator retry sources.
- For printer mapping, do not select an implementation until the organization/site use case is registered and proven.
- Never use one organization's printer-mapping rules as another organization's defaults.
- For Northwell printer mapping, direct-IP installation and per-user-only mapping are blocking contract violations, not fallbacks.
- For Northwell batch mapping, never commit `mapping\NorthwellPrinterBatch.csv`; it is local live assignment data. Only the `.example.csv` template is tracked.
- For Northwell printer diagnosis, successful real-world document output after canonical mapping outranks contradictory diagnostic telemetry. Do not turn a proven working mapping into a repair target solely to make lower-level telemetry look cleaner.
