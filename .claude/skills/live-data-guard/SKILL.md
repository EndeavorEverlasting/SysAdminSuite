# Live Data Guard Skill

Use this skill before reading, creating, moving, staging, or committing files that may contain operator-local or live environment data.

## Protected material

Do not commit live target CSVs, workbooks, host lists, serial lists, MAC exports, scan output, Nmap/Naabu logs, dashboards, ZIP bundles, local evidence, user-profile paths, or local reference-tree paths/names.

## Allowed tracked material

- Synthetic fixtures, samples, examples, and templates in approved tracked locations.
- Documentation that describes generic local paths without revealing operator-local folder names.
- Validators that inspect file names and content without opening live artifacts.

## Required checks

1. Review `.claudeignore`, `.gitignore`, `docs/LOCAL_REFERENCE_POLICY.md`, and `targets/README.md` when local data may be nearby.
2. Use `git status --short` before committing.
3. Inspect the diff for local paths, usernames, hostnames, and live artifact names.
4. Keep evidence in local ignored paths such as `survey/output/`, `survey/artifacts/`, `logs/nmap/`, or `logs/targets/`.

## Preferred wording

Use authorized, read-only, local evidence, scoped, bounded, dry-run, and validation-first.
