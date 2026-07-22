# Agent Governance for SysAdminSuite

`AGENTS.md` is the repository-root governance contract and the single source of truth for how agents operate in SysAdminSuite. Compact routing lives here; detailed procedures remain in task skills under `.claude/skills/`, reusable rules in `.claude/capabilities/`, and machine-readable execution contracts under `harness/`.

## Required loading sequence
1. Read this governance contract.
2. Inspect the current Git state and preserve existing work.
3. Use `CODEBASE_MAP.md` to locate the smallest relevant surface.
4. Use `harness/api/agent-routing-manifest.json` for exact task signals; unknown or conflicting signals fail closed to the repository-sprint skill.
5. Load only the selected skill and its declared capability dependencies.
6. Read deeper product or harness documentation only when the selected route points to it.

Triggers route work only. They never authorize network activity, target mutation, destructive Git operations, secret handling, or proof claims. Progressive disclosure is a repository requirement; do not preload every skill, capability, plan, or handoff.

## Agent operating principles
- **Evidence before action:** inspect repository, branch, PR, worktree, contracts, and existing evidence before mutation.
- **Floor before furniture:** establish governance, safety boundaries, validation, and rollback before convenience features.
- **Bounded sprints with declared scope:** every writing sprint declares its lane, mission, owned scope, forbidden scope, artifacts, validation, and proof ceiling.
- **One writer per branch:** parallel agents use isolated branches or worktrees and do not make competing writes.
- **Reuse before replacing:** search for canonical authorities, helpers, scripts, schemas, validators, and naming patterns before inventing.
- **No completion without proof:** plans, acknowledgments, summaries, generated text, and unexecuted commands are not completion.

## Instruction precedence
When instructions conflict, use this order:
1. Platform, security, legal, and repo-owner instructions.
2. This governance contract.
3. Task-specific prompts.
4. Generic defaults.

At the same level, stop expansion, identify the conflicting authorities, and make the smallest safe correction that restores one source of truth.

## Mandatory sprint declaration
Before every writing sprint, state:
- repo and branch;
- lane and mission;
- owned scope and forbidden scope;
- expected artifacts and validation commands;
- proof ceiling: the highest claim the planned evidence can support.

Preserve existing work and keep mutation inside owned scope. Checkpoint coherent tracked work before broad validation, long diagnostics, runtime proof, or refactoring expansion.

## Device-profile and deployment doctrine
- Establish the equipment profile before configuration or package selection. Serial number, hostname, MAC address, model, subnet, or probe response is identity evidence, not permission to infer a profile.
- Profiles are separate authorities. Cybernet, shared/user-login workstation, Neuron, tablet, Kronos clock, and any other equipment class must never inherit one another's settings, packages, probes, validators, or completion claims.
- Unknown, ambiguous, conflicting, or unsupported profile evidence fails closed to read-only review. A probe must report the mismatch and must not relabel the device, select a package set, or mutate it.
- The current Cybernet clinical-workstation authority is `Config/cybernet-client-preferences.json`; its standards apply only after the target is proven eligible for that profile.
- AutoLogon is forbidden on every shared/user-login workstation profile. A package set containing AutoLogon is invalid for that profile and must stop before deployment.
- Whenever AutoLogon is selected for an eligible non-shared profile, it must be the final package and final mutating configuration step. Complete all other software and settings first; only validation, technician acceptance, and a separately authorized reboot may follow.
- A successful probe or test for one profile is not proof for another profile. Cross-profile conflation is a blocking defect, not a warning.

## SysAdminSuite virtual-machine doctrine
- The SysAdminSuite VM is Python-generated. Never assume Hyper-V, invent a VM name, or substitute a provider-specific launcher without repository or operator evidence.
- Before VM-dependent work, locate the canonical Python generator/launcher and its documented guest identity, startup, readiness, shutdown, rollback, and evidence paths.
- A complete VM workflow includes: start or resume the VM, wait for guest and network readiness, execute the requested action inside the intended guest, capture sanitized evidence, and perform the required shutdown, rollback, or destruction step.
- Do not hand over only an inner guest command when the task requires the VM to be started from the admin box.
- Use the VM for isolated package qualification, management-boundary network or Kerberos certification, reproducible Windows runtime proof, and other tasks whose evidence must originate inside that guest.
- Do not start the VM for static analysis, documentation-only work, offline validators, or an approved host-native workflow that does not require guest evidence.
- If the canonical Python startup authority is absent or cannot be proven, report that exact gap; do not fabricate a launcher.

## Universal invariants
- Treat repository and current Git evidence as authoritative over remembered conversation context.
- Never commit secrets, credentials, personal data, live targets, machine-local paths, raw runtime evidence, generated logs, or local reference material.
- Survey and dashboard probe lanes are read-only toward targets; deployment or repair mutation requires explicit authorization and its lane-specific gate.
- Do not claim a higher proof level than the evidence supports. Static checks, launcher success, command acknowledgment, observed behavior, and live runtime proof are distinct.
- Preserve active PowerShell tooling. Bash-first does not mean PowerShell is dead, deprecated, or safe to delete.
- Use short technician entrypoints and hide composition complexity behind repository-owned scripts, launchers, profiles, and evidence summaries.

## Skill router
| Task signal | Load this skill |
|---|---|
| Repository intake, sprint selection, Git/PR lifecycle, interrupted work recovery | [Repository Sprint](.claude/skills/repository-sprint/SKILL.md) |
| Choosing Bash, PowerShell, Windows-native, or managed implementation surfaces | [Language and Runtime](.claude/skills/language-runtime/SKILL.md) |
| Technician commands, double-click launchers, field runbooks, QR command capsules | [Field Workflow](.claude/skills/field-workflow/SKILL.md) |
| Selecting parsers, unit tests, contracts, and bounded validators | [Scoped Validation](.claude/skills/scoped-validation/SKILL.md) |
| Integration gates, composed workflows, browser/launcher journeys, merge/release proof | [End-to-End Validation](.claude/skills/end-to-end-validation/SKILL.md) |
| Reading, generating, moving, or staging local/live evidence | [Live Data Guard](.claude/skills/live-data-guard/SKILL.md) |
| Survey, preflight, target intake, Naabu/Nmap, packet probes, dashboard probes | [Survey Low-Noise](.claude/skills/survey-low-noise/SKILL.md) |
| WezTerm/tmux setup, persistent coding workspace, workstation repair, or agent readiness | [Developer Workstation](.claude/skills/developer-workstation/SKILL.md) |
| EXE/MSI/archive inspection, installer behavior inference, large private package intake | [Package Static Analysis](.claude/skills/package-static-analysis/SKILL.md) |
| AutoLogon planning, canonical admin deployment, post-reboot session or technician runtime proof | [AutoLogon Deployment](.claude/skills/autologon-deployment/SKILL.md) |

## Canonical repo authorities
- `CODEBASE_MAP.md` — minimal context routing.
- `docs/AI_HARNESS_ENTRYPOINT.md` and `docs/HARNESS_DISCIPLINE.md` — fresh-agent, Git, branch, PR, worktree, and evidence discipline.
- `docs/END_TO_END_TESTING_POSTURE.md` — validation and merge/release proof posture.
- `docs/VM_DRY_RUN_READINESS.md` and `docs/PACKAGE_VM_QUALIFICATION_PROFILES.md` — current VM safety and proof ceilings.
- `Config/operational-posture.json`, `Config/cybernet-client-preferences.json`, and `docs/OPERATIONAL_POSTURE.md` — lane, mutation, and current Cybernet profile authority.
- `harness/api/agent-capability-manifest.json` and `harness/api/agent-routing-manifest.json` — machine-readable capability and routing authority.
- `harness/workflows/agent-sprint-capsule.yaml` and `tools/New-SasSprintCapsule.ps1` — final handoff compression.
- `tools/validate-ai-layer.ps1` and `Tests/survey/test_agent_governance_doctrine_contracts.py` — instruction and governance enforcement.

## Completion standard
A task is complete only when:
1. changed files are named;
2. validation commands were actually run and exact results reported;
3. a commit SHA exists;
4. push and PR state are reported;
5. one exact next command is given.

Also report skipped checks, remaining gaps or risks, and the proof ceiling reached. A green static validator is not automatically runtime, target, deployment, or operator-acceptance proof.

## Forbidden behaviors
- Acknowledgment without mutation when mutation is authorized and required.
- Plans without execution.
- Summaries without proof.
- Completion claims without running checks.
- Secret, credential, live-target, or private-evidence exposure.
- Destructive cleanup, force-push, default-branch mutation, or scope expansion without explicit authority.
