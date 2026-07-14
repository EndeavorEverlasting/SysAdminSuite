# Developer Workstation Provisioning

## Purpose

SysAdminSuite owns the developer-workstation orchestration layer for a bimodal Windows and Linux programming workflow. WezTerm is the preferred terminal host on both supported platforms. Native Windows and native Linux are first-class execution modes.

WSL remains available as a lower-priority Windows compatibility and experimentation profile. It is not the default Linux implementation and must not replace or obscure native Linux support.

macOS is explicitly unsupported in this contract because no current test environment is available. The repository must not advertise, generate, or infer macOS readiness until a dedicated test lane proves it.

This document defines the profile and ownership contract only. It does not install software, authenticate agents, mutate deployment targets, or duplicate AgentSwitchboard implementation.

## Repository ownership boundary

### SysAdminSuite owns

- Windows and Linux prerequisite inventory and future orchestration;
- WezTerm installation and managed configuration policy on supported platforms;
- native Windows and native Linux execution-profile selection;
- optional WSL distribution discovery and compatibility routing on Windows;
- tmux configuration for Linux-native and optional WSL workflows;
- project workspace and launcher composition;
- elevation, rollback, and technician-facing evidence boundaries;
- validation that the external AgentSwitchboard contract is available before invocation.

### AgentSwitchboard owns

- coding-agent installation, detection, upgrade, and repair;
- agent-specific PATH and wrapper handling;
- authentication-readiness reporting without automatic authentication;
- per-agent smoke tests and normalized agent inventory.

SysAdminSuite must consume AgentSwitchboard through a versioned external contract. It must not copy AgentSwitchboard installers into this repository or silently replace customized agent installations.

## Canonical profile contract

- Schema: `schemas/harness/developer-workstation-profile.schema.json`
- Sanitized sample: `Config/developer-workstation-profile.sample.json`
- Contract test: `Tests/survey/test_developer_workstation_profile_contracts.py`

The contract uses these first-class paths:

```text
Windows:
Windows -> WezTerm -> PowerShell 7 -> OpenCode / AGY / Goose

Linux:
Linux -> WezTerm -> Bash -> tmux -> OpenCode / AGY / Goose
```

The optional Windows compatibility path remains:

```text
Windows -> WezTerm -> WSL -> Bash -> tmux -> OpenCode / AGY / Goose
```

## Platform posture

| Platform | Support | Default profile | Runtime-test posture |
|---|---|---|---|
| Windows | Supported | `windows-native` | Available |
| Linux | Supported | `linux-native` | Available |
| macOS | Unsupported | None | Unavailable |
| WSL | Optional Windows environment | `wsl-tmux` disabled by default | Experimental/compatibility |

A future macOS lane must begin as a separately scoped research and validation sprint. Documentation, launchers, schemas, and installers must continue to reject macOS support claims until that lane has real executable proof.

## Preference and fallback rules

1. WezTerm is required as the preferred terminal provider for this workstation profile.
2. Windows-native and Linux-native are both enabled first-class profiles.
3. The default profile is selected by host platform rather than by a single cross-platform default.
4. WSL is Windows-only, disabled by default, and lower priority than Windows-native.
5. Linux-native uses a native Linux shell. It must not be represented as WSL.
6. macOS profiles are outside the accepted schema.
7. Existing user configuration must be preserved unless an explicit managed-block or replacement policy is authorized.

## Safety posture

The profile is fail closed around these properties:

- install missing components only;
- preserve existing user configuration;
- never authenticate accounts automatically;
- never contact or mutate deployment targets;
- never commit runtime evidence, credentials, or machine-local paths;
- never claim support for an untested operating system.

## Proof ceiling

The contract test can prove:

- schema shape and fail-closed platform declarations;
- enabled native Windows and Linux defaults;
- WezTerm preference;
- optional, lower-priority WSL posture;
- explicit macOS exclusion;
- repository ownership and safety boundaries;
- sanitized tracked configuration and validation-runner registration.

It cannot prove:

- WezTerm, PowerShell, Bash, tmux, WSL, or any coding agent is installed;
- native Windows or native Linux agent operation works;
- AgentSwitchboard exposes a stable executable command;
- installation, repair, upgrade, authentication readiness, or launch behavior;
- Windows elevation or Linux privilege behavior;
- rollback behavior;
- end-to-end workstation provisioning.

Those require later bounded implementation and platform-specific runtime sprints.

## Next implementation seam

Before adding an executable SysAdminSuite installer, AgentSwitchboard must publish a stable, versioned invocation and result contract for both Windows and Linux.

The SysAdminSuite adapter should then:

1. detect the host as Windows or Linux;
2. select the matching native WezTerm execution profile;
3. treat WSL only as an explicit Windows fallback;
4. reject macOS as unsupported;
5. invoke AgentSwitchboard without forwarding secrets;
6. translate normalized PASS/SKIP/FAIL results into a SysAdminSuite evidence summary.
