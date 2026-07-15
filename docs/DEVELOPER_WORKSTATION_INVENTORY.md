# Developer Workstation Execution-Domain Inventory

The inventory is read-only. It reports the host, terminal roles, execution
domains, tmux health, persistence-service state, and agent command resolution
without installing packages, starting stopped WSL distributions, launching a
GUI, editing configuration, authenticating, or attempting interactive smoke.

## Domains

- `windows-native`: PowerShell fallback/admin and Windows agent commands.
- `windows-wsl`: the Windows tmux backend and its native or bridged agents.
- `linux-native`: local Linux tmux and native agents.

These domains are never interchangeable. A Windows command does not establish
WSL readiness, and WSL is not native-Linux runtime proof.

## Detected state

The v2 inventory distinguishes `wezterm.exe` from `wezterm-gui.exe`, reports
only path classes, inspects the managed default-workspace and font posture,
and records WSL candidate distribution state, tmux version/socket/sessions,
nested-tmux state, keepalive and PID health, desktop shortcut, and start/stop
script presence.

Agents report command kind (`executable`, `wrapper`, `function`, `alias`, or
`missing`), selected native/bridge backend, command-path class, version when
safe, authentication readiness, and an explicit non-attempted interactive
smoke state. Alias-only commands are not treated as scriptable automation.

## Fixtures and evidence

Ten sanitized scenarios cover no WSL, Docker-only WSL, stopped WSL, healthy and
stale keepalive, a healthy `dev` tmux session, bridge-only and WSL-native agents,
an unavailable font, and WezTerm CLI/GUI confusion. Collectors can emit both the
typed inventory and a `sas-developer-workstation-lifecycle-result/v1` artifact.
Live output belongs under ignored `runs/` paths.

## Commands

Windows PowerShell:

```powershell
./scripts/Get-SasDeveloperWorkstationInventory.ps1 -OutputPath ./runs/inventory.json -LifecycleOutputPath ./runs/lifecycle.json
```

Native Linux or WezTerm/tmux Bash:

```bash
bash scripts/get-sas-developer-workstation-inventory.sh --output runs/inventory.json --lifecycle-output runs/lifecycle.json
```

## Proof ceiling

Inventory proves detected read-only state. Command presence is not successful
launch or authentication. A tmux session is not persistence proof. No launcher,
provider, interactive agent, or operator-acceptance claim is made.
