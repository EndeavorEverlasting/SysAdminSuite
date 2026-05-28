# Branch Retirement Ledger (2026-05-27)

Validation branch: `docs/post-convergence-validation-2026-05-27`  
Commit under test: `9ec89e44fb2fe24458dbdb799ac64d8b4f796bdf`

## Commands run

```bash
git fetch --all --prune
git branch -r --sort=-committerdate
git rev-list --count origin/main..origin/<branch>
git rev-list --count origin/<branch>..origin/main
git log --oneline origin/main..origin/<branch>
git diff --stat origin/main...origin/<branch>
```

## Cleanup actions executed

### Remote branches deleted (`absorbed_in_main`)

- `origin/docs/post-convergence-audit-2026-05-27`
- `origin/docs/local-reference-privacy-redaction`
- `origin/feature/autologon-preflight-2026-05-27`
- `origin/docs/convergence-final-ledger-2026-05-27`

### Local branches deleted (merged / obsolete)

- `audit-deployment-2026-05-02`
- `consolidate/v2.0`
- `demo/v2.1`
- `docs/local-reference-privacy-redaction`
- `docs/post-convergence-audit-2026-05-27`
- `feature/autologon-preflight-2026-05-27`
- `feature/autologon-workstation-assessment`
- `feature/qrtasks-module`
- `feature/registry-install-diff-consolidated`
- `integration/registry-install-diff-2026-05`
- `unit-tests/repo-health-and-bom-compliance`

Post-cleanup counts:

- Local branches: `4` (including `main` and active validation branch)
- Remote non-main branches: `44`

## Current classifications (remaining remote branches)

| Branch set | Classification | Why |
|---|---|---|
| `origin/harvest/*` | `historical_checkpoint_only` | Mostly one-off harvest checkpoints with ahead deltas against current `main` |
| `origin/tmp/*` | `safe_to_delete_after_tag` | Temporary rebase/scratch branches |
| `origin/forensics/*` | `historical_checkpoint_only` | Evidence/archive style names and old divergence points |
| `origin/feature/2026-04-*` Neuron branches | `superseded_by_replacement_pr` | Payload expectations overlap with later convergence replacements and current-main harvests |
| `origin/feature/nmap-baseline-module-v1` + `origin/sprint/2026-05-23-registry-install-diff-pipeline` | `superseded_by_replacement_pr` | Superseded by merged convergence path (#34/#36 and follow-on merges) |
| `origin/feature/live-serial-probe-v1-mainline` | `do_not_delete_yet` | Has unique ahead commit; verify no unmerged docs/fixtures before deletion |
| `origin/feature/machine-info-hostname-copy` | `do_not_delete_yet` | Large ahead set (`23`) requires explicit payload decision |
| `origin/feature/qr-field-capsule-v1` / `v2` | `do_not_delete_yet` | Candidate for future feature lane, not proven absorbed |
| Legacy roots (`origin/LPW003ASI037-Repo`, `origin/feat/*`, `origin/delta/*`) | `historical_checkpoint_only` | Early project archaeology; safe only after explicit archive/tag policy |

## Known gaps

- `44` remote non-main branches still exist after the safe deletion pass.
- Several branches retain ahead commits and need explicit human product decision before delete.

## Risks

- Aggressive deletion of historical branches could lose branch-specific context still used by operators.
- Leaving large stale branch sets increases future PR base confusion and accidental rebases.

## Targets

1. Perform a second janitor pass focused on `tmp/*`, then `harvest/*`, then old legacy roots after tagging.
2. For each `do_not_delete_yet` branch, document whether payload is to be merged, archived, or dropped.
3. Keep branch namespace below 10 active non-main remotes before starting next feature wave.
