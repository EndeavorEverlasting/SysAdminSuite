# SysAdminSuite AI Harness Guide

## Source of truth

Start with `AGENTS.md` and `CODEBASE_MAP.md`. `AGENTS.md` is intentionally compact: it routes the task to the smallest relevant skill under `.claude/skills/`, and each skill names the reusable capability files it depends on.

Do not preload `docs/HARNESS_COMPLETION_PLAN.md`, `docs/ENGLISH_LOG_ARTIFACT_CONTRACT.md`, every skill, or every capability for unrelated work. Read deeper plans and contracts only when the selected skill or codebase map points to them.

## Operating rules

- Treat the repository and current Git state as operational truth.
- Preserve active Bash, PowerShell, Windows-native, and managed surfaces according to the language-runtime skill.
- Treat survey and dashboard probes as authorized, read-only validation that writes local evidence only.
- Keep changes scoped, bounded, dry-run friendly, and validation-first.
- Use E2E as the default merge/release proof target for executable or integration-affecting changes.
- Keep live targets, workbooks, host/serial/MAC lists, scan output, ZIP bundles, dashboards, and local evidence out of commits.
- Use `.claudeignore`, `.gitignore`, `docs/LOCAL_REFERENCE_POLICY.md`, and `targets/README.md` before opening or staging local data.
- Keep double-click or one-command field entrypoints as the default technician front door.

## Progressive-disclosure workflow

1. Read `AGENTS.md`.
2. Classify the request using the skill router.
3. Load only the selected `SKILL.md` files.
4. Load only their declared capability dependencies.
5. Use `CODEBASE_MAP.md` to open the smallest relevant implementation and validation surface.
6. Make the smallest safe change.
7. Run targeted diagnostics, the applicable E2E journey, and broader checks.
8. Report the exact proof level and unrun higher gates.

## Skill catalog

- `.claude/skills/repository-sprint/SKILL.md` — repository evidence, sprint selection, Git/PR lifecycle, and interrupted work recovery.
- `.claude/skills/language-runtime/SKILL.md` — choose Bash, PowerShell, Windows-native, or managed implementation surfaces.
- `.claude/skills/field-workflow/SKILL.md` — technician entrypoints, launchers, menus, QR capsules, and operator handoffs.
- `.claude/skills/scoped-validation/SKILL.md` — choose bounded diagnostic checks for a change.
- `.claude/skills/end-to-end-validation/SKILL.md` — prove composed workflows through real entrypoints and result paths.
- `.claude/skills/live-data-guard/SKILL.md` — keep local data and operator evidence out of AI context and commits.
- `.claude/skills/survey-low-noise/SKILL.md` — preserve low-noise survey doctrine.

Capability catalog: `.claude/capabilities/README.md`.

## Safety vocabulary

Preferred wording: authorized, read-only, low-noise, scoped, bounded, local evidence, dry-run, validation-first, operator-approved, and local ignored paths.
