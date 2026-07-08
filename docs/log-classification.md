# Render-Only Log Classification

The deployment log classifier is render-only. It may explain which log classes matter for human review, but it must not query live target logs.

Configured classes are in `config/log-classification.json` and include deployment-owned logs, installer logs, Windows Application/System/Security, PowerShell Operational, WinRM, security product/EDR, file share/network access, and audit-integrity events.

Forbidden from this sprint: live `Get-WinEvent` against target hosts, host log export, clearing logs, deleting logs, mutating logs, disabling logging, suppressing audit trails, and security-tool bypass.
