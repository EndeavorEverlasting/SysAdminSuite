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
