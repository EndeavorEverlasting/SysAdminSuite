# Local Reference Policy

SysAdminSuite may use a **gitignored local reference tree** at the repo root: install scripts,
shortcuts, and installers copied from field practice. That tree is **not product code** and must
never be committed, pushed, or named in public docs, PR descriptions, or issue comments.

## Rules

1. **Gitignore only** — Keep reference material in the gitignored directory at repo root (exact
   folder name is local and must not appear in tracked docs). Legacy folder names may exist on disk
   until renamed. Do not add paths to the index.
2. **No revealing paths in public artifacts** — Do not commit absolute Windows paths, Windows
   usernames, hostnames from your workstation, or the local reference folder name in tracked
   `docs/`, `README`, PR bodies, or runbooks.
3. **Promote patterns, not copies** — When a reference script proves useful, extract the *behavior*
   (registry keys, OU checks, probe sequence) into `survey/`, `scripts/`, `deployment-audit/`, or
   `docs/` using generic language. Do not copy the reference tree into the repo.
4. **Runtime outputs** — CSV/HTML from live assessments and GUI worker sessions may contain PII;
   keep them under ignored `survey/output/` and `Mapping/Output/GuiRuns/` (and `mapping/`
   case variants on Windows).

## For agents

- Default new docs to **“gitignored local reference tree”** or **“operator-local reference
  install script”** — not folder names, usernames, or absolute user-profile paths.
- Before opening a PR, search the diff for `Users\`, personal names used as directory labels, and
  on-disk reference folder names; redact before push.
- See also `AGENTS.md` (local reference guardrail).
