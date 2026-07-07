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
scripts/Invoke-WindowsLogClassifier.ps1
Tests/survey/test_windows_log_classification_contracts.py
Tests/survey/test_windows_log_classifier_code.py
```

The Markdown explains the doctrine. The taxonomy is the machine-readable contract. The classifier is the executable implementation that loads the taxonomy, classifies a request, builds an operation plan, and renders an operator-visible PowerShell handoff without executing host log actions. The PowerShell wrapper gives Windows operators a repo-standard entrypoint into that classifier while keeping host log action execution outside the wrapper. The schema and tests keep the taxonomy usable by scripts, MCP tools, and dashboard surfaces.

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

Windows PowerShell wrapper:

```powershell
.\scripts\Invoke-WindowsLogClassifier.ps1 `
  -Target System `
  -Operation 'show recent errors' `
  -Emit plan
```

## Acceptance criteria

This system is ready for scripts when:

1. The taxonomy lists every supported family, operation class, and safety tier.
2. Mutating operations are explicitly represented rather than hand-waved away.
3. Every destructive operation declares whether backup is required.
4. Every classifier result declares `host_log_mutation`.
5. MCP/API surfaces expose classification and rendering but do not silently execute host mutation.
6. Static tests prove the doc, taxonomy, API manifest, MCP catalog, implementation, and PowerShell wrapper stay connected.
7. Executable tests prove the classifier can load the taxonomy, classify common requests, build operation plans, and render handoffs without executing host actions.
