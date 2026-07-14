# Developer Workstation Provisioning

## Purpose

SysAdminSuite owns the operator-workstation orchestration layer for a Windows development workstation that enters WSL through WezTerm, uses tmux for persistent project sessions, and delegates coding-agent lifecycle work to AgentSwitchboard.

This document defines the first contract slice only. It does not install software, authenticate agents, mutate target workstations, or duplicate AgentSwitchboard implementation.

## Repository ownership boundary

### SysAdminSuite owns

- Windows prerequisite inventory and future orchestration;
- WSL distribution selection;
- WezTerm and tmux configuration templates;
- project workspace and launcher composition;
- elevation boundaries, rollback, and technician-facing evidence;
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

The current profile fixes the intended terminal stack to:

```text
Windows -> WezTerm -> WSL -> tmux -> OpenCode / AGY / Goose
```

The profile is fail closed around these safety properties:

- install missing components only;
- preserve existing user configuration;
- never authenticate accounts automatically;
- never contact or mutate deployment targets;
- never commit runtime evidence, credentials, or machine-local paths.

## Proof ceiling

The contract test can prove schema shape, repository-boundary declarations, sanitized tracked configuration, and validation-runner registration. It cannot prove:

- WezTerm, WSL, tmux, or any coding agent is installed;
- AgentSwitchboard exposes a stable executable command;
- installation, repair, upgrade, authentication readiness, or launch behavior works;
- Windows elevation and rollback behavior;
- end-to-end workstation provisioning.

Those require later bounded implementation and Windows fixture/runtime sprints.

## Next implementation seam

Before adding an executable SysAdminSuite installer, AgentSwitchboard must publish a stable, versioned invocation and result contract. The SysAdminSuite adapter should then validate that contract, invoke it without forwarding secrets, and translate its normalized PASS/SKIP/FAIL results into a SysAdminSuite evidence summary.
