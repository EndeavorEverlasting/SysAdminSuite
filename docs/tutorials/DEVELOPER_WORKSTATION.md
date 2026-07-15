# Developer Workstation: WezTerm → tmux → agents

This is the canonical operator guide for the persistent coding workstation owned by SysAdminSuite and AgentSwitchboard.

The product model is:

- WezTerm is the terminal GUI.
- tmux session `dev` is the persistent workspace.
- Windows uses a selected non-Docker WSL distribution as the tmux backend.
- Native Linux uses local tmux.
- PowerShell 7 is the Windows fallback and administration shell, not the primary tmux workspace.
- OpenCode, AGY, and Goose are resolved by AgentSwitchboard in the domain where they run.

macOS is unsupported. WSL is not native-Linux proof.

## Know which terminal receives a command

| Label in this guide | Where to use it |
|---|---|
| **Regular Windows PowerShell** | A normal PowerShell 7 window outside WezTerm/tmux. Use it for Windows Inventory, Plan, Apply, lifecycle, and recovery. |
| **WezTerm/tmux Bash** | A Bash pane inside the `dev` tmux session. Use it for tmux and coding-agent commands. |
| **Native Linux Bash** | A terminal on a real Linux desktop, not WSL. Use it for the native-Linux lifecycle. |
| **Windows shortcut** | Double-click `WezTerm tmux` on the Windows desktop. |
| **File content** | Configuration text managed by the repository. Do not paste it into a shell. |

Opening the generated WezTerm shortcut already attaches to tmux `dev`. Do not run `tmux new-session` inside that pane: `$TMUX` is already set, and nesting tmux makes detach and key bindings ambiguous.

## Prerequisites

Windows requires PowerShell 7, WezTerm GUI, WSL2, one non-Docker development distribution, tmux in that distribution, Python, Git, a SysAdminSuite checkout, and an AgentSwitchboard checkout.

Native Linux requires a graphical Linux desktop, WezTerm, tmux, Bash, Python, Git, and both repositories. A WSL kernel containing `microsoft` does not qualify.

The commands never automate provider authentication. Sign-in, tokens, and provider-quality checks remain manual and outside runtime evidence.

## Windows first-time setup

Inventory and Plan are read-only. Apply requires `-AllowTargetMutation`; `-BridgePermission` explicitly allows canonical WSL wrappers to use healthy Windows agent executables when no WSL-native executable exists.

Terminal: **regular Windows PowerShell**, from the SysAdminSuite repository root.

```powershell
$Switchboard = 'C:\path\to\AgentSwitchboard'
$Evidence = '.\survey\output\developer-workstation'

pwsh -NoProfile -File .\scripts\Invoke-SasDeveloperWorkstation.ps1 `
  -Mode Inventory -Platform windows -ExecutionDomain windows-wsl `
  -AgentSwitchboardRoot $Switchboard -OutputRoot "$Evidence\01-inventory"

pwsh -NoProfile -File .\scripts\Invoke-SasDeveloperWorkstation.ps1 `
  -Mode Plan -Platform windows -ExecutionDomain windows-wsl `
  -AgentSwitchboardRoot $Switchboard -OutputRoot "$Evidence\02-plan"
```

Read the English summary before Apply. The Plan must name a real `wezterm-gui.exe`, a non-Docker WSL distro, tmux, and session `dev`.

Terminal: **regular Windows PowerShell**, after reviewing Plan and authorizing the bounded configuration change.

```powershell
pwsh -NoProfile -File .\scripts\Invoke-SasDeveloperWorkstation.ps1 `
  -Mode Apply -Platform windows -ExecutionDomain windows-wsl `
  -AgentSwitchboardRoot $Switchboard -AllowTargetMutation `
  -BridgePermission -LaunchGui -OutputRoot "$Evidence\03-apply"
```

Apply preserves the existing `.wezterm.lua`, writes a bounded managed include, renders `.wezterm-sysadminsuite.lua`, preserves the first rollback manifest across idempotent reruns, starts the exact owned WSL keepalive, ensures tmux `dev`, installs managed AgentSwitchboard wrappers in WSL, and creates the desktop shortcut.

## Lua is file content

`.wezterm.lua` and `.wezterm-sysadminsuite.lua` are Lua configuration files. Lua is not a PowerShell or Bash command. Repository lifecycle commands render and manage the bounded include.

File content: **conceptual Lua shape only; do not paste into PowerShell or Bash**.

```lua
local wezterm = require 'wezterm'
local config = wezterm.config_builder()
-- BEGIN SYSADMINSUITE WINDOWS TMUX WORKSPACE
-- The repository renders and updates this managed include.
-- END SYSADMINSUITE WINDOWS TMUX WORKSPACE
return config
```

## Daily Windows use

Windows shortcut: **double-click `WezTerm tmux`**. The shortcut starts a hidden, noninteractive lifecycle command and launches the real `wezterm-gui.exe`; no parent PowerShell window must remain.

Terminal: **regular Windows PowerShell**, equivalent CLI Start.

```powershell
pwsh -NoProfile -File .\scripts\Invoke-SasDeveloperWorkstation.ps1 `
  -Mode Start -Platform windows -ExecutionDomain windows-wsl `
  -AgentSwitchboardRoot $Switchboard -BridgePermission -LaunchGui `
  -OutputRoot "$Evidence\daily-start"
```

Terminal: **WezTerm/tmux Bash**, safe status checks.

```bash
printf 'TMUX=%s\n' "${TMUX:-not-attached}"
tmux display-message -p 'session=#{session_name} attached=#{session_attached} windows=#{session_windows}'
tmux list-windows -F '#{window_index}:#{window_name}:#{pane_current_command}'
```

Detach with `Ctrl+B`, release both keys, then press `D`. Closing WezTerm does not mean Stop: the owned keepalive and tmux server are designed to remain alive.

Terminal: **regular Windows PowerShell**, verify after detaching or closing the GUI.

```powershell
pwsh -NoProfile -File .\scripts\Invoke-SasDeveloperWorkstation.ps1 `
  -Mode Status -Platform windows -ExecutionDomain windows-wsl `
  -AgentSwitchboardRoot $Switchboard -BridgePermission `
  -OutputRoot "$Evidence\daily-status"
```

Status is healthy only when the exact owned keepalive PID and tmux `dev` both remain. Reopen with the desktop shortcut to reattach the same windows.

## Agent wrappers inside tmux

Canonical wrappers are `opencode`, `agy`, and `goose`. Each prefers a healthy native executable. A Windows bridge is selected only when the recorded policy permits it. Diagnostic wrappers make routing explicit:

- `<agent>_native` requires a native executable in the current domain.
- `<agent>_win` requires Windows interop and never masquerades as native.
- `<agent>` applies native-first policy and reports failure when neither route is healthy.

Terminal: **WezTerm/tmux Bash**, content-free resolution checks.

```bash
opencode --agent-switchboard-probe
agy --agent-switchboard-probe
goose --agent-switchboard-probe

opencode_native --agent-switchboard-probe
opencode_win --agent-switchboard-probe
```

Terminal: **WezTerm/tmux Bash**, launch agents only after completing any required authentication yourself.

```bash
opencode
agy
goose
```

Version/help output proves command acknowledgement only. It does not prove authentication, provider response quality, or a successful coding conversation.

## PowerShell fallback

Choose `PowerShell 7 (fallback/admin)` from the WezTerm launch menu when Windows administration or a Windows-native agent is required. This profile does not create hidden WSL lifecycle state and does not provide tmux persistence.

Terminal: **regular Windows PowerShell**, inspect fallback posture.

```powershell
pwsh -NoProfile -File .\scripts\Invoke-SasDeveloperWorkstation.ps1 `
  -Mode Plan -Platform windows -ExecutionDomain windows-native `
  -AgentSwitchboardRoot $Switchboard -OutputRoot "$Evidence\powershell-fallback"
```

## Native Linux quick start

Run this section only on a real Linux desktop. Stop if `/proc/sys/kernel/osrelease` contains `microsoft`, if `wezterm` is missing, or if no graphical session is available.

Terminal: **native Linux Bash**, host gate and read-only phases.

```bash
grep -qi microsoft /proc/sys/kernel/osrelease && { echo 'WSL is not native Linux proof'; exit 1; }
command -v wezterm tmux bash python3 git

bash scripts/invoke-sas-developer-workstation.sh \
  --mode Inventory --platform linux --execution-domain linux-native \
  --agentswitchboard-root ../AgentSwitchboard \
  --output-root survey/output/developer-workstation/01-inventory

bash scripts/invoke-sas-developer-workstation.sh \
  --mode Plan --platform linux --execution-domain linux-native \
  --agentswitchboard-root ../AgentSwitchboard \
  --output-root survey/output/developer-workstation/02-plan
```

Terminal: **native Linux Bash**, authorized Apply and GUI launch.

```bash
bash scripts/invoke-sas-developer-workstation.sh \
  --mode Apply --platform linux --execution-domain linux-native \
  --agentswitchboard-root ../AgentSwitchboard \
  --allow-target-mutation --launch-gui \
  --output-root survey/output/developer-workstation/03-apply
```

Native Linux uses local tmux, not WSL and not a Windows bridge by default. The repository currently has fixture proof for this path; the 2026-07-15 recovery sprint had no qualifying native desktop and therefore did not claim live native-Linux persistence.

## Stop, Repair, and Rollback

Stop is intentionally destructive to the persistent workspace: it terminates tmux `dev` and every shell or agent process inside it. Preserve work and obtain explicit operator intent first.

Terminal: **regular Windows PowerShell**, destructive Stop after explicit intent.

```powershell
pwsh -NoProfile -File .\scripts\Invoke-SasDeveloperWorkstation.ps1 `
  -Mode Stop -Platform windows -ExecutionDomain windows-wsl `
  -AgentSwitchboardRoot $Switchboard -BridgePermission `
  -OutputRoot "$Evidence\stop"
```

Repair refreshes only managed configuration, owned lifecycle state, tmux agent `PATH`, and the generated shortcut.

Terminal: **regular Windows PowerShell**, bounded Repair.

```powershell
pwsh -NoProfile -File .\scripts\Invoke-SasDeveloperWorkstation.ps1 `
  -Mode Repair -Platform windows -ExecutionDomain windows-wsl `
  -AgentSwitchboardRoot $Switchboard -AllowTargetMutation `
  -BridgePermission -LaunchGui -OutputRoot "$Evidence\repair"
```

Rollback restores configuration from the preserved manifest. Stop first if you also intend to terminate the active workspace; Rollback alone is a configuration operation.

Terminal: **regular Windows PowerShell**, authorized Rollback.

```powershell
pwsh -NoProfile -File .\scripts\Invoke-SasDeveloperWorkstation.ps1 `
  -Mode Rollback -Platform windows -ExecutionDomain windows-wsl `
  -AgentSwitchboardRoot $Switchboard -AllowTargetMutation `
  -BridgePermission -OutputRoot "$Evidence\rollback"
```

## Recovery table

| Symptom | Read first | Recovery |
|---|---|---|
| No GUI | Plan must identify `wezterm-gui.exe`, not only `wezterm.exe` | Run Repair, then use the regenerated shortcut. |
| Hidden PowerShell remains | Shortcut may be stale | Run Repair; current shortcut includes noninteractive confirmation handling. |
| `keepalive-stale` | PID file does not match the exact owned WSL command | Run Repair. Never kill all `wsl.exe` processes. |
| `tmux-socket-missing` | Backend is running but `dev` is absent | Run Start or Repair. |
| Agent says command not found | Managed wrapper path is absent in an old pane | Open a new tmux window or run Repair, then use the canonical wrapper. |
| Nested tmux warning | `$TMUX` is already set | Detach instead of starting another tmux server. |
| Invalid Lua | Existing config lacks a bounded `return config` insertion point | Use the backup manifest; repair the user config explicitly. |
| Native Linux requested on WSL | Kernel contains `microsoft` | Move to a real Linux desktop; do not relabel WSL evidence. |

No recovery command uses `wsl --unregister`, broad process-name kills, automatic authentication, or full dotfile replacement.

## Proof taxonomy and current evidence

A fixture proof is not live-runtime proof. Live-runtime proof is also not authentication/provider proof or operator acceptance; each claim stops at the evidence recorded for that layer.

| Proof class | Current result | What it means |
|---|---|---|
| Static/contracts | PASS | Schemas, fixtures, scripts, routing, and safety invariants validate. |
| Fixture E2E | 22/22 PASS | The public orchestrator covers required success and failure journeys in disposable roots. |
| Windows live runtime | PASS | Independent GUI, exact keepalive, tmux detach/reopen, same windows, and canonical-wrapper help interaction were observed. |
| Native Linux live runtime | BLOCKED | Available Linux kernel is WSL2 and native Linux WezTerm GUI is missing. |
| Authentication/provider | NOT PROVEN | No login, token, provider response, or response quality was captured. |
| Operator acceptance | NOT RECORDED | Automation cannot accept the experience on the operator's behalf. |

The Windows interaction ceiling is `canonical-wrapper-help-command-only`. It is stronger than startup-banner proof and weaker than authenticated provider behavior.

## Validation commands

Terminal: **regular Windows PowerShell**, documentation and repository gates.

```powershell
python .\Tests\survey\test_developer_workstation_documentation_contracts.py
bash .\tests\survey\run_offline_survey_tests.sh
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-ai-layer.ps1
git diff --check
```

Further details: [provisioning contract](../DEVELOPER_WORKSTATION_PROVISIONING.md), [inventory contract](../DEVELOPER_WORKSTATION_INVENTORY.md), [fixture E2E report](../DEVELOPER_WORKSTATION_E2E_PROOF_MERGE_READINESS.md), and [PR convergence report](../DEVELOPER_WORKSTATION_CONVERGENCE_REPORT.md).
