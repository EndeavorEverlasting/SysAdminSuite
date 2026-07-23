# SysAdminSuite Operational Harness Status

## Current state

The repository has an operational harness floor for fresh-agent intake, task routing, scoped validation, artifact production, local hooks, English reporting, and next-agent handoff. The machine-readable authority is `harness/api/operational-harness-manifest.json`; this report is the human-readable view.

## Working

- **Repository orientation:** `AGENTS.md` defines governance and `CODEBASE_MAP.md` routes agents to the smallest relevant surface.
- **Workflow selection:** scoped skills and machine-readable routing manifests distinguish repository, validation, field, survey, package, workstation, and AutoLogon work.
- **Local/remote boundary:** `harness/workflows/operational-harness-maintenance.yaml` remains network-free; operator-approved Git push and pull-request publication are isolated in `harness/workflows/operational-harness-publish.yaml`.
- **Run context and artifacts:** `scripts/SasRunContext.psm1` creates bounded run roots, per-run artifact registries, reports, review paths, and operator handoffs.
- **Validation:** dependency-free Python contracts, Pester suites, Bash syntax checks, schemas, manifests, dedicated workflows, and default E2E profiles are available.
- **Hooks:** `.githooks/pre-commit` blocks generated/private evidence and runs focused contracts; `.githooks/pre-push` runs the offline harness floor and validates commits against the actual destination ref.
- **Reports and handoff:** English report renderers and `tools/New-SasSprintCapsule.ps1` provide human summaries and compressed handoffs.
- **Repository text policy:** `.gitattributes` classifies CMD/BAT, shell/fixture files, JSONL, and binaries without forcing Windows worktree rewrites. `scripts/check-repo-text-policy.py` independently enforces canonical LF bytes and no trailing whitespace in every changed Git text blob. PowerShell, JSON, documentation, and other existing formats retain their established checkout behavior.

## Repaired boundary

A prior push-only whitespace check reported every line of a Windows CMD file as trailing whitespace because the Git blob contained CRLF bytes. The harness now validates the bytes stored in Git without forcing checkout conversion. Future changed text blobs are checked through the same staged, destination-range, PR, and pushed-commit validator, while a focused Windows CI gate proves the AI validator leaves a clean worktree before Sprint Capsule handoff generation.

## Known gaps and proof limits

- Existing historical blobs are not rewritten wholesale by this sprint; the text-policy validator applies when a text file is changed and blocks noncanonical stored bytes.
- Repository hooks are tracked but must be enabled once per clone with `bash scripts/install-local-harness-hooks.sh`.
- Static and fixture passes do not prove live target reachability, deployment success, application behavior, reboot behavior, or technician acceptance.
- Generated run evidence remains local under ignored `survey/output/` roots and must not be committed.

## Operator validation

Run the focused harness floor from the repository root:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'
python .\Tests\survey\test_operational_harness_completeness_contracts.py
python .\scripts\check-repo-text-policy.py --commit HEAD
python .\Tests\survey\test_local_harness_contracts.py
git diff --check
```

Run the broader offline floor when the focused checks pass:

```bash
bash tests/survey/run_offline_survey_tests.sh
```

## Expected result

A complete harness reports every required component as present and tracked, validates the central manifest and artifact registry, proves hook and CI wiring, confirms the line-ending attributes, and exits with:

```text
PASS: operational harness completeness
```
