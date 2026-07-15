# Persistent developer workstation fixture E2E readiness

The `developer-workstation-persistent-e2e-v2` profile contains 22 required journeys for the WezTerm → tmux architecture. A full Windows coordination run completed **22 / 22** journeys with valid artifacts and idempotent reruns.

Covered behavior includes Windows WSL and native Linux success, PowerShell fallback, missing/invalid backend states, keepalive ownership, tmux lifecycle, simulated GUI close, nested-tmux refusal, CLI/GUI distinction, invalid Lua, optional font handling, native and bridge agents, alias rejection, authentication required, malformed AgentSwitchboard output, rollback, and unsupported macOS.

Every journey calls `scripts/Invoke-SasDeveloperWorkstation.py`, which is the public one-command core behind the PowerShell, Bash, and CMD front doors. Roots are disposable. AgentSwitchboard results are fixture-only; no provider is contacted and authentication is never attempted.

## Proof ceiling

This is composed fixture proof, not live persistence. The simulated GUI-close journey removes only fixture GUI ownership and confirms the simulated tmux state remains. It does not prove a real WezTerm process detached and reopened.

The following remain false in every proof artifact:

- live runtime;
- observed interactive behavior;
- observed persistence;
- observed agent interaction;
- operator acceptance.

A native Linux desktop with WezTerm is still required for native GUI proof. Windows live proof and operator acceptance are owned by Sprint 10. Therefore this lane is fixture-E2E ready but does not, by itself, authorize a runtime or release claim.
