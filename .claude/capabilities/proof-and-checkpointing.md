# Proof and Checkpointing Capability

## Contract

Preserve useful work before expensive expansion and report only the proof actually reached.

## Checkpoint rule

Checkpoint the first coherent tracked change before broad validation, long diagnostics, runtime proof, or larger refactoring. A valid checkpoint is a bounded commit, a complete patch, or another repo-approved recovery artifact.

A checkpoint proves preservation only. It does not prove correctness, completion, merge readiness, or runtime behavior.

## Proof ladder

Use these levels separately:

1. contract proof;
2. harness proof;
3. static test proof;
4. build proof;
5. launcher or browser proof;
6. command ACK proof;
7. behavior observed proof;
8. live runtime proof;
9. operator acceptance proof when the workflow requires it.

Never promote a lower level to a higher one. Green CI does not replace controlled runtime evidence.

## Validation reporting

- Run the smallest deterministic check covering the change first.
- Add broader checks only when practical and relevant.
- Name failures and exact skipped commands.
- Review final Git diff and status before delivery.
- Keep raw runtime evidence outside git unless a sanitized tracked artifact is explicitly required.

## Used by

- `.claude/skills/repository-sprint/SKILL.md`
- `.claude/skills/scoped-validation/SKILL.md`
- `.claude/skills/survey-low-noise/SKILL.md`
