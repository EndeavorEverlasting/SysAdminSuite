# Language and Runtime Skill

Use this skill when choosing an implementation language, shell, runtime, wrapper, or compatibility path.

## Capability dependencies

- [Language Runtime Selection](../../capabilities/language-runtime-selection.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)

## Workflow

1. Identify the actual environment and current implementation surface.
2. Classify the operation: survey/preflight, Windows-native administration, dashboard/managed code, or quick local check.
3. Reuse the existing language and entrypoint when it already owns the behavior.
4. For suitable new Northwell survey work, prefer Bash-on-Windows.
5. For Windows-native capabilities, use and maintain PowerShell rather than forcing a Bash imitation.
6. Preserve parallel implementations and document their boundary when both are required.
7. Validate with the language-appropriate tests named in the scoped-validation skill.

## Guardrails

- Do not assume Bash means Linux, WSL, or a POSIX-only stack.
- Do not treat PowerShell as dead or deprecated.
- Do not introduce a second implementation merely to satisfy a language preference.
