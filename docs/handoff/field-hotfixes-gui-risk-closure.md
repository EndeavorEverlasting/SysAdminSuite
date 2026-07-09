# Field Hotfixes GUI Risk Closure

## Context

The Cybernet setup-completion hotfix is still available through the dedicated Field Hotfixes launcher:

```cmd
Run-FieldHotfixesGui.cmd
```

This path keeps the confirmed Shift+F10/CMD QR workflow available without restructuring the existing all-in-one GUI.

## Decision

Do not keep the temporary `Start-SysAdminSuiteGui.ps1` wrapper/core split.

The wrapper pattern created a generated runtime GUI file and moved the original all-in-one GUI body into a `.Core.ps1` file. That made the field-hotfix tab injection possible from a connector-only session, but it added too much mechanical risk to the primary operator GUI.

## Current Operator Path

1. Open `Run-FieldHotfixesGui.cmd` on the admin box.
2. Select the CMD Shift+F10 payload.
3. Stand in front of the Cybernet showing the Windows setup error.
4. Press `Shift+F10` to open Command Prompt.
5. Scan the QR code into CMD.
6. Press Enter if the scanner does not submit automatically.
7. Let the device restart and continue post-install.

## Boundaries

- No silent remote execution.
- No target mutation from the admin GUI.
- No USB/COM repair in this lane.
- No final app install or SmartLynx app-binding work.
- Keep the all-in-one GUI mechanically stable unless a local Windows validation sprint can patch and test it directly.

## Follow-up

A later local Windows sprint may add the Field Hotfixes tab directly to `GUI/Start-SysAdminSuiteGui.ps1`, but only with a checked-out repo, PowerShell parser validation, and GUI smoke launch evidence.
