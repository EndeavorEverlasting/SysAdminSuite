# SysAdminSuite Repository Directory Structure

## Purpose

SysAdminSuite commands must not assume the operator is already in the right directory. Every runnable instruction should start by entering the repository root, then use repo-relative paths.

This document establishes the canonical app root, sibling worktree layout, source directories, generated-output directories, and command preamble for local operators and agents.

## App root contract

The app root is the checked-out `SysAdminSuite` repository directory: the directory that contains `.git`, `README.md`, `docs/`, `scripts/`, `survey/`, `harness/`, and `Tests/`.

Use the helper script when you do not know where the current shell is:

```powershell
.\scripts\Enter-SysAdminSuite.ps1
```

If you are outside the repo, pass the clone path explicitly:

```powershell
.\scripts\Enter-SysAdminSuite.ps1 -RepoRoot "C:\path\to\SysAdminSuite"
```

After the helper runs, commands should use repo-relative paths.

## Local clone and sibling worktree pattern

SysAdminSuite should emulate the Blacksmith Guild local layout: one stable primary clone plus sibling directories for validation, PR, and sprint worktrees.

Blacksmith Guild reference pattern:

```text
C:\Users\Cheex\Desktop\dev\Mods\Bannerlord\BlacksmithGuild
C:\Users\Cheex\Desktop\dev\Mods\Bannerlord\BlacksmithGuild-037a-validation
C:\Users\Cheex\Desktop\dev\Mods\Bannerlord\BlacksmithGuild-pr23
C:\Users\Cheex\Desktop\dev\Mods\Bannerlord\BlacksmithGuild-pr25-launcher-evidence
C:\Users\Cheex\Desktop\dev\Mods\Bannerlord\BlacksmithGuild-pr27-duration-guard
```

SysAdminSuite equivalent pattern:

```text
<dev-root>\SysAdminSuite
<dev-root>\SysAdminSuite-<sprint-or-validation-name>
<dev-root>\SysAdminSuite-pr<NUMBER>
<dev-root>\SysAdminSuite-pr<NUMBER>-<short-scope>
<dev-root>\SysAdminSuite-<sprint-id>-<short-scope>
```

Suggested concrete Windows layout:

```text
C:\Users\Cheex\Desktop\dev\SysAdminSuite\SysAdminSuite
C:\Users\Cheex\Desktop\dev\SysAdminSuite\SysAdminSuite-pr149-windows-log-classifier
C:\Users\Cheex\Desktop\dev\SysAdminSuite\SysAdminSuite-log-classifier-validation
C:\Users\Cheex\Desktop\dev\SysAdminSuite\SysAdminSuite-harness-validation
```

The primary clone should remain the ordinary working copy. Sibling worktrees should be used when a branch is dirty, conflicted, experimental, or validating a PR without disturbing the primary clone.

## Worktree naming rules

Use these names for sibling worktrees:

| Case | Pattern | Example |
| --- | --- | --- |
| PR validation | `SysAdminSuite-pr<NUMBER>-<short-scope>` | `SysAdminSuite-pr149-windows-log-classifier` |
| Sprint branch | `SysAdminSuite-<sprint-id>-<short-scope>` | `SysAdminSuite-logs-classifier-implementation` |
| Validation lane | `SysAdminSuite-<scope>-validation` | `SysAdminSuite-log-classifier-validation` |
| Dirty primary escape | `SysAdminSuite-<branch-short-name>-validation` | `SysAdminSuite-harness-validation` |

Keep worktree names short, lowercase where practical, and specific enough to identify the PR/sprint from File Explorer and terminal prompts.

## Required command preamble

Every human-facing PowerShell command block should start with one of these forms.

Known local clone path:

```powershell
Set-Location "C:\Users\Cheex\Desktop\dev\SysAdminSuite\SysAdminSuite"
```

Known sibling worktree path:

```powershell
Set-Location "C:\Users\Cheex\Desktop\dev\SysAdminSuite\SysAdminSuite-pr149-windows-log-classifier"
```

Already somewhere inside the repo:

```powershell
.\scripts\Enter-SysAdminSuite.ps1
```

Unknown current directory but known clone path:

```powershell
.\scripts\Enter-SysAdminSuite.ps1 -RepoRoot "C:\Users\Cheex\Desktop\dev\SysAdminSuite\SysAdminSuite"
```

Do not give a command that starts with `bash tests/...`, `python3 harness/...`, `powershell -File ...`, or `git ...` unless it first establishes the app root.

## Creating a sibling worktree

Use the repo helper from the primary clone when creating a sibling worktree:

```powershell
Set-Location "C:\Users\Cheex\Desktop\dev\SysAdminSuite\SysAdminSuite"
.\scripts\New-SysAdminSuiteWorktree.ps1 `
  -Name "SysAdminSuite-pr149-windows-log-classifier" `
  -Branch "sprint/windows-log-classification-system" `
  -StartPoint "main"
```

Then work from the sibling path:

```powershell
Set-Location "C:\Users\Cheex\Desktop\dev\SysAdminSuite\SysAdminSuite-pr149-windows-log-classifier"
```

## Canonical tracked directories

```text
.
├── docs/                         Human-readable doctrine, contracts, and operating guides
├── harness/                      Local harness APIs, manifests, taxonomy, and implementation code
│   ├── api/                      Harness API manifests
│   └── taxonomy/                 Machine-readable classifiers and controlled vocabularies
├── mcp/local/                    Local MCP server catalog and planned server contracts
├── schemas/harness/              JSON schemas for harness artifacts and taxonomies
├── scripts/                      Operator entrypoints and shared PowerShell modules
│   └── powershell/               General PowerShell utilities
├── survey/                       Survey planners, renderers, input/output conventions
│   ├── input/                    Generated or staged local inputs; usually gitignored unless fixtures
│   └── output/                   Generated local outputs; gitignored runtime evidence
├── targets/                      Target intake documentation and non-secret templates
├── Tests/                        Contract tests and validation scripts
│   ├── bash/                     Bash/static shell contracts
│   └── survey/                   Python/static survey and harness contracts
└── tests/                        Existing lower-case test runner paths and legacy tests
    └── survey/                   Offline survey runner and lowercase test suite
```

## Generated-output boundary

Generated runtime evidence belongs under ignored local output roots, not committed source paths.

Preferred local output roots:

```text
survey/output/<workflow>/<run_id>/
runs/<workflow_id>/
logs/local/<workflow>/<run_id>/
```

Do not commit:

```text
*.evtx
*.etl
*.pcap
*.pcapng
crash dumps
machine-local logs
credential-bearing exports
live client evidence
```

Synthetic fixtures may be committed only when scrubbed and clearly marked as fixtures.

## Canonical run directory shape

For new harness workflows, prefer this run shape:

```text
runs/<workflow_id>/
├── request/      Original operator request or normalized request JSON
├── context/      Local context gathered from repo artifacts only
├── plan/         Rendered low-noise plan and safety classification
├── actions/      Operator-visible command handoffs
├── artifacts/    Generated local artifacts, summaries, and manifests
├── evidence/     Evidence pointers or scrubbed fixture evidence
├── reports/      English-readable reports
├── review/       Human review notes and unresolved items
└── summary/      Machine-readable summary JSON
```

## Windows log classifier locations

Tracked source:

```text
harness/windows_log_classifier.py
harness/taxonomy/windows-log-taxonomy.json
schemas/harness/windows-log-taxonomy.schema.json
scripts/Invoke-WindowsLogClassifier.ps1
Tests/survey/test_windows_log_classification_contracts.py
Tests/survey/test_windows_log_classifier_code.py
```

Local generated output:

```text
survey/output/windows-log-classifier/<run_id>/n```

## Example: safe classifier run from an unknown shell

```powershell
.\scripts\Enter-SysAdminSuite.ps1 -RepoRoot "C:\Users\Cheex\Desktop\dev\SysAdminSuite\SysAdminSuite"
.\scripts\Invoke-WindowsLogClassifier.ps1 `
  -Target System `
  -Operation "show recent errors" `
  -Emit plan
```

## Example: repository validation from an unknown shell

```powershell
.\scripts\Enter-SysAdminSuite.ps1 -RepoRoot "C:\Users\Cheex\Desktop\dev\SysAdminSuite\SysAdminSuite"
bash tests/survey/run_offline_survey_tests.sh
```

## Agent rule

When producing a command for this repo, include the app-root step. If the actual clone path differs from the documented `C:\Users\Cheex\Desktop\dev\SysAdminSuite\...` convention, use the real local clone path in the `Set-Location` or `-RepoRoot` line. Do not omit the directory step.
