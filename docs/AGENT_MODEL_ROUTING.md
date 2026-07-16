# Agent and model routing

SysAdminSuite delegates agent/model selection to AgentSwitchboard rather than duplicating provider logic. The tracked SysAdminSuite sample records the integration contract and safety posture; the installed AgentSwitchboard `model-route-policy.json` is the executable authority.

## Priority

The route order is:

1. AGY/Anti-Gravity's naturally free token pool;
2. OpenCode limited-time free routes;
3. other free routes, including Gemini CLI/API profiles and Goose free-provider profiles;
4. paid fallback routes, including direct DeepSeek V4 Flash, Codex/OpenAI, Claude Code, GitHub Copilot CLI, and future Augment Code adapters.

AGY is not permanently pinned to a model by SysAdminSuite or AgentSwitchboard. AGY owns its normal default allocation, which lets its naturally free tokens be consumed before another route is considered.

A route must be both available and GNHF-compatible. Command presence or a simple model response is not enough when the actual GNHF adapter uses a different session or output contract.

## Install AgentSwitchboard routing

From the AgentSwitchboard repository:

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Install-AgentModelRouter.ps1 -ResetPolicy
```

The one-time `-ResetPolicy` adopts the schema-v2 AGY-first order after creating a backup of the existing local policy. Later installer runs preserve local policy customizations unless reset is explicitly requested.

Plan from SysAdminSuite without launching an agent:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Invoke-SasAgentModelRoute.ps1 -Plan
```

Launch a bounded sprint from a clean repository:

```powershell
$Prompt = Get-Clipboard -Raw

pwsh -NoLogo -NoProfile -File .\scripts\Invoke-SasAgentModelRoute.ps1 `
  -LaunchWithPrompt `
  -RepoPath "C:\Users\Cheex\Desktop\dev\SysAdminSuite" `
  -Prompt $Prompt `
  -MaxIterations 2 `
  -MaxTokens 180000
```

The wrapper requires a clean Git worktree, never authenticates providers, never writes credentials, and does not push.

## AGY and Good Night, Have Fun

AGY 1.1.2 does not list an `acp` subcommand. `agy acp --help` prints top-level help and may exit successfully, so it must not be interpreted as ACP readiness.

AgentSwitchboard installs a Pi-compatible JSONL bridge and temporarily places its `pi.cmd` shim first on the routed GNHF child process's `PATH`. GNHF runs its native Pi adapter, while the shim translates the streamed GNHF prompt into an AGY one-shot coding request. It does not replace a real Pi command globally and does not edit the operator's GNHF configuration.

Verify AGY's current session without choosing a permanent model:

```powershell
agy --version
agy models
agy --mode plan --print "Return exactly this text and nothing else: AGY_FREE_READY"
```

The production bridge uses `accept-edits` for the bounded GNHF worktree. The read-only `plan` smoke above proves only that AGY can answer through its current default allocation.

## Exhaustion-only fallback

AgentSwitchboard switches away from AGY only when the bridge records the exact classification `quota-exhausted` and verifies that:

- the base repository is clean and its HEAD is unchanged;
- no new GNHF branch contains a commit;
- no new worktree remains for inspection.

Generic failures do not authorize fallback. Authentication problems, rate limiting, network faults, malformed output, test failures, and repository changes stop for review. This protects work already performed and preserves the purpose of maximizing every available token pool.

After confirmed AGY exhaustion, OpenCode's limited-time free route is next. The observed OpenCode Zen free DeepSeek route responds to ordinary OpenCode calls but returned HTTP 400 for the structured OpenCode session request used by GNHF. It therefore remains gated on a green route-compatibility proof.

## Pricing schedule

The current official DeepSeek pricing page lists flat per-token prices and no active time-of-day multiplier. SysAdminSuite therefore records `mode: flat` and an empty UTC-window list. The earlier operator-supplied peak windows are not enforced as official pricing facts.

Both repositories support a future verified time-window policy. Add windows only in the operator-local AgentSwitchboard policy after confirming the current official provider page and recording the source and verification time. Heavy paid work may then be deferred unless an explicit peak-price override is supplied.

## Proof ceiling

The tracked policy and contract tests prove ordering, delegation, safety boundaries, and schedule posture. They do not prove provider authentication, free quota, paid balance, AGY bridge runtime, model quality, or successful GNHF execution on a specific route.
