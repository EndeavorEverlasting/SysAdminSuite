# PR Payload Audit — 2026-05-27

Post-convergence audit of merged PRs **#33–#38** and follow-up commit **`6d82865`**. Compares GitHub title/body narration to files actually merged. See [MAINLINE_STATE_2026-05-27.md](MAINLINE_STATE_2026-05-27.md) for mainline SHAs and lane map.

**Method:** `gh pr view N --json number,title,body,headRefName,mergeCommit,files` plus `git show --stat` on merge commits and branch tips.

---

## Audit table (#33–#38)

| PR | Title says | Body says (1 line) | Files prove | Classification | Follow-up |
|----|------------|-------------------|-------------|----------------|------------|
| [#33](https://github.com/EndeavorEverlasting/SysAdminSuite/pull/33) | Numeric hostname availability with AD/tracker/DNS evidence | Bash-first numeric hostname survey with AD export, tracker extraction, DNS cross-check, contract test | 9 files: `survey/sas-survey-hostname-availability.sh`, `survey/sas-hostname-availability.py`, AD/DNS helpers, `docs/HOSTNAME_AVAILABILITY.md`, contract test | `title_matches_payload` | Lab validation per PR test plan (AD export, tracker union) |
| [#34](https://github.com/EndeavorEverlasting/SysAdminSuite/pull/34) | Document remote-first workflow and branch convergence ledger | Claims docs-only: REMOTE_WORKFLOW + BRANCH_CONVERGENCE ledger + AGENTS pointers | **23 files**, ~2943 insertions: registry PS orchestrator, snapshots, readiness, schemas, Pester tests, bash wrapper — **no** `REMOTE_WORKFLOW.md` or ledger in PR file list; tip commit `35db948` is **empty** (message-only) | `title_body_mismatch` | Treat #34 as registry consolidation; see corrected narrative; REMOTE_WORKFLOW landed in `6d82865`, ledger in #37 |
| [#35](https://github.com/EndeavorEverlasting/SysAdminSuite/pull/35) | Harvest Neuron runtime tools from current main | Replaces draft PR #32; Neuron PS harvest onto current main | 4 files: `GetInfo/Get-NeuronSoftwareReference.ps1`, `QRTasks/Get-NeuronMaintenanceSnapshot.ps1`, Neuron Pester tests | `replacement_pr` (for #32) | Run CI/local Pester on Neuron* tests per PR test plan |
| [#36](https://github.com/EndeavorEverlasting/SysAdminSuite/pull/36) | Add Nmap Cybernet target audit workflow (v2 from main) | Ports `deployment-audit/nmap/*` from #10 without merging stale branch | 9 files under `deployment-audit/nmap/` (Python runners, WAB guard, cmd launchers) | `replacement_pr` (for #10) | Lab smoke `run-cybernet-nmap.cmd`; guest-network guard validation |
| [#37](https://github.com/EndeavorEverlasting/SysAdminSuite/pull/37) | Finalize branch convergence ledger | Marks #34–#36 merged, closed open PRs; closing #13 housekeeping | 9 files: autologon assessment (`survey/sas-assess-autologon.sh`, dashboard renderer, contracts), **`docs/BRANCH_CONVERGENCE_2026-05-27.md`**, `docs/AUTOLOGON_ASSESSMENT.md` — title says ledger only | `title_body_partial_mismatch` | Update ledger in a future sprint (drift vs `6d82865` HEAD); autologon lab runs |
| [#38](https://github.com/EndeavorEverlasting/SysAdminSuite/pull/38) | feat(survey): autologon preflight via Test-TargetReadiness | `--preflight` on autologon survey using registry readiness PS; remote-first doc updates | 5 files: `survey/sas-assess-autologon.sh`, `docs/AUTOLOGON_ASSESSMENT.md`, `docs/COMMAND_CATALOG.md`, ledger touch, `survey/README.md` | `title_matches_payload` | Contract test passed in PR; field preflight on corp network |

---

## PR #34 deep dive (mislabelled merge)

### GitHub metadata

| Field | Value |
|-------|--------|
| Head branch | `docs/branch-convergence-2026-05-27` |
| Merge commit | `443e25df3ee85857cc9985c6aa74b20a92f13aff` (`443e25d`) |
| Merge parents | `1f83842` + `35db948` |

### Empty tip commit `35db948`

```bash
git show --stat 35db948
```

Commit message references REMOTE_WORKFLOW and convergence ledger; **`git show --stat` reports no file changes** (empty tip). Narration in the commit message does not match the diff.

### Actual payload merged at `443e25d`

`git diff --stat 1f83842..443e25d` — **23 files changed, 2943 insertions(+)**:

| Area | Paths |
|------|--------|
| PowerShell pipeline | `scripts/powershell/Compare-RegistrySnapshots.ps1`, `Get-RegistrySnapshot.ps1`, `Invoke-RegistryInstallDiff.ps1`, `Invoke-TrackedInstall.ps1`, `Test-TargetReadiness.ps1` |
| Bash wrapper | `scripts/sas_registry_install_diff.sh` |
| Schemas / config | `schemas/*.schema.json`, `config/registry_*.example.json`, `config/target_batch.example.csv` |
| Docs (registry) | `docs/REGISTRY_INSTALL_DIFF_PIPELINE.md`, `docs/REGISTRY_DIFF_SAFETY_RULES.md`, etc. |
| Tests | `Tests/Pester/Registry*.ps1`, `tests/bash/test_registry_install_diff_wrapper_contracts.sh` |

### Where docs actually landed

| Document | Landed in |
|----------|-----------|
| `docs/REMOTE_WORKFLOW.md` | **`6d82865`** (direct commit on main after #38) — **not** #34 |
| `docs/BRANCH_CONVERGENCE_2026-05-27.md` | **#37** — **not** #34 |
| Registry install-diff docs | **#34** merge (`443e25d`) |

---

## Post-merge commit `6d82865`

| Field | Value |
|-------|--------|
| SHA | `6d828657b86d509b406ee9093137d25abd5a8c68` |
| Message | `docs: add remote-first workflow guide for GitHub-centric development` |
| Files | `docs/REMOTE_WORKFLOW.md` only (+59 lines) |

Not a PR merge node. Operators must not attribute `REMOTE_WORKFLOW.md` to PR #34.

---

## `git show --stat` merge nodes (summary)

| SHA | PR | Stat headline |
|-----|-----|----------------|
| `1f83842` | #33 (direct) | Hostname availability survey + docs + contract test |
| `443e25d` | #34 merge | Registry stack (23 files via integration branch history) |
| `3dd3145` | #35 merge | 4 Neuron PS + Pester files |
| `955563e` | #36 merge | `deployment-audit/nmap/*` (9 files) |
| `8440e93` | #37 merge | Autologon assessment + convergence ledger |
| `3ad472e` | #38 merge | Autologon preflight + catalog |
| `6d82865` | — | `docs/REMOTE_WORKFLOW.md` |

---

## Stern rules (audit discipline)

1. **Files win over titles.** If the PR title says "docs" but `gh pr view --json files` lists scripts, schemas, or tests, classify by files.
2. **Empty tip commits are not payload.** Always run `git show --stat` on the branch tip; do not assume the tip commit equals the merge diff.
3. **Merge commits carry integration history.** PR #34's registry payload arrived through `integration/registry-install-diff-2026-05` merges visible in `git log` between `1f83842` and `443e25d`.
4. **Do not merge PR #6 or #10 as-is.** Replacement PRs #35 and #36 are the supported paths (per convergence ledger).
5. **Do not edit [BRANCH_CONVERGENCE_2026-05-27.md](BRANCH_CONVERGENCE_2026-05-27.md) in the post-convergence docs sprint.** Record drift in [MAINLINE_STATE_2026-05-27.md](MAINLINE_STATE_2026-05-27.md) only.
6. **No operational data in public commits.** Survey output, WAB captures, and local scratch belong in `.gitignore` or outside the repo.

---

## Corrected narrative (use in runbooks and agent context)

| Item | Correct description |
|------|---------------------|
| **#33** | Numeric hostname availability (AD + tracker + DNS evidence) on main at `1f83842`. |
| **#34** | **Registry install-diff consolidation payload** merged at `443e25d`. Title/body incorrectly described docs-only workflow; branch name `docs/branch-convergence-2026-05-27` added confusion. Tip `35db948` is empty. |
| **#35** | **Neuron runtime replacement for #32** — PowerShell harvest at `3dd3145`. |
| **#36** | **Nmap v2 replacement for #10** — `deployment-audit/nmap` at `955563e`. |
| **#37** | **Convergence ledger + autologon assessment landing zone** at `8440e93` (ledger file + assessment tooling; title understates autologon scope). |
| **#38** | **Autologon preflight hardening** at `3ad472e` (`--preflight` via `Test-TargetReadiness.ps1`). |
| **`6d82865`** | **`docs/REMOTE_WORKFLOW.md` on main after #38** — not part of #34. |

---

## Known gaps (from this audit)

- [BRANCH_CONVERGENCE_2026-05-27.md](BRANCH_CONVERGENCE_2026-05-27.md) still lists HEAD `955563e` and pending autologon PR (drift).
- PR #34 GitHub title/body still read "docs-only" on the merged PR record (historical mislabel; do not trust without file list).
- Lab validations open on #33, #35, #36 per original PR test plans.
- Phases 3–7 of post-convergence plan not started (bash contracts, Pester CI, public safety, branch janitor, command catalog sync).

## Risks

- **Mislabeled PRs** confuse agents into skipping registry or autologon maintenance.
- **Empty commits** (`35db948`) look like completed doc work when no files changed.
- **Branch soup** — deleted remotes (`docs/branch-convergence-2026-05-27`, etc.) may still exist locally; do not rebase new work onto stale tips.

## Targets (next sprint — Phases 3–7)

1. Bash wrapper contracts and CI wiring for registry install-diff.
2. Pester workflow coverage for Neuron and registry lanes.
3. Public-safety scrub and command catalog alignment with merged payloads.
4. Branch janitor: delete classified locals/remotes per ledger.
5. Command catalog: ensure Live Mode lists Bash + PowerShell for WMI/registry/autologon paths.

---

## Related

- [MAINLINE_STATE_2026-05-27.md](MAINLINE_STATE_2026-05-27.md)
- [REMOTE_WORKFLOW.md](REMOTE_WORKFLOW.md)
- Control issue [#13](https://github.com/EndeavorEverlasting/SysAdminSuite/issues/13)
