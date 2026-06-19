# QR GUI and Runner Policy

## Purpose

SysAdminSuite supports two related QR workflows:

1. **Scan-to-run** — a QR encodes a short launcher string that invokes a local diagnostic task.
2. **Offline QR generation** — a QR encodes plain text or a command payload for technicians to scan and paste.

Both workflows are available in the WinForms GUI. PowerShell implementations are **preserved legacy**. Northwell-targeted development should move toward **Bash-first** or neutral compiled hosts over time.

## PowerShell legacy posture

| Component | Status |
|-----------|--------|
| `GUI/Start-SysAdminSuiteGui.ps1` — **QR Generator** tab | Acceptable in PowerShell-enabled environments. Deprecated for Northwell-targeted workflows. |
| `GUI/Start-SysAdminSuiteGui.ps1` — Machine Info QR modes | Preserved for backward compatibility |
| `QRTasks/*.ps1` | Preserved until Bash QR runners exist |

Labeling standard (from [`POWERSHELL_LEGACY_POLICY.md`](POWERSHELL_LEGACY_POLICY.md)):

> Acceptable in PowerShell-enabled environments. Deprecated for Northwell-targeted workflows. Prefer Bash QR runners for new Northwell development.

## QRTasks design

[`QRTasks/Invoke-TechTask.ps1`](../QRTasks/Invoke-TechTask.ps1) is the central dispatcher. Design principle: **QR = pointer, not payload**.

- Keep encoded strings short and scannable (target under ~120 characters for field labels when possible).
- The GUI **QR Generator** tab builds preview strings like:

  ```text
  powershell.exe -NoProfile -File "<repo>\QRTasks\Invoke-TechTask.ps1" -Task RAMProfile
  ```

- Do **not** use `Invoke-Expression`, `iex`, `-EncodedCommand`, download tricks, or `-ExecutionPolicy Bypass` in new GUI-generated payloads.

Historical README examples may still show `-EP Bypass` for permissive lab environments. Treat those as legacy field deployment patterns, not the Northwell-forward default.

## GUI workflow (QR Generator tab)

1. Launch SysAdminSuite GUI (`Launch-SysAdminSuite.bat`).
2. Open the **QR Generator** tab.
3. Choose **Ad Hoc Text / Command Payload** or a registered **QR Task** from the picker (sourced from `$TaskMap` in `Invoke-TechTask.ps1`).
4. Review the **exact payload preview** (read-only).
5. Click **Generate QR** — writes UTF-8 `.txt` and `.png` under `GetInfo/Output/QRGenerator/` (or a chosen path).
6. Click **Show Large QR** for a modal, high-resolution scannable display with Copy Payload and Save PNG.

Status text after generation:

```text
QR generated locally. Scan to paste selected payload.
```

Payloads longer than 2000 characters are truncated for scannability; the GUI shows a visible warning.

## Machine Info tab (legacy path)

Machine Info still exposes:

- **QR Task Runner** — run a task locally and view inline QR
- **QR Text Generator** — ad hoc text from the Targets box

These modes remain for operators who already use them. New documentation and tutorials should prefer the **QR Generator** tab.

## Bash-forward migration (TODO)

Future Northwell work should add Bash equivalents under [`bash/qr/`](../bash/qr/README.md):

| QR Task (PowerShell) | Planned Bash runner |
|----------------------|---------------------|
| RAMProfile | `bash/qr/sas-qr-ram-profile.sh` (placeholder) |
| ModelInfo | `bash/qr/sas-qr-model-info.sh` (placeholder) |
| NetworkInfo | `bash/qr/sas-qr-network-info.sh` (placeholder) |
| Serials | `bash/qr/sas-qr-serials.sh` (placeholder) |

Until runners exist:

- Keep `QRTasks/*.ps1` intact.
- GUI may list PowerShell launch strings in preview for permissive sites.
- A compiled dashboard host or neutral launcher may wrap the same plain-text payloads later ([`V3_NEXT_MILESTONE.md`](V3_NEXT_MILESTONE.md) defers engine-aware QR beyond PowerShell until a host exists).

## Payload safety

QR payloads must be **plain text commands or data**, not execution bypass mechanisms.

Forbidden in new SysAdminSuite QR generation paths:

- `Invoke-Expression` / `iex`
- `-EncodedCommand`
- Remote download / `IWR` one-liners embedded in QR
- `-ExecutionPolicy Bypass` in GUI-built templates

## Testing

- Pester: [`Tests/Pester/Gui.Tests.ps1`](../Tests/Pester/Gui.Tests.ps1) — dedicated QR Generator tab contracts
- Manual WAB smoke: generate ad hoc QR + one task QR; open large modal; verify `.txt` and `.png` under `GetInfo/Output/QRGenerator/`

## Output paths

| Artifact | Default path |
|----------|----------------|
| Ad hoc payload `.txt` | `GetInfo/Output/QRGenerator/QRGenerator_Output.txt` |
| Ad hoc payload `.png` | `GetInfo/Output/QRGenerator/QRGenerator_Output.png` |
| Task payload `.txt` | `GetInfo/Output/QRGenerator/QRTask_<TaskName>_Output.txt` |
| Task payload `.png` | `GetInfo/Output/QRGenerator/QRTask_<TaskName>_Output.png` |
| QR task run output (Machine Info runner) | `GetInfo/Output/QRTasks/` |

Generated artifacts may contain host-identifying data. Do not commit them to the public repo.
