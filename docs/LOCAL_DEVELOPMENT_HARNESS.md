# Local Development Harness

The harness is the local control layer that keeps SysAdminSuite development natural, repeatable, and bounded.

It has four jobs:

1. Install repo hooks that run the same local contracts developers rely on before commits and pushes.
2. Define stable local APIs so scripts, dashboards, and MCP servers do not invent their own command shapes.
3. Catalog local MCP servers that expose repo capabilities without bypassing guardrails.
4. Make reports emerge from local artifacts instead of ad hoc explanation after the fact.

This harness is for authorized local development and approved operator workflows. It must not introduce hidden network activity, persistent target-side artifacts, credential collection, log suppression, or monitoring bypass behavior.

## Harness layers

| Layer | Path | Purpose |
| --- | --- | --- |
| Hooks | `.githooks/` | Run local checks before commit and push. |
| Installer | `scripts/install-local-harness-hooks.sh` | Sets `core.hooksPath` to `.githooks`. |
| API manifest | `harness/api/sas-harness-api.json` | Defines stable local operation names, inputs, outputs, and safety modes. |
| MCP catalog | `mcp/local/servers.json` | Lists local-only MCP servers and the APIs they may expose. |
| Contracts | `Tests/survey/test_local_harness_contracts.py` | Keeps hooks, APIs, MCP, and reporting guardrails connected in CI. |

## Required hook behavior

### pre-commit

The pre-commit hook is a fast local guard. It should:

- run harness, socket-boundary, standard tooling, and software-install static contracts;
- block staged generated evidence paths;
- block accidental commit of live operational files such as generated probe outputs, serial evidence, host/IP/MAC exports, or local MCP runtime logs;
- stay local-only and avoid network actions.

### pre-push

The pre-push hook is the heavier guard. It should:

- run the offline survey test runner;
- run the harness contract directly;
- avoid network probes;
- leave generated reports and evidence in gitignored local paths.

Developers can install the hooks with:

```bash
bash scripts/install-local-harness-hooks.sh
```

## API posture

Harness APIs are operation contracts, not remote services by default.

Every API operation must declare:

- `id`
- `summary`
- `mode`
- `network_activity`
- `target_mutation`
- `inputs`
- `outputs`
- `guardrails`

Approved modes:

| Mode | Meaning |
| --- | --- |
| `plan_only` | Produces commands, plans, or classifications. Does not execute probes. |
| `local_read` | Reads local artifacts only. |
| `local_transform` | Converts local evidence into reports or reduced target lists. |
| `operator_execute` | May execute only through an approved wrapper and must be separately gated. |

The default harness APIs are deliberately plan-only or local-transform:

- `target_reduction.plan`
- `standard_probe.render_cmd`
- `standard_probe.render_powershell`
- `report.generate_from_artifacts`
- `mcp.catalog.list`

The software install lane is intentionally different. `software_install.operator_execute` is an approved operator-execute surface because installing software mutates authorized targets. It must be gated by explicit operator intent, approved source roots, bounded target lists, local evidence, and cleanup reporting. It must not suppress Windows logs, bypass monitoring, collect credentials, or create persistence.

## Software install posture

The approved software source root is:

```text
\\nt2kwb972sms01\
```

Software install work should prefer direct UNC execution from the read-only source so SysAdminSuite does not stage installer payloads on the target. If staging is required, the wrapper must stage only under a run-specific `ProgramData\SysAdminSuite\SoftwareInstall\<run_id>` folder, remove that run folder after execution, and prune empty `ProgramData\SysAdminSuite\SoftwareInstall` and `ProgramData\SysAdminSuite` parent directories when no sibling run artifacts remain.

The no-artifact boundary means no persistent SysAdminSuite-owned staging payload, log, report, manifest, transcript, script, or evidence should remain on the target. Installer-owned files, installer logs, registry changes, caches, services, and endpoint-management records belong to the software install itself. SysAdminSuite does not erase operating-system audit logs; it avoids and cleans its own target filesystem remnants.

See `docs/SOFTWARE_INSTALL_HARNESS.md` and `scripts/Invoke-SasSoftwareInstall.ps1` for the concrete contract.

## Local MCP posture

Local MCP servers must be boring by default.

They may:

- read repo docs and local artifact metadata;
- render CMD/PowerShell command plans;
- classify prior probe results into reduced/retry/review queues;
- generate reports from local artifacts;
- explain guardrail failures.

They must not:

- probe the network directly;
- mutate targets;
- collect credentials;
- write artifacts to target hosts;
- bypass repo hooks or CI checks;
- introduce hidden listeners or background daemons.

Any future MCP server that executes network activity must be treated as an `operator_execute` surface, added to the harness API manifest, documented, and covered by a CI contract before use.

## Reporting rule

Reports should be derived from local artifacts with a clear chain:

```text
input artifact(s) -> classifier/transform -> report output -> summary metadata
```

A report should say what it consumed, what it excluded, what it classified, and what remains unresolved. It should not invent certainty. Reached is not identity proof. Non-reached is not dead.

## Next sprint seam

The next implementation sprint should add a local target-reduction planner that consumes prior probe results and produces:

```text
reduced_targets.csv
retry_candidates.csv
review_required.csv
location_subnet_candidates.csv
target_reduction_summary.json
```

That planner should implement the API operation `target_reduction.plan` and stay plan-only/local-transform before any new probe execution is introduced.
