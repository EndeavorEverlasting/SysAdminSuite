# Mainline State — 2026-05-27

Authoritative snapshot of `origin/main` after the 2026-05-27 convergence sprint (#33–#38). Complements [BRANCH_CONVERGENCE_2026-05-27.md](BRANCH_CONVERGENCE_2026-05-27.md) (not edited in this sprint).

## 1. Snapshot

| Field | Value |
|-------|--------|
| Date | 2026-05-27 |
| Full SHA | `6d828657b86d509b406ee9093137d25abd5a8c68` |
| Short SHA | `6d82865` |
| Branch | `main` |
| `origin/main` sync | Up to date after `git fetch --all --prune && git pull origin main` |
| Top commit message | `docs: add remote-first workflow guide for GitHub-centric development` |

Verify locally:

```bash
git fetch origin && git rev-parse HEAD && git rev-parse --short HEAD
```

## 2. Commands cited (2026-05-27)

### `git rev-parse HEAD`

```
6d828657b86d509b406ee9093137d25abd5a8c68
```

### `git log --oneline --decorate --max-count=40`

```
6d82865 (HEAD -> main, origin/main, origin/HEAD) docs: add remote-first workflow guide for GitHub-centric development
3ad472e Merge pull request #38 from EndeavorEverlasting/feature/autologon-preflight-2026-05-27
c0b4a1f feat(survey): wire autologon preflight and remote-first docs
8440e93 (tag: archive/convergence-2026-05-27) Merge pull request #37 from EndeavorEverlasting/docs/convergence-final-ledger-2026-05-27
5e09732 Record completed branch convergence outcomes in 2026-05-27 ledger.
2fedcb0 feat(survey): add read-only auto-logon workstation assessment
955563e Merge pull request #36 from EndeavorEverlasting/feature/nmap-cybernet-audit-v2
7a42947 Port deployment-audit Nmap Cybernet workflow from PR #10 onto current main.
3dd3145 Merge pull request #35 from EndeavorEverlasting/feature/neuron-runtime-harvest-2026-05-27
a0b2bcf Merge Neuron runtime tools from harvest/neuron-runtime-current-main-v2
443e25d Merge pull request #34 from EndeavorEverlasting/docs/branch-convergence-2026-05-27
35db948 Document remote-first workflow and 2026-05-27 branch convergence ledger.
bb7440b Merge remote-tracking branch 'origin/codex/build-orchestrator-and-bash-wrapper-for-pipeline' into integration/registry-install-diff-2026-05
dfe425c Merge remote-tracking branch 'origin/codex/implement-tracked-installer-runner' into integration/registry-install-diff-2026-05
af24b29 Merge remote-tracking branch 'origin/codex/implement-registry-snapshot-comparison-script' into integration/registry-install-diff-2026-05
935d2df Merge remote-tracking branch 'origin/codex/implement-registry-snapshot-capture-layer' into integration/registry-install-diff-2026-05
941d659 Merge remote-tracking branch 'origin/codex/implement-target-readiness-checks-for-pipeline' into integration/registry-install-diff-2026-05
32f4678 Merge remote-tracking branch 'origin/codex/add-json-schemas-and-example-configs' into integration/registry-install-diff-2026-05
d8d5021 Merge remote-tracking branch 'origin/codex/create-documentation-for-registry-install-diff-pipeline' into integration/registry-install-diff-2026-05
1f83842 Add numeric hostname availability evidence workflow
b282fcf Harvest Neuron runtime tools onto current main
3e0a218 Assert Neuron name survey authorization guard
d956790 Require explicit authorization for live Neuron name discovery
ed28e12 Ignore SysAdminSuite survey runtime artifacts
0fc654f Add registry install diff orchestrator and wrapper
335a159 Add tracked installer runner
a6c0b2c Add registry snapshot diff script
1afe4cc Add registry snapshot capture script
7a2a019 Add target readiness checks for registry install diff
f7f4c81 Add registry install diff schemas and examples
23b9115 Document registry install diff pipeline
afb001c Document Neuron name availability wrapper safely
ba580cb Cover Neuron name availability survey wrapper
63db8dd Add Neuron name availability survey wrapper
677b7ef Document Neuron name availability workflow
3dd0d47 Add Neuron name availability contract test
c69c38f Add sample nmap XML for Neuron name availability
d6c1c43 Add Neuron naming availability analyzer
84a79fb Cover Neuron machine info fields in Pester contract
d2d67a3 Add Nmap baseline and classifier workflow
```

### `git tag -l 'archive/*'`

```
archive/convergence-2026-05-27
```

Tag `archive/convergence-2026-05-27` resolves to `8440e9341dcfaeccc950ecf77bd30efa8d34ccc1` (`8440e93`).

## 3. Convergence merge table (#33–#38 + post-merge)

| Item | SHA (short) | Role on main |
|------|-------------|--------------|
| #33 | `1f83842` | Direct commit on main (no merge PR node); numeric hostname availability |
| #34 merge | `443e25d` | Registry install-diff consolidation (23 files, ~2943 insertions) — **not docs-only** |
| #35 merge | `3dd3145` | Neuron runtime PowerShell harvest (replaces #32) |
| #36 merge | `955563e` | `deployment-audit/nmap` Cybernet workflow (replaces #10) |
| #37 merge | `8440e93` | Convergence ledger update + autologon assessment landing |
| #38 merge | `3ad472e` | Autologon preflight via `Test-TargetReadiness` |
| Post-#38 | `6d82865` | `docs/REMOTE_WORKFLOW.md` on main (not carried by #34 tip commit) |

Merge order on main: `1f83842` → `443e25d` → `3dd3145` → `955563e` → `8440e93` → `3ad472e` → `6d82865`.

Note: PR #34 branch tip `35db948` is an empty docs-only commit message; the registry payload entered via the integration branch history merged at `443e25d`.

## 4. Presence check (`git merge-base --is-ancestor <sha> HEAD`)

All convergence anchors are ancestors of current `HEAD` (`6d82865`):

| SHA | Status |
|-----|--------|
| `1f83842` | ancestor |
| `443e25d` | ancestor |
| `3dd3145` | ancestor |
| `955563e` | ancestor |
| `8440e93` | ancestor |
| `3ad472e` | ancestor |
| `6d82865` | ancestor (HEAD) |

## 5. Product lanes on main (post-convergence)

| Lane | Primary paths | Introduced by |
|------|---------------|---------------|
| Numeric hostname availability | `survey/sas-survey-hostname-availability.sh`, `survey/sas-hostname-availability.py`, `survey/sas-ad-computer-prefix-export.ps1`, `docs/HOSTNAME_AVAILABILITY.md` | PR #33 (`1f83842`) |
| Registry install-diff pipeline | `scripts/powershell/*Registry*`, `scripts/powershell/Test-TargetReadiness.ps1`, `scripts/sas_registry_install_diff.sh`, `schemas/`, `config/registry_*.example.json`, `Tests/Pester/Registry*.ps1` | PR #34 merge (`443e25d`) |
| Neuron runtime (PS harvest) | `GetInfo/Get-NeuronSoftwareReference.ps1`, `QRTasks/Get-NeuronMaintenanceSnapshot.ps1`, `Tests/Pester/Neuron*.ps1` | PR #35 (`3dd3145`) |
| Cybernet Nmap deployment audit | `deployment-audit/nmap/*` | PR #36 (`955563e`) |
| Auto-logon workstation assessment | `survey/sas-assess-autologon.sh`, `deployment-audit/sas-render-autologon-dashboard.py`, `docs/AUTOLOGON_ASSESSMENT.md` | PR #37 (`8440e93`) |
| Auto-logon preflight | `survey/sas-assess-autologon.sh` (`--preflight`), `docs/COMMAND_CATALOG.md` | PR #38 (`3ad472e`) |
| Remote-first operator docs | `docs/REMOTE_WORKFLOW.md` | Direct commit `6d82865` (after #38) |
| Branch convergence ledger | `docs/BRANCH_CONVERGENCE_2026-05-27.md` | PR #37 + touch in #38 |

## 6. Other main lanes (pre-sprint foundation)

These lanes predate the 2026-05-27 convergence batch but remain active on `main`:

| Reference | Lane | Primary paths | Notes |
|-----------|------|---------------|--------|
| PR #7 | Deployment audit / transport | `deployment-audit/`, transport-related scripts | Merged historical foundation per [BRANCH_CONVERGENCE_2026-05-27.md](BRANCH_CONVERGENCE_2026-05-27.md) |
| PR #21 | Identity / AD export | `survey/sas-ad-identity-export.ps1` | Extended in #37 autologon work |
| PR #24 | Survey-layer Nmap baseline | `survey/` nmap baseline tooling | Distinct from `deployment-audit/nmap` (#36) |
| PR #12 superseded | Live serial probe | `survey/sas-live-serial-probe.sh` | Landed via direct-main commits; see [BRANCH_CONVERGENCE_2026-05-22.md](BRANCH_CONVERGENCE_2026-05-22.md) |

## 7. Documentation drift (do not edit source ledger this sprint)

[BRANCH_CONVERGENCE_2026-05-27.md](BRANCH_CONVERGENCE_2026-05-27.md) on `main` is **stale** relative to actual `origin/main` as of this audit:

| Ledger claim | Actual main (2026-05-27 audit) |
|--------------|--------------------------------|
| HEAD `955563e` | HEAD is `6d82865` |
| Open PR: `feature/autologon-workstation-assessment` pending | #37 and #38 merged; autologon assessment + preflight on main |
| #34 described as REMOTE_WORKFLOW + ledger (`absorbed_in_main` docs) | #34 merge brought registry install-diff stack; REMOTE_WORKFLOW landed in `6d82865`; ledger finalized in #37 |

Record drift here only; ledger file update is deferred to a later sprint phase.

## 8. Archive tag

| Tag | Points to | Present |
|-----|-----------|---------|
| `archive/convergence-2026-05-27` | `8440e93` (post-#37 merge, pre-#38) | Yes |

Use this tag as the convergence-sprint checkpoint before autologon preflight (#38) and `REMOTE_WORKFLOW.md` (`6d82865`).

## Related documents

- [PR_PAYLOAD_AUDIT_2026-05-27.md](PR_PAYLOAD_AUDIT_2026-05-27.md) — title/body vs files for #33–#38
- [REMOTE_WORKFLOW.md](REMOTE_WORKFLOW.md) — operator workflow (main @ `6d82865`)
- Control issue: [#13](https://github.com/EndeavorEverlasting/SysAdminSuite/issues/13)
