# Windows Log Classification System

## Purpose

SysAdminSuite needs a stable way to reason about Windows logs before an agent or script decides what to read, add, clear, delete, export, archive, or reconfigure.

The goal is not to flatten all logs into one bucket. The goal is to classify each log surface by:

```text
log family
  -> storage/provider model
  -> supported operations
  -> privilege needs
  -> sensitivity
  -> mutation/destruction risk
  -> required operator gate
  -> safe command-rendering pattern
```

This lets a script inspect a request such as "clear old Application log entries after backing them up" and route it differently from "read recent System errors" or "enable a high-volume analytic channel."

## Source-of-truth artifacts

```text
docs/WINDOWS_LOG_CLASSIFICATION_SYSTEM.md
harness/taxonomy/windows-log-taxonomy.json
schemas/harness/windows-log-taxonomy.schema.json
harness/windows_log_classifier.py
Tests/survey/test_windows_log_classification_contracts.py
Tests/survey/test_windows_log_classifier_code.py
```

The Markdown explains the doctrine. The taxonomy is the machine-readable contract. The classifier is the executable implementation that loads the taxonomy, classifies a request, builds an operation plan, and renders an operator-visible PowerShell handoff without executing host log actions. The schema and tests keep the taxonomy usable by scripts, MCP tools, and dashboard surfaces.

## Classification dimensions

Every Windows log target should be classified with these dimensions before an action is rendered or executed.

| Dimension | Meaning |
| --- | --- |
| `family` | The kind of logging surface, such as classic Event Log, provider channel, ETW trace, plain text log, or servicing log. |
| `scope` | Whether the target is local host, remote host, exported file, repository fixture, or generated local artifact. |
| `read_surface` | The normal safe reader, such as `Get-WinEvent`, `wevtutil qe`, or plain file parsing. |
| `write_surface` | The supported append/configuration surface, if any. |
| `operation_class` | The action being requested: read, append, export, clear, delete registration, configure retention, enable/disable, archive, or file deletion. |
| `safety_tier` | A normalized risk level used by agents before rendering commands. |
| `requires_admin` | Whether the action normally needs elevated rights. |
| `contains_sensitive_data` | Whether the records may include security, identity, endpoint, hostname, user, credential-adjacent, or client data. |
| `mutation_effect` | Whether the action changes no state, appends records, changes configuration, deletes records, or removes registration. |
| `required_gate` | The minimum human/operator gate before execution. |
| `backup_required` | Whether export/backup must happen before the operation. |
| `tracked_output_allowed` | Whether resulting artifacts may be committed. Live logs and EVTX/ETL exports should remain local/gitignored. |

## Log families

| Family | Examples | Primary reader | Notes |
| --- | --- | --- | --- |
| `eventlog_classic` | `Application`, `System`, `Setup` | `Get-WinEvent`, `wevtutil qe` | Structured EVTX logs with stable classic channels. |
| `eventlog_security` | `Security` | `Get-WinEvent`, Event Viewer | Security-sensitive. Reads and clears require extra caution and usually elevation. |
| `eventlog_provider_channel` | `Microsoft-Windows-PowerShell/Operational`, `Microsoft-Windows-TaskScheduler/Operational` | `Get-WinEvent`, `wevtutil qe` | Provider-specific channels under Applications and Services Logs. |
| `eventlog_forwarded` | `ForwardedEvents` | `Get-WinEvent`, `wevtutil qe` | Aggregated events; identity of source computer matters. |
| `etw_trace` | `.etl`, WPR/WPA traces, live ETW sessions | `Get-WinEvent -Path`, `tracerpt`, WPR/WPA | High-volume diagnostic traces. Often performance/debug oriented. |
| `setup_servicing_log` | CBS, DISM, Panther, WindowsUpdate logs | Text parser, vendor tooling | Often plain text or generated diagnostic artifacts. |
| `application_text_log` | Vendor logs under `ProgramData`, app folders, temp folders | Text/JSON parser | No uniform event schema. Rotation/deletion rules are app-specific. |
| `repository_fixture_log` | Synthetic `.json`, `.csv`, `.md`, or sample log fixtures | Local parser | Safe for tests only when scrubbed and synthetic. |

## Operation classes

| Operation class | Mutation effect | Safety tier | Default posture |
| --- | --- | --- | --- |
| `inventory` | none | `S0_READ_ONLY` | Allowed for local metadata only. |
| `read_query` | none | `S0_READ_ONLY` | Allowed when scoped and time-bounded. |
| `export_copy` | creates local artifact | `S1_EXPORT_LOCAL` | Allowed when output stays local/gitignored and sensitive data is marked. |
| `archive_copy` | creates self-contained archive | `S1_EXPORT_LOCAL` | Allowed when output stays local/gitignored. |
| `append_event` | appends new records | `S2_APPEND` | Requires source/provider validation and operator acknowledgement. |
| `register_source` | adds source/provider/log registration | `S3_CONFIG_CHANGE` | Requires admin gate and rollback note. |
| `install_manifest` | adds providers/channels from manifest | `S3_CONFIG_CHANGE` | Requires manifest path, admin gate, and uninstall plan. |
| `set_configuration` | changes retention, size, enablement, path, filters, or ACL | `S3_CONFIG_CHANGE` | Requires before/after config export and operator approval. |
| `enable_high_volume_channel` | changes channel enablement or verbosity | `S3_CONFIG_CHANGE` | Requires duration/rollback to avoid noisy or huge logs. |
| `clear_with_backup` | deletes records after backup | `S4_DESTRUCTIVE_BACKED_UP` | Requires backup path, authorization reason, and post-check. |
| `clear_without_backup` | deletes records without preserving copy | `S5_DESTRUCTIVE_UNBACKED` | Deny by default except break-glass. |
| `delete_source_registration` | removes source/log registration | `S4_DESTRUCTIVE_CONFIG` | Requires dependency review and rollback plan. |
| `uninstall_manifest` | removes providers/channels registered by manifest | `S4_DESTRUCTIVE_CONFIG` | Requires manifest ownership proof and rollback plan. |
| `delete_log_file` | deletes a file-backed log | `S5_DESTRUCTIVE_UNBACKED` | Deny by default for live Windows log paths. |
| `tamper_history` | edits past records to falsify history | `S5_DISALLOWED` | Disallowed. Preserve evidence; do not rewrite history. |

## Safety tiers

| Tier | Meaning | Minimum gate |
| --- | --- | --- |
| `S0_READ_ONLY` | Reads metadata or events without changing host state. | Scope/time window must be explicit. |
| `S1_EXPORT_LOCAL` | Copies events or logs into a local artifact. | Output path must be local/gitignored and sensitivity marked. |
| `S2_APPEND` | Adds new events without deleting old records. | Operator acknowledgement and approved source/provider. |
| `S3_CONFIG_CHANGE` | Changes logging configuration. | Admin gate, before/after config capture, rollback note. |
| `S4_DESTRUCTIVE_BACKED_UP` | Removes records or registrations after backup/review. | Explicit authorization, backup/export, reason, and post-check. |
| `S5_DESTRUCTIVE_UNBACKED` | Deletes or clears without backup, or touches sensitive logs without preservation. | Deny by default; break-glass only. |
| `S5_DISALLOWED` | Falsifies, suppresses, bypasses, or hides evidence. | Refuse and route to legitimate export/retention workflow. |

## Agent/script routing rule

Agents should resolve a log request in this order:

```text
1. identify target
2. classify log family
3. classify operation class
4. assign safety tier
5. check required privileges and gates
6. render a bounded command plan
7. require explicit operator execution for S2+
8. write local summary/report artifacts
9. preserve uncertainty and evidence paths
```

For example:

```text
"Show recent System errors"
  -> family: eventlog_classic
  -> operation_class: read_query
  -> safety_tier: S0_READ_ONLY
  -> render: Get-WinEvent with LogName/System, Level/Error, StartTime
```

```text
"Clear Application after backing it up"
  -> family: eventlog_classic
  -> operation_class: clear_with_backup
  -> safety_tier: S4_DESTRUCTIVE_BACKED_UP
  -> render: wevtutil cl Application /bu:<local-gitignored-backup.evtx>
  -> gate: explicit operator authorization
```

```text
"Delete the Security log"
  -> family: eventlog_security
  -> operation_class: clear_without_backup or delete_log_file
  -> safety_tier: S5_DESTRUCTIVE_UNBACKED
  -> default: deny and offer export/retention/reporting alternative
```

## Mutating operations are in scope

Mutation is not ignored. It is classified.

The classifier must distinguish:

```text
append_event
set_configuration
register_source
install_manifest
clear_with_backup
clear_without_backup
delete_source_registration
uninstall_manifest
delete_log_file
tamper_history
```

The harness boundary is that mutation-capable requests must not be silently executed by a planner, renderer, dashboard, or MCP tool. The correct behavior is to classify the operation, name the mutation effect, render an operator-visible plan when allowed, and require the gate declared by the taxonomy.

## Required output fields for a classifier

A classifier result should include:

```json
{
  "target": "System",
  "family": "eventlog_classic",
  "operation_class": "read_query",
  "safety_tier": "S0_READ_ONLY",
  "mutation_effect": "none",
  "network_activity": false,
  "host_log_mutation": false,
  "requires_admin": false,
  "contains_sensitive_data": true,
  "required_gate": "scope_time_window",
  "backup_required": false,
  "tracked_output_allowed": false,
  "recommended_reader": "Get-WinEvent",
  "recommended_command_surface": "powershell",
  "notes": [
    "Use provider and event id together.",
    "Preserve uncertainty; warnings are not automatically incidents."
  ]
}
```

## Command rendering posture

The implementation renders plans and commands; it does not execute them.

Approved renderer outputs:

```text
windows_log_inventory_plan.json
windows_log_operation_plan.json
windows_log_command_plan.ps1
windows_log_classification_report.md
```

Real EVTX, ETL, CBS, DISM, or vendor logs should remain outside tracked repo paths unless they are synthetic fixtures.

## CLI usage

```bash
python3 harness/windows_log_classifier.py \
  --target System \
  --operation "show recent errors" \
  --emit plan
```

To write local artifacts under an ignored output root:

```bash
python3 harness/windows_log_classifier.py \
  --target Application \
  --operation "write event" \
  --output-root survey/output/windows-log-classifier/demo \
  --emit all \
  --write
```

## Add/delete/mutate command families

The taxonomy deliberately models the following command families:

| Purpose | Example surface | Classifier treatment |
| --- | --- | --- |
| Read events | `Get-WinEvent`, `wevtutil qe` | `S0_READ_ONLY` when bounded. |
| List logs/providers | `Get-WinEvent -ListLog`, `wevtutil el`, `wevtutil ep` | `S0_READ_ONLY`. |
| Export before review | `wevtutil epl` | `S1_EXPORT_LOCAL`; output must stay local/gitignored. |
| Archive exported log | `wevtutil al` | `S1_EXPORT_LOCAL`. |
| Add a classic source | `New-EventLog` | `S3_CONFIG_CHANGE`. |
| Append custom event | `Write-EventLog`, `eventcreate` | `S2_APPEND`. |
| Install provider manifest | `wevtutil im` | `S3_CONFIG_CHANGE`. |
| Change retention/size/enabled/path/ACL | `wevtutil sl` | `S3_CONFIG_CHANGE`. |
| Clear with backup | `wevtutil cl /bu:<path>` | `S4_DESTRUCTIVE_BACKED_UP`. |
| Clear without backup | `wevtutil cl` without `/bu` | `S5_DESTRUCTIVE_UNBACKED`; deny by default. |
| Remove classic source/log | `Remove-EventLog` | `S4_DESTRUCTIVE_CONFIG`. |
| Uninstall provider manifest | `wevtutil um` | `S4_DESTRUCTIVE_CONFIG`. |
| Delete live EVTX/ETL/text file | `Remove-Item` against live log path | `S5_DESTRUCTIVE_UNBACKED`; deny by default for live log roots. |

## Review buckets

Classifier outputs should route requests into these buckets:

| Bucket | Meaning |
| --- | --- |
| `safe_read_plan` | Bounded read/list command can be rendered. |
| `safe_export_plan` | Export/archive can be rendered to local ignored output. |
| `append_plan_requires_ack` | Appending a custom event/source is allowed only after acknowledgement. |
| `config_plan_requires_admin` | Configuration/register/unregister operations need elevation and rollback. |
| `destructive_plan_requires_backup_and_auth` | Clear/delete action requires backup and explicit authorization. |
| `deny_or_break_glass` | Unbacked clearing, live file deletion, tampering, stealth, or bypass request. |
| `needs_human_review` | Ambiguous target, unknown provider, unknown app log ownership, or sensitive scope. |

## Reference facts

- Microsoft documents `Get-WinEvent` as able to read classic event logs, newer Windows Event Log channels, and ETW log files, with filtering by log, provider, path, XPath, XML, or hash table.
- Microsoft documents `wevtutil` as a command for retrieving event log and publisher information, installing and uninstalling event manifests, querying events, exporting logs, archiving logs, clearing logs, and changing log configuration.
- Microsoft documents `wevtutil cl <Logname> /bu:<Backup>` as a clear operation that can save cleared events to a backup EVTX file.

Reference URLs:

```text
https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent
https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/wevtutil
```

## Acceptance criteria

This system is ready for scripts when:

1. The taxonomy lists every supported family, operation class, and safety tier.
2. Mutating operations are explicitly represented rather than hand-waved away.
3. Every destructive operation declares whether backup is required.
4. Every classifier result declares `host_log_mutation`.
5. MCP/API surfaces expose classification and rendering but do not silently execute host mutation.
6. Static tests prove the doc, taxonomy, API manifest, and MCP catalog stay connected.
7. Executable tests prove the classifier can load the taxonomy, classify common requests, build operation plans, and render handoffs without executing host actions.
