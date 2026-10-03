# Operator Recipes

SysAdminSuite is the canonical home for recurring workstation commands that are useful enough to keep.

## Contract

A useful command graduates from chat or clipboard history into a tracked **operator recipe**:

1. Put executable behavior in a tracked `.cmd`, `.ps1`, `.sh`, or other repo-owned entrypoint.
2. Put technician instructions beside it in a tracked runbook.
3. Register discoverability metadata in `Config/operator-recipes.json`.
4. Point the registry at tests or validators that prove the recipe still exists and retains its safety contract.
5. Keep runtime evidence under ignored local output. Do not commit workstation logs, clipboard contents, secrets, or machine-local state.

The registry deliberately does **not** embed command bodies. That prevents a copied command in documentation or metadata from drifting away from the executable source of truth.

## Lifecycle

- `active`: supported and discoverable.
- `archived`: retained for history, but no longer the recommended entrypoint.

When a recipe is replaced, preserve the old registry entry as `archived` and document its replacement instead of silently deleting operational history.

## Current recipes

| Recipe | Purpose | Entrypoint | Runbook |
|---|---|---|---|
| `windows.clipboard.repair` | Capture lightweight evidence, restart the current user's Clipboard User Service, clear the clipboard, and prove a write/read round trip. | `Repair-Clipboard.cmd` | `START-HERE-CLIPBOARD-RECOVERY.md` |

## Validation

```text
python Tests/survey/test_operator_recipe_registry_contracts.py
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Tests\clipboard\Test-ClipboardRecoveryContracts.ps1
```

The clipboard contract test is static: it does not restart services or mutate the CI runner clipboard. A real recovery claim still requires a live interactive Windows run.
