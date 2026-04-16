# Issue template: Unify QR dispatcher safety with current mainline capabilities

Use this as the body when opening a GitHub issue (title below).

**Title:** Unify QR dispatcher safety with current mainline capabilities

**Body:**

## Summary

Track follow-up work to keep QR task dispatch aligned with `main` behavior while preserving experimental fallback script-root resolution.

## Acceptance criteria

- Preserve `main` timeout and interruption model (`-TaskTimeoutSec`, `-DisableTaskTimeout`, trap cleanup).
- Preserve `main` task registry breadth (including `NeuronTrace`).
- Add and keep experimental fallback path resolution when the primary `ScriptRoot` or share is unreachable (`\\localhost\c$\Scripts\QRTasks`, `\\<COMPUTERNAME>\c$\Scripts\QRTasks`, local dispatcher).
- Log selected script root and fallback reason (already partially implemented in `QRTasks/Invoke-TechTask.ps1`).
- Keep QR as pointer, not payload (short launch strings; no embedded scripts).

## References

- `QRTasks/Invoke-TechTask.ps1`
- `docs/MIGRATION_LEDGER.md` (experimental branch notes)
- `Tests/Pester/QRTasks.Tests.ps1`
