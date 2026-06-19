# Bash QR runners (reserved)

This directory is reserved for **future Bash-first QR payload runners** on Windows (Git Bash / MSYS2).

PowerShell implementations remain in [`QRTasks/`](../../QRTasks/) until parity runners exist here.

Policy and GUI workflow: [`docs/QR_GUI_AND_RUNNER_POLICY.md`](../../docs/QR_GUI_AND_RUNNER_POLICY.md).

## Planned runners (not implemented yet)

- `sas-qr-ram-profile.sh`
- `sas-qr-model-info.sh`
- `sas-qr-network-info.sh`
- `sas-qr-serials.sh`

Each script should write plain-text output suitable for QR encoding and follow the Bash-on-Windows runtime contract in [`AGENTS.md`](../../AGENTS.md).
