# Agent Instructions for SysAdminSuite

`AGENTS.md` is the compact, agent-agnostic entrypoint. It contains only universal invariants and routing. Detailed procedures live in task skills under `.claude/skills/`; stable reusable rules live in `.claude/capabilities/`.

## Required loading sequence

1. Read this file.
2. Use `CODEBASE_MAP.md` to locate the smallest relevant repo surface.
3. Use `harness/api/agent-routing-manifest.json` when the request matches an exact deterministic task signal; unknown or conflicting signals fail closed to the repository-sprint skill.
4. For a `skill` route, load only the selected skill and its declared capability dependencies.
5. For a `harness_operation` route, collect every declared `required_inputs` value and apply the registered workflow input mapping before invoking its repo-owned entrypoint.
6. Read deeper product or harness docs only when the selected skill or operation points to them.

Triggers route work only. They never authorize network activity, target mutation, destructive Git operations, or proof claims. A harness-operation route is not a skill and cannot omit mandatory operation inputs.

Do not preload every skill, capability, plan, or handoff. Progressive disclosure is a repository requirement.

## Universal invariants

- Treat the repository and current Git state as the source of truth over remembered chat context.
- Preserve existing work. Inspect dirty files before switching, restoring, cleaning, rebasing, or deleting.
- State repo, branch, PR/sprint, lane, owned scope, forbidden scope, and expected artifacts before mutation.
- Keep changes bounded. Reuse existing contracts, helpers, schemas, workflows, and validators before inventing new ones.
- Checkpoint coherent tracked work before broad validation, long diagnostics, runtime proof, or refactoring expansion.
- Never commit secrets, credentials, personal data, live targets, machine-local paths, raw runtime evidence, generated logs, or local reference material.
- Survey and dashboard probe lanes are read-only toward targets. Deployment or repair mutation requires explicit authorization and its lane-specific gate.
- Do not claim a higher proof level than the evidence supports. Static checks, launcher success, command ACK, observed behavior, and live runtime proof are distinct.
- Preserve active PowerShell tooling. Bash-first does not mean PowerShell is dead, deprecated, or safe to delete.
- Use short, repeatable technician entrypoints. Hide composition complexity behind repo-owned scripts, launchers, profiles, and evidence summaries.

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

Load multiple skills only when the task genuinely crosses lanes. A skill may compose several capabilities; do not copy capability text into a new prompt.

## Source-of-truth precedence

When instructions appear to conflict, use this order:

1. Explicit user scope and safety constraints.
2. This file's universal invariants.
3. The selected skill.
4. The capability dependencies named by that skill.
5. Canonical machine-readable policy, schemas, routing, and workflow specs.
6. Product docs and runbooks.
7. Historical plans, handoffs, PR bodies, and comments.

If two same-level sources conflict, stop expansion, cite both paths, and make the smallest correction that restores one authority.

## Canonical repo authorities

- `docs/AI_HARNESS_ENTRYPOINT.md` — fresh-agent inspection, routing, artifact, validation, and handoff sequence.
- `CODEBASE_MAP.md` — minimal context routing.
- `harness/api/agent-capability-manifest.json` — complete skill and capability inventory.
- `harness/api/agent-routing-manifest.json` — deterministic task-signal routing and ambiguity rules.
- `harness/workflows/agent-sprint-capsule.yaml` and `tools/New-SasSprintCapsule.ps1` — final handoff compression using the canonical run context and artifact registry.
- `Config/operational-posture.json` and `docs/OPERATIONAL_POSTURE.md` — lane and mutation posture.
- `docs/HARNESS_DISCIPLINE.md` — full Git/PR/worktree operation contract.
- `docs/END_TO_END_TESTING_POSTURE.md` — default validation and merge/release proof posture.
- `docs/LOCAL_REFERENCE_POLICY.md`, `.gitignore`, and `.claudeignore` — local data boundaries.
- `survey/naabu_profiles.json` — approved Naabu doctrine profiles.
- `tools/validate-ai-layer.ps1` — manifest-driven agent instruction, skill, capability, routing, and handoff validation.

## Delivery floor

Before reporting completion:

1. Review `git diff --check`, `git status --short`, `git diff --stat`, and the final diff when locally available.
2. Run targeted diagnostics, then the selected skill's required proof gate, then broader checks.
3. Report exact passes, failures, and skipped commands.
4. Report changed files, commit SHA, push/PR state, remaining gaps, proof level, and one exact next command.
5. When another agent or chat must continue, generate a schema-backed sprint capsule; do not paste an unbounded transcript as the handoff.
