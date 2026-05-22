# BRANCH HARVEST

## Harvest from `main`
- Consolidated v2.0 repository posture and current domain separation.
- QR task dispatcher safeguards currently present in `QRTasks/Invoke-TechTask.ps1`:
  - task timeout controls (`-TaskTimeoutSec`, `-DisableTaskTimeout`)
  - interruption cleanup handling for running jobs
  - broad task registry including `NeuronTrace`
- Existing test-oriented workflow under `Tests/Pester`.
- Current launch posture with `Launch-SysAdminSuite.bat`.

## Harvest from `experimental/qrtasks-safe-defaults`
- Fallback script-root resolution logic for QR dispatch when the primary path is unavailable.
- Local-first resilience behavior that allows task execution without guaranteed central share availability.

## No Unique Harvest Needed
- `unit-tests/repo-health-and-bom-compliance`
- `demo/v2.1`
- `consolidate/v2.0`

## Implementation Guardrails
- Keep QR as pointer, not payload.
- Preserve timeout/interruption safety from `main`.
- Add structured logging of selected script root and fallback reason.

---

## Harvest from PR9 Bash-on-Windows runtime contract

### Purpose

Preserve the PR9 product-harvest analysis so terminal refreshes do not erase repo recovery context.

### Harvest lane

- Source repo: `/home/runner/workspace`
- Harvest worktree: `/home/runner/sysadminsuite-product-harvest`
- Harvest branch: `forensics/sysadminsuite-product-harvest-v1`
- Base ref: `origin/main`
- Base commit: `e68160b`
- PR9 ref: `origin/pr/9`
- PR9 commit: `7519501`

### PR9 target files inspected

- `AGENTS.md`
- `docs/AI_RUNTIME_CONTRACT.md`
- `docs/COMMAND_CATALOG.md`
- `survey/README.md`
- `survey/sas-device-snapshot.sh`
- `survey/sas-neuron-environment.sh`
- `tests/bash/smoke-bash-windows-runtime.sh`

### Harvest decision

- `AGENTS.md` from PR9 was not accepted as-is.
- Reason: the staged PR9 diff removed the existing language hierarchy and PowerShell protection doctrine.
- Existing doctrine must continue to state that PowerShell scripts are active production-relevant tooling.
- Bash-on-Windows direction is valid, but it must not collapse Windows/PowerShell tooling or pretend Bash means Linux.
- Other PR9 target files produced no visible staged product delta from `origin/main` in this harvest attempt.

### Runtime doctrine

- This lane is Bash-on-Windows field tooling.
- Do not treat Bash as Linux.
- Target runtime is usually Git Bash or MSYS2 on Windows.
- Replit/Linux smoke failures caused by missing Windows executables are environment mismatch, not product failure.
- Do not collapse the runtime doctrine into Linux defaults.
- Do not delete or deprecate PowerShell files as part of this harvest.

### Doctrine grep interpretation

Grep hits are review signals only. Forbidden Linux examples inside documentation can be valid when clearly listed as forbidden defaults.

Doctrine grep hits recorded during harvest:

    AGENTS.md:81:ip addr
    AGENTS.md:82:ifconfig
    AGENTS.md:83:nmcli dev show
    AGENTS.md:84:systemctl status
    AGENTS.md:85:journalctl
    AGENTS.md:86:lsusb
    AGENTS.md:87:lspci
    docs/AI_RUNTIME_CONTRACT.md:70:ip addr
    docs/AI_RUNTIME_CONTRACT.md:71:ifconfig
    docs/AI_RUNTIME_CONTRACT.md:72:nmcli dev show
    docs/AI_RUNTIME_CONTRACT.md:73:systemctl status
    docs/AI_RUNTIME_CONTRACT.md:74:journalctl
    docs/AI_RUNTIME_CONTRACT.md:75:lsusb
    docs/AI_RUNTIME_CONTRACT.md:76:lspci
    docs/COMMAND_CATALOG.md:142:ip addr
    docs/COMMAND_CATALOG.md:143:ifconfig
    docs/COMMAND_CATALOG.md:144:nmcli dev show
    docs/COMMAND_CATALOG.md:145:systemctl status
    docs/COMMAND_CATALOG.md:146:journalctl

### Smoke test interpretation

The smoke test was run in Replit/Linux, not the target Bash-on-Windows runtime.

Smoke log:

    ======================================
     SysAdminSuite Bash-on-Windows Smoke Test
    ======================================
    
    PASS: bash
    FAIL: cmd.exe not found
    FAIL: hostname.exe not found
    FAIL: ping.exe not found
    FAIL: nslookup.exe not found
    PASS: tee
    PASS: date
    PASS: tr
    
    Smoke test failed. Missing command count: 4
    Expected runtime: Bash on Windows, usually Git Bash or MSYS2 Bash.

### Standing interpretation

- Missing `cmd.exe`, `hostname.exe`, `ping.exe`, or `nslookup.exe` in Replit is expected runtime mismatch.
- Do not treat that smoke result as a product failure.
- Do not overfit the tooling to Replit/Linux.
- Commit only deliberate harvest documentation unless a future PR9 file is reviewed and accepted intentionally.
