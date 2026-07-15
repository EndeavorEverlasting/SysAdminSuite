# Developer Workstation Inventory

## Purpose

SysAdminSuite owns a read-only inventory surface that determines what is present and healthy enough to plan, without installing, repairing, authenticating, or mutating anything.

The inventory collects bounded facts about the host environment and maps them to the developer-workstation profile v2 from the provisioning contract.

## Canonical paths

| Artifact | Path |
|---|---|
| Inventory schema | `schemas/harness/developer-workstation-inventory.schema.json` |
| Profile schema | `schemas/harness/developer-workstation-profile.schema.json` |
| Profile sample | `Config/developer-workstation-profile.sample.json` |
| Windows collector | `scripts/Get-SasDeveloperWorkstationInventory.ps1` |
| Linux collector | `scripts/get-sas-developer-workstation-inventory.sh` |
| English renderer | `scripts/Render-SasWorkstationInventoryEnglish.py` |
| Contract test | `Tests/survey/test_developer_workstation_inventory_contracts.py` |
| CI workflow | `.github/workflows/developer-workstation-inventory.yml` |

## Detected fields

The inventory captures:

| Field | Description |
|---|---|
| `detected_platform` | `windows`, `linux`, or `unsupported` |
| `execution_environment` | `native`, `wsl`, or `unknown` |
| `checks.wezterm` | WezTerm executable presence and version |
| `checks.shell` | Native shell presence and version |
| `checks.multiplexer` | tmux presence and version (SKIP on Windows native) |
| `checks.repository` | SysAdminSuite repo root detection with relative path |
| `checks.agent_commands` | OpenCode, AGY, Goose command resolution and version |
| `checks.agent_switchboard` | AgentSwitchboard availability |
| `checks.wsl` | WSL availability and registered distributions (Windows native only) |
| `selected_profile` | Matching enabled profile from the profile sample |
| `eligible_profiles` | All enabled profiles matching the detected platform and environment |
| `proof_ceiling` | Statement of what the inventory does not prove |

## Reason codes

Every check returns one of:

| Status | Meaning |
|---|---|
| `PASS` | Tool or resource was found and version was obtained (or distribution discovered) |
| `SKIP` | Check not applicable on this platform (e.g., tmux on Windows native, WSL on Linux) |
| `FAIL` | Tool or resource was not found or not obtainable |

## Path redaction

- Repository `relative_path` uses portable relative paths, never absolute machine-local paths.
- No drive letters, `/Users/`, `/home/`, or usernames appear in tracked fixtures or output.
- Tool `path` fields in live inventory are ephemeral and never committed.

## Unsupported-platform behavior

When `detected_platform` is `unsupported`, all tool checks return `SKIP`, the repository check returns `FAIL`, `selected_profile` is `null`, and `eligible_profiles` is empty. The inventory does not guess at unsupported behavior.

## Fixtures

| Fixture | Scenario |
|---|---|
| `windows-native.fixture.json` | Windows host with WezTerm, pwsh, no tmux, WSL with Ubuntu, 2 of 3 agents |
| `linux-native.fixture.json` | Linux host with WezTerm, bash, tmux, no WSL, 2 of 3 agents |
| `wsl.fixture.json` | Windows host running inside a WSL session |
| `missing-tools.fixture.json` | Windows host with all tools missing |
| `malformed-output.fixture.json` | Intentionally incomplete JSON to test schema rejection |
| `unsupported-platform.fixture.json` | macOS or unknown platform |

## Proof ceiling

The inventory proves:

- What tools are present or absent on the host at command-discovery time.
- Which profile from the sample is selected and eligible.
- The detected platform and execution environment.

The inventory does not prove:

- WezTerm, shell, tmux, or any coding agent is installed and functional.
- Native Windows or native Linux agent operation works.
- AgentSwitchboard exposes a stable executable command.
- Installation, repair, upgrade, authentication readiness, or launch behavior.
- End-to-end workstation provisioning.

## Usage

### Windows (PowerShell)

```powershell
# Live inventory
$inventory = .\scripts\Get-SasDeveloperWorkstationInventory.ps1 -OutputPath .\runs\inventory.json

# Fixture mode
$inventory = .\scripts\Get-SasDeveloperWorkstationInventory.ps1 -FixtureMode
```

### Linux (Bash)

```bash
# Live inventory
bash scripts/get-sas-developer-workstation-inventory.sh --output runs/inventory.json

# Fixture mode
bash scripts/get-sas-developer-workstation-inventory.sh --fixture
```

### English renderer

```bash
python3 scripts/Render-SasWorkstationInventoryEnglish.py Tests/Fixtures/workstation-inventory/windows-native.fixture.json
```

## Validation order

1. Dependency-free contract tests (Python)
2. PowerShell parser for Windows collector
3. Bash syntax check for Linux collector
4. Schema validation of every fixture
5. English-renderer checks
6. Dedicated CI workflow
7. Offline suite
8. `git diff --check`
9. Final diff review
