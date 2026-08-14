# Pre-stage Bootstrap Safety Skill

## Trigger

Use this skill when AutoLogon/S4U fails before stage 1, when Windows PowerShell 5.1/StrictMode raises a scalar/null `.Count` exception during bootstrap, or when an outer resolver succeeds but an inner canonical-FQDN bootstrap fails.

## Required inputs

- repository root, current branch, and current HEAD;
- intended current remote ref or expected commit;
- whether stage 1 was observed;
- sanitized failure phase/message;
- repository-network and branch-update authority, if remote refresh is required.

## Procedure

1. Read `AGENTS.md` and preserve unrelated or dirty work.
2. Read `harness/maps/prestage-bootstrap-map.md`.
3. If stage 1 was not observed, classify the failure as controller pre-stage bootstrap; do not call it an S4U task failure yet.
4. Run `harness/workflows/repository-freshness-before-launch.yaml`. A fetch is not an update. Prove the executing tree matches the selected refreshed commit or use a preserved isolated worktree.
5. Inspect `scripts/SasNetworkGuard.psm1`, `scripts/SasTargetNameResolution.psm1`, and `scripts/Invoke-SasAutoLogonKerberosS4UPilot.ps1` read-only.
6. Run `python harness/validators/validate-prestage-bootstrap-safety.py` and `python Tests/survey/test_prestage_bootstrap_harness_completeness.py`.
7. On a Windows PowerShell-capable host, run `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-Pester5Suite.ps1 -TestPath Tests/Pester/TargetNameResolution.Tests.ps1`.
8. If the stale checkout fails while current-tree regression proof is green, converge the controller to the selected current commit without force or destructive cleanup, then return to the canonical field workflow. If current-tree regression proof fails, stop and create a separately owned product-repair lane.

## Failure handling

- Freshness unproven: stop before product diagnosis or field rerun and provide the exact non-force fetch/isolation action.
- Dirty or separately owned work: preserve it; do not reset, clean, overwrite, or force-update.
- Current regression missing/failing: stop this harness lane and report a product-code blocker; do not edit product code here.
- Stage 1 absent: do not attribute the incident to task creation, target registry application, restart, or automatic sign-in.
- Live evidence: keep it local/untracked and sanitize handoffs.

## Expected outputs

- selected repository commit and freshness classification;
- pre-stage versus post-stage classification;
- focused harness validation result;
- focused target-name-resolution regression result when a Windows host is available;
- tracked operator status report reference;
- one exact next action that advances the first unproven gate.

## Proof ceiling

This skill proves repository selection, pre-stage classification, harness integrity, and focused regression evidence only. It cannot prove a live target, S4U task execution, AutoLogon application, restart completion, signed-in runtime behavior, or operator acceptance.
