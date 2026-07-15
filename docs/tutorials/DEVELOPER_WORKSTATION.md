# Tutorial: Developer Workstation Setup with SysAdminSuite

Use this tutorial to inventory, plan, configure, launch, verify, and recover a developer workstation for SysAdminSuite on Windows or Linux.

## What this tutorial covers

```text
read-only host inventory (Windows or Linux)
-> select matching execution profile
-> plan WezTerm configuration
-> apply configuration (optional, requires explicit authorization)
-> launch workspace
-> verify environment
-> rollback if needed
-> interpret proof results
```

Every step in this tutorial is read-only unless you explicitly authorize mutation with `-AllowTargetMutation`. The plan action never touches your file system.

## Supported platforms

| Platform | Support | Default profile | Shell | Multiplexer |
|----------|---------|-----------------|-------|-------------|
| Windows | Supported | `windows-native` | PowerShell 7 | none |
| Linux | Supported | `linux-native` | Bash | tmux |
| WSL | Optional (Windows only) | `wsl-tmux` (disabled) | Bash | tmux |
| macOS | **Unsupported** | None | n/a | n/a |

### macOS notice

macOS is explicitly unsupported. No test environment exists for macOS. The repository does not advertise, generate, or infer macOS readiness. All schemas reject macOS platform claims. Do not attempt to use these tools on macOS.

---

## Key concepts

### WezTerm is the terminal host

WezTerm is the required terminal emulator for the developer workstation. It runs on both Windows and Linux. On Windows, it provides a native PowerShell 7 session with optional WSL launch-menu entries. On Linux, it provides a Bash session with tmux integration.

If WezTerm is not installed, the planner emits a warning and continues. The launcher falls back to native PowerShell or a plain Bash session.

### WSL is optional, not mandatory

WSL (Windows Subsystem for Linux) is an optional execution environment on Windows. It is disabled by default in the workstation profile. Native Windows (PowerShell 7) and native Linux (Bash) are first-class execution modes. WSL is a compatibility path for tools that require a Linux environment on a Windows host.

### Native Linux is not WSL

Running WezTerm on a Linux machine is the `linux-native` profile. Running WezTerm inside WSL on a Windows machine is the `wsl-tmux` profile. These are different execution environments with different inventory results and different configuration paths.

### AgentSwitchboard is external

SysAdminSuite validates that AgentSwitchboard is available but does not install, configure, or authenticate it. AgentSwitchboard owns agent installation, detection, upgrade, repair, and authentication-readiness reporting. SysAdminSuite never automatically authenticates accounts.

### No automatic authentication

The workstation profile enforces `automatic_authentication: false`. SysAdminSuite does not log into any agent, API, or service. Authentication readiness is reported, not performed.

---

## Prerequisites

Before running any workstation command:

1. **Clone the repository** (or use an existing clone):

   ```bash
   git clone https://github.com/EndeavorEverlasting/SysAdminSuite.git
   ```

2. **Navigate to the repository root.** All commands assume you are at the top level of the `SysAdminSuite` folder.

3. **Verify your shell:**

   - Windows: PowerShell 7 (`pwsh`) recommended; PowerShell 5.1 compatible.
   - Linux: Bash 4+ recommended.

4. **Optional: Install WezTerm** from [wezfurlong.org/wezterm](https://wezfurlong.org/wezterm/). The inventory and plan work without WezTerm; only Apply and Launch benefit from it.

---

## Phase 1: Read-only inventory

The inventory detects what is present on your host without installing, repairing, or mutating anything.

### Windows inventory

```powershell
.\scripts\Get-SasDeveloperWorkstationInventory.ps1 -OutputPath .\runs\workstation-inventory.json
```

This probes WezTerm, PowerShell, tmux (WSL only), repository presence, agent commands (OpenCode, AGY, Goose), AgentSwitchboard, and WSL distributions. It emits:

- `.\runs\workstation-inventory.json` — machine-readable inventory
- `.\runs\workstation-inventory-summary.txt` — human-readable summary

### Linux inventory

```bash
bash scripts/get-sas-developer-workstation-inventory.sh --output runs/workstation-inventory.json
```

Same probe structure as the Windows version, adapted for Linux. Emits JSON and English summary to stdout and the specified output path.

### Understanding the output

Every check returns one of:

| Status | Meaning |
|--------|---------|
| `PASS` | Tool found and version obtained |
| `SKIP` | Check not applicable on this platform |
| `FAIL` | Tool not found or not obtainable |

The inventory also reports:

- `detected_platform` — `windows`, `linux`, or `unsupported`
- `execution_environment` — `native`, `wsl`, or `unknown`
- `selected_profile` — the matching enabled profile from the sample
- `eligible_profiles` — all enabled profiles for this platform

### English renderer

To render any inventory JSON as a human-readable summary:

```bash
python3 scripts/Render-SasWorkstationInventoryEnglish.py runs/workstation-inventory.json
```

### Fixture mode (for testing)

```powershell
# Windows fixture
.\scripts\Get-SasDeveloperWorkstationInventory.ps1 -FixtureMode
```

```bash
# Linux fixture
bash scripts/get-sas-developer-workstation-inventory.sh --fixture
```

Fixture mode emits synthetic inventory data without probing the host. Use it to verify the rendering pipeline or to test downstream tools.

---

## Phase 2: Plan WezTerm configuration (read-only)

The plan action renders the planned WezTerm configuration files without touching the file system.

### Windows plan

```powershell
.\scripts\Invoke-SasWezTermWindowsNativeProfile.ps1 `
  -ProfilePath .\Config\developer-workstation-profile.sample.json `
  -Action Plan
```

This produces:

- A planned `.wezterm-sysadminsuite.lua` content block (the managed fragment).
- A planned `.wezterm.lua` content block (your main config with the managed block injected).
- No file changes.

Review the plan output before deciding to apply.

### Plan with a specific user config directory

```powershell
.\scripts\Invoke-SasWezTermWindowsNativeProfile.ps1 `
  -ProfilePath .\Config\developer-workstation-profile.sample.json `
  -Action Plan `
  -UserConfigDir "C:\Users\YourName"
```

### Plan with a fixture inventory

```powershell
.\scripts\Invoke-SasWezTermWindowsNativeProfile.ps1 `
  -ProfilePath .\Config\developer-workstation-profile.sample.json `
  -InventoryFixturePath .\Tests\Fixtures\workstation-inventory\windows-native.fixture.json `
  -Action Plan
```

---

## Phase 3: Apply WezTerm configuration (mutation)

Apply writes WezTerm configuration files. It requires explicit authorization.

### Windows apply

```powershell
.\scripts\Invoke-SasWezTermWindowsNativeProfile.ps1 `
  -ProfilePath .\Config\developer-workstation-profile.sample.json `
  -Action Apply `
  -AllowTargetMutation
```

Apply will:

1. Prompt for confirmation (High impact).
2. Create a timestamped backup in `logs/wezterm-backups/`.
3. Write `.wezterm-sysadminsuite.lua` (the managed fragment).
4. Update `.wezterm.lua` (inject or replace the managed block).
5. Optionally validate via `wezterm show-config`.

### What Apply does not do

- It does not install WezTerm.
- It does not install PowerShell, Bash, or tmux.
- It does not authenticate any agent or service.
- It does not contact any remote target.
- It does not modify the repository.

---

## Phase 4: Launch workspace

### Windows launcher

Double-click:

```text
Launch-WorkstationWezTerm.cmd
```

Or from PowerShell:

```powershell
.\Launch-WorkstationWezTerm.ps1
```

The launcher:

1. Detects WezTerm on the PATH.
2. If found, opens WezTerm at the repository root.
3. If not found, falls back to a native PowerShell session at the repository root.

### Linux workspace functions

On Linux, source the SysAdminSuite bash fragment from your `~/.bashrc`:

```bash
source /path/to/SysAdminSuite/configs/linux-native/sas-bashrc.sh
```

Then use:

```bash
sas_workspace     # Open WezTerm at the repository root (if available)
sas_wezterm_info  # Show WezTerm detection status
sas_tmux_attach   # Attach to the SysAdminSuite tmux session
sas_agent_info    # Show agent command availability
```

### tmux integration (Linux)

Source the tmux fragment from your `~/.tmux.conf`:

```conf
source-file /path/to/SysAdminSuite/configs/linux-native/tmux-linux.conf
```

This adds WezTerm-compatible keybindings for split navigation.

---

## Phase 5: Verify environment

After launching, verify your environment:

1. **Check WezTerm loaded the config:** In WezTerm, the launch menu should show a `windows-native` entry (Windows) or the Bash prompt should be available (Linux).

2. **Check agent availability:**

   ```powershell
   # Windows
   Get-Command opencode -ErrorAction SilentlyContinue
   Get-Command agy -ErrorAction SilentlyContinue
   Get-Command goose -ErrorAction SilentlyContinue
   ```

   ```bash
   # Linux
   which opencode agy goose 2>/dev/null
   ```

3. **Check AgentSwitchboard:**

   The inventory output's `checks.agent_switchboard` field reports availability. `FAIL` means AgentSwitchboard is not installed or not on the PATH. This does not block planning or configuration.

---

## Phase 6: Rollback and recovery

### Rollback WezTerm configuration

```powershell
.\scripts\Invoke-SasWezTermWindowsNativeProfile.ps1 `
  -Action Rollback `
  -AllowTargetMutation
```

Rollback will:

1. Restore from the latest timestamped backup in `logs/wezterm-backups/`.
2. If no backup exists, strip the managed block from `.wezterm.lua` and remove `.wezterm-sysadminsuite.lua`.
3. Prompt for confirmation before any file change.

### Restore from git

If you accidentally modified tracked files in the repository:

```bash
git checkout -- .
git clean -fd
```

This restores the repository to the last committed state. Local evidence in `runs/`, `logs/`, and `survey/output/` is not affected.

### Recover from an interrupted run

The inventory and planner are stateless. There is no session to recover. Simply re-run the command from Phase 1 or Phase 2.

---

## Phase 7: Interpret proof results

### What the inventory proves

- What tools are present or absent on the host at command-discovery time.
- Which profile from the sample is selected and eligible.
- The detected platform and execution environment.

### What the inventory does not prove

- That WezTerm, shell, tmux, or any coding agent is installed and functional.
- That native Windows or native Linux agent operation works.
- That AgentSwitchboard exposes a stable executable command.
- Installation, repair, upgrade, authentication readiness, or launch behavior.
- End-to-end workstation provisioning.

### What the E2E fixture suite proves

The 12-journey bimodal E2E suite proves:

- Configuration planning, backup, and rollback on disposable mock-home directories.
- Managed-block injection and replacement in existing `.wezterm.lua`.
- Graceful handling of missing tools, malformed input, and unsupported platforms.
- WSL opt-in generates the correct launch-menu entry.
- macOS detection produces a clean skip.

### What the E2E suite does not prove

- Live runtime agent capabilities.
- Real target mutation or installation.
- Active authentication or provider API responses.
- Network connectivity or remote target behavior.

### Proof ceiling

| Dimension | Achieved |
|-----------|----------|
| `runtime_proof` | false |
| `live_installation_proof` | false |
| `authentication_proof` | false |
| `provider_response_proof` | false |

The highest achieved proof level is **fixture/loopback E2E**. This means all journeys ran against synthetic fixtures in disposable directories. No live target was contacted, no installation was performed, and no authentication occurred.

---

## Windows quick start

```powershell
# 1. Inventory
.\scripts\Get-SasDeveloperWorkstationInventory.ps1 -OutputPath .\runs\inventory.json

# 2. Plan (read-only)
.\scripts\Invoke-SasWezTermWindowsNativeProfile.ps1 `
  -ProfilePath .\Config\developer-workstation-profile.sample.json `
  -Action Plan

# 3. Apply (requires authorization)
.\scripts\Invoke-SasWezTermWindowsNativeProfile.ps1 `
  -ProfilePath .\Config\developer-workstation-profile.sample.json `
  -Action Apply `
  -AllowTargetMutation

# 4. Launch
.\Launch-WorkstationWezTerm.ps1

# 5. Rollback (if needed)
.\scripts\Invoke-SasWezTermWindowsNativeProfile.ps1 `
  -Action Rollback `
  -AllowTargetMutation
```

## Linux quick start

```bash
# 1. Inventory
bash scripts/get-sas-developer-workstation-inventory.sh --output runs/inventory.json

# 2. Source workspace helpers (add to ~/.bashrc)
source configs/linux-native/sas-bashrc.sh

# 3. Open workspace
sas_workspace

# 4. Check agents
sas_agent_info
```

---

## WSL optional profile

WSL is available as a lower-priority Windows compatibility profile. It is **disabled by default**.

To enable WSL profiling, modify `Config/developer-workstation-profile.sample.json` and set the `wsl-tmux` execution profile to `enabled: true` with a lower priority number. The plan action will then include WSL launch-menu entries in the WezTerm configuration.

Do not enable WSL as a replacement for native Linux support. WSL is a Windows-only compatibility path.

---

## AgentSwitchboard readiness

SysAdminSuite validates AgentSwitchboard availability through the inventory. The `checks.agent_switchboard` field reports:

- `PASS` — AgentSwitchboard is detected and versioned.
- `FAIL` — AgentSwitchboard is not found.

A `FAIL` status does not block planning or configuration. It means SysAdminSuite cannot invoke AgentSwitchboard for agent management. AgentSwitchboard owns its own installation, detection, upgrade, repair, and authentication-readiness reporting.

SysAdminSuite must not:

- Copy AgentSwitchboard installers into this repository.
- Silently replace customized agent installations.
- Forward secrets to AgentSwitchboard.
- Automatically authenticate agent accounts.

---

## Safety posture

The workstation profile enforces:

- **Install missing components only** — never overwrite existing tooling.
- **Preserve existing configuration** — managed blocks are injected, not wholesale replaced.
- **Never authenticate accounts automatically** — authentication readiness is reported, not performed.
- **Never contact or mutate deployment targets** — inventory and planning are local-only.
- **Never commit runtime evidence, credentials, or machine-local paths** — output stays local.
- **Never claim support for an untested operating system** — macOS is explicitly rejected.

---

## AI-use prompt

Copy and paste this prompt into an AI assistant to get help explaining the workstation tools, grounded in the current repository:

```text
I am working in the SysAdminSuite repository (https://github.com/EndeavorEverlasting/SysAdminSuite).

I need help understanding the developer workstation setup tools. Please read these files from the repository to answer my questions:

1. docs/tutorials/DEVELOPER_WORKSTATION.md — the canonical developer workstation tutorial
2. Config/developer-workstation-profile.sample.json — the workstation profile definition
3. docs/DEVELOPER_WORKSTATION_PROVISIONING.md — the provisioning contract and ownership boundary
4. docs/DEVELOPER_WORKSTATION_INVENTORY.md — the inventory surface and proof ceiling

After reading those files, please help me with: [your question here]

Important constraints:
- WezTerm is the terminal host. WSL is optional. Native Linux is distinct from WSL.
- macOS is explicitly unsupported.
- No automatic authentication occurs. Secrets are never stored or forwarded.
- Inventory is read-only. Apply requires explicit -AllowTargetMutation.
- The highest proof level is fixture/loopback E2E, not live runtime.
- Do not suggest commands that do not exist in the committed implementation.
```

---

## Command reference

| Command | Platform | Purpose |
|---------|----------|---------|
| `.\scripts\Get-SasDeveloperWorkstationInventory.ps1` | Windows | Read-only host inventory |
| `bash scripts/get-sas-developer-workstation-inventory.sh` | Linux | Read-only host inventory |
| `python3 scripts/Render-SasWorkstationInventoryEnglish.py <file>` | Both | Render inventory as English summary |
| `.\scripts\Invoke-SasWezTermWindowsNativeProfile.ps1 -Action Plan` | Windows | Plan WezTerm config (read-only) |
| `.\scripts\Invoke-SasWezTermWindowsNativeProfile.ps1 -Action Apply -AllowTargetMutation` | Windows | Apply WezTerm config |
| `.\scripts\Invoke-SasWezTermWindowsNativeProfile.ps1 -Action Rollback -AllowTargetMutation` | Windows | Rollback WezTerm config |
| `.\Launch-WorkstationWezTerm.ps1` | Windows | Launch WezTerm workspace |
| `.\Launch-WorkstationWezTerm.cmd` | Windows | Batch wrapper for launcher |
| `sas_workspace` | Linux | Open WezTerm at repo root |
| `sas_wezterm_info` | Linux | Show WezTerm status |
| `sas_tmux_attach` | Linux | Attach to tmux session |
| `sas_agent_info` | Linux | Show agent availability |

## File locations

| File | Path |
|------|------|
| Profile sample | `Config/developer-workstation-profile.sample.json` |
| Profile schema | `schemas/harness/developer-workstation-profile.schema.json` |
| Inventory schema | `schemas/harness/developer-workstation-inventory.schema.json` |
| Windows inventory script | `scripts/Get-SasDeveloperWorkstationInventory.ps1` |
| Linux inventory script | `scripts/get-sas-developer-workstation-inventory.sh` |
| English renderer | `scripts/Render-SasWorkstationInventoryEnglish.py` |
| Windows profile manager | `scripts/Invoke-SasWezTermWindowsNativeProfile.ps1` |
| WezTerm Lua template | `Config/wezterm-windows.lua.template` |
| Windows launcher | `Launch-WorkstationWezTerm.ps1` / `Launch-WorkstationWezTerm.cmd` |
| Linux WezTerm template | `configs/linux-native/wezterm-linux-template.lua` |
| Linux bash fragment | `configs/linux-native/sas-bashrc.sh` |
| Linux tmux fragment | `configs/linux-native/tmux-linux.conf` |
| E2E runner | `scripts/Invoke-SasWorkstationE2E.ps1` |
| Inventory fixtures | `Tests/Fixtures/workstation-inventory/*.json` |
| Backups | `logs/wezterm-backups/` (created by Apply) |

## Further reading

- Provisioning contract: [`docs/DEVELOPER_WORKSTATION_PROVISIONING.md`](../DEVELOPER_WORKSTATION_PROVISIONING.md)
- Inventory surface: [`docs/DEVELOPER_WORKSTATION_INVENTORY.md`](../DEVELOPER_WORKSTATION_INVENTORY.md)
- E2E proof report: [`docs/DEVELOPER_WORKSTATION_E2E_PROOF_MERGE_READINESS.md`](../DEVELOPER_WORKSTATION_E2E_PROOF_MERGE_READINESS.md)
- Convergence report: [`docs/DEVELOPER_WORKSTATION_CONVERGENCE_REPORT.md`](../DEVELOPER_WORKSTATION_CONVERGENCE_REPORT.md)
