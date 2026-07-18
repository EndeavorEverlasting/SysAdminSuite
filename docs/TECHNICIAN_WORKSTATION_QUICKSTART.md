# Technician Workstation Quick-Start

Clone, configure WezTerm + tmux + agents, verify models, and start coding.

## One-command setup

```cmd
Developer-Workstation.cmd
```

This runs Plan → Apply → Start → Status. Details below.

## Step-by-step

### 1. Clone the repo

```cmd
git clone https://github.com/EndeavorEverlasting/SysAdminSuite.git
cd SysAdminSuite
```

### 2. Set up the workstation

```powershell
.\scripts\Install-SasWindowsTmuxWorkspace.ps1
.\scripts\Start-SasWindowsTmuxWorkspace.ps1 -LaunchGui
```

This installs the managed WezTerm config, creates a desktop shortcut, starts WSL tmux, and opens WezTerm.

### 3. Verify agents

```powershell
.\scripts\Show-SasActiveAgent.ps1
```

Shows all available agents (opencode, agy, goose), their backend resolution, and the active model/provider.

### 4. Model priority and provider setup

The provider catalog (`Config/ai-provider-catalog.json`) defines all known free and paid providers:

| Tier | Providers | Tokens |
|------|-----------|--------|
| Free local | Ollama | Unlimited, no key |
| Free cloud (free tokens) | GitHub Models, Google AI Studio, Groq, HuggingFace, Mistral, DeepSeek | Free quota |
| Free cloud (trial) | Cohere | Trial grant |
| Paid | OpenAI, Anthropic, Google Vertex, Amazon Bedrock | Billed |

**Fallback order:** free local → free cloud free tokens → free cloud trial → paid.

Set environment variables for the providers you use:

```powershell
$env:OPENCODE_CONFIG_CONTENT = '{"$schema":"https://opencode.ai/config.json","model":"opencode/deepseek-v4-flash-free"}'
```

### 5. Cast feedback votes

When an agent produces a contribution that needs to be undone or modified:

```powershell
.\scripts\Invoke-SasAgentFeedback.ps1 -AgentId opencode -ModelId deepseek-chat -ProviderId deepseek -Vote thumbs_down -Reason "Generated invalid config" -WorkContext "profile generation"
```

The orchestrator reads accumulated feedback and routes around flagged agents/models.

### 6. View feedback summary

```powershell
.\scripts\Show-SasAgentFeedbackSummary.ps1
```

Shows per-agent, per-model vote counts and flagged tuples.

### 7. Start coding

OpenCode is now available in your tmux session. Run your sprint:

```powershell
opencode
```

GNHF is also available for multi-agent orchestration:

```powershell
gnhf --agent opencode --worktree . --max-iterations 2 --stop-when "The objective is complete and committed."
```
