# Persistent Developer Workstation Contract

## Product contract

The preferred workstation experience is:

```text
WezTerm terminal host -> tmux persistent workspace -> coding agents
```

The layers are independent. WezTerm owns the graphical terminal. tmux owns the
persistent workspace. A backend supplies tmux. Bash or PowerShell is the shell
inside a selected execution domain. Agent readiness is evaluated in that same
domain.

On Windows, a detected non-Docker WSL distribution is the tmux backend. WSL is
an implementation detail, not the user-facing goal. On native Linux, tmux runs
locally. PowerShell 7 remains an enabled Windows fallback and administration
profile, but it cannot claim to host tmux. macOS remains unsupported.

## Machine-readable authority

- Schema: `schemas/harness/developer-workstation-profile.schema.json`
- Sanitized sample: `Config/developer-workstation-profile.sample.json`
- Contract test: `Tests/survey/test_developer_workstation_profile_contracts.py`
- PR recovery ledger: `docs/DEVELOPER_WORKSTATION_PR_STACK.md`

The breaking schema revision is `sas-developer-workstation-profile/v3`.

## Layer decision record

| Layer | Windows preferred | Linux preferred | Windows fallback |
|---|---|---|---|
| Terminal host | WezTerm GUI | WezTerm GUI | WezTerm or a native console |
| Workspace | tmux session `dev` | tmux session `dev` | none |
| tmux backend | detected non-Docker WSL distro | local native Linux | not applicable |
| Shell | Bash inside WSL | Bash on native Linux | PowerShell 7 |
| Agent domain | `windows-wsl` | `linux-native` | `windows-native` |

The user-facing workspace is named `tmux: Development`. The deterministic tmux
session is `dev`.

## Fail-closed invariants

1. A tmux workspace may select only a backend that declares tmux capability.
2. Windows-native PowerShell is a fallback profile with `multiplexer: none`.
3. The Windows backend selector must reject Docker Desktop distributions.
4. `windows-native`, `windows-wsl`, and `linux-native` are distinct execution
   domains.
5. A Windows command on PATH does not prove readiness inside WSL.
6. Native agent commands are preferred; a Windows bridge is explicit and only
   used when the invoking contract permits it.
7. No workflow authenticates an agent automatically.
8. Runtime evidence and machine-local paths are never tracked.

## Ownership boundary

SysAdminSuite owns platform inventory, backend selection, managed WezTerm/tmux
configuration, lifecycle operations, launchers, rollback, evidence, and the
technician entrypoint. AgentSwitchboard owns agent installation, native and
bridge wrappers, version probes, authentication-readiness reporting, and agent
smoke contracts. The repositories integrate through a versioned external
request/result contract; SysAdminSuite must not copy AgentSwitchboard installers.

## Safety and proof ceiling

The profile preserves existing configuration, installs only missing approved
components after explicit apply, never authenticates, never mutates deployment
targets, and never claims macOS support.

This contract proves schema shape, layer separation, fail-closed invalid cases,
and the PR collision decision. It does not prove installation, GUI launch,
keepalive behavior, tmux persistence, agent interaction, or native-Linux GUI
runtime. Those remain later sprint gates.
