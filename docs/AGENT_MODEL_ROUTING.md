# Agent and model routing

SysAdminSuite delegates agent/model selection to AgentSwitchboard rather than duplicating provider logic. The tracked SysAdminSuite sample records the integration contract and safety posture; the installed AgentSwitchboard `model-route-policy.json` is the executable authority.

## Priority

The route order is:

1. OpenCode limited-time free routes first;
2. other free routes, including AGY/Anti-Gravity free DeepSeek, Gemini CLI/API profiles, and Goose free-provider profiles;
3. paid fallback routes, including direct DeepSeek V4 Flash, Codex/OpenAI, Claude Code, GitHub Copilot CLI, and future Augment Code adapters.

A route must be both available and GNHF-compatible. Command presence or a simple model response is not enough when the actual GNHF adapter uses a different session or output contract.

## Install AgentSwitchboard routing

From the AgentSwitchboard repository:

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Install-AgentModelRouter.ps1
```

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

## DeepSeek free GNHF route

The observed OpenCode Zen free DeepSeek route responds to ordinary OpenCode calls but has returned HTTP 400 for the structured OpenCode session request used by GNHF. It remains first priority in policy but requires a green route-compatibility proof before automatic GNHF selection.

AGY is the current free DeepSeek GNHF path when `agy acp --help` succeeds and AGY's own model picker is configured to its free DeepSeek model. AgentSwitchboard invokes it as `acp:agy acp`; AGY owns its provider login and model state.

## Pricing schedule

The current official DeepSeek pricing page lists flat per-token prices and no active time-of-day multiplier. SysAdminSuite therefore records `mode: flat` and an empty UTC-window list. The earlier operator-supplied peak windows are not enforced as official pricing facts.

Both repositories support a future verified time-window policy. Add windows only in the operator-local AgentSwitchboard policy after confirming the current official provider page and recording the source and verification time. Heavy paid work may then be deferred unless an explicit peak-price override is supplied.

## Proof ceiling

The tracked policy and contract tests prove ordering, delegation, safety boundaries, and schedule posture. They do not prove provider authentication, free quota, paid balance, model quality, or successful GNHF execution on a specific route.
