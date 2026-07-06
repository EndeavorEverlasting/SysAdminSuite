# SysAdminSuite AI Harness Guide

## Source of truth

Read `AGENTS.md`, `docs/HARNESS_COMPLETION_PLAN.md`, and `docs/ENGLISH_LOG_ARTIFACT_CONTRACT.md` before planning AI-assisted work. Do not duplicate those planning docs; use this file as the agent/workflow front door.

## Operating rules

- Keep SysAdminSuite Bash-first for Northwell-targeted field work.
- Preserve all `.ps1`, `.psm1`, and `.psd1` files unless the user explicitly asks for PowerShell changes.
- Treat survey and dashboard probes as authorized, read-only validation that writes local evidence only.
- Keep changes scoped, bounded, dry-run friendly, and validation-first.
- Keep live target material, workbooks, host lists, serial lists, MAC exports, scan output, ZIP bundles, dashboards, and local evidence out of commits.
- Use `.claudeignore`, `.gitignore`, `docs/LOCAL_REFERENCE_POLICY.md`, and `targets/README.md` before opening or staging local data.
- Use low-noise survey discipline and the suite wrappers for reachability validation.
- For dashboard field users, keep the double-click launcher as the default front door.

## Required workflow loop

1. Classify the request: docs/config only, survey harness, runtime code, dashboard, mapping, or validation.
2. Load the smallest relevant context using `CODEBASE_MAP.md`.
3. Run the live-data guard before reading, generating, or staging artifacts.
4. Make the smallest safe change.
5. Run scoped validation. Prefer static validators for docs/config changes.
6. Summarize what changed, what was intentionally not changed, and the exact validation command.

## Harness skills

- `.claude/skills/scoped-validation/SKILL.md` — choose bounded checks for a change.
- `.claude/skills/live-data-guard/SKILL.md` — keep local data and operator evidence out of AI context and commits.
- `.claude/skills/survey-low-noise/SKILL.md` — preserve low-noise survey doctrine.

## Safety vocabulary

Preferred wording: authorized, read-only, low-noise, scoped, bounded, local evidence, dry-run, validation-first, operator-approved, local ignored paths.
