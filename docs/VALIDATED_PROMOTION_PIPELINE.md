# Validated Promotion Pipeline

## Purpose

SysAdminSuite promotion is an evidence-and-advancement system. It does not generate or opportunistically rewrite product source. Humans, agents, and bounded repo-native generators finish authoring before this pipeline begins.

The promotion authority is `.github/workflows/validated-promotion.yml`. Its policy is `Config/promotion-policy.json`. Candidate identity resolution is owned by `scripts/Resolve-SasPromotionCandidate.ps1`.

## Promotion graph

```text
same-repo owner PR + promote/* + exact authorization marker
  -> trusted-base candidate resolver
  -> source head SHA + current default-base SHA + GitHub synthetic merge SHA
  -> read-only promotion contracts + git diff --check
  -> read-only harness contracts
  -> read-only one-command harness E2E
  -> read-only default application E2E
  -> read-only AutoLogon application E2E
  -> serialized exact-identity recheck
  -> exact synthetic merge commit fast-forward to main
  -> refreshed-main ancestry containment proof
  -> GitHub merged-PR proof
  -> machine-readable promotion receipt + PR comment
```

## Authorization

Automatic promotion is deliberately narrow. A PR must:

- target the repository's actual default branch and a target listed in `allowed_targets`;
- originate in this repository;
- be authored by the repository owner;
- use the `promote/` source-branch prefix;
- contain the exact line `Promotion-Intent: validated-mainline`;
- be open, non-draft, and mergeable;
- avoid every `manual_only_paths` control-plane/validator owner.

`workflow_dispatch` is also available, but the supplied PR number, candidate head SHA, and target still pass through the same resolver and policy.

## Trust boundary

The write-capable workflow uses `pull_request_target` so its orchestration comes from trusted base-branch code. Candidate code is executed only in jobs whose token permissions are read-only and whose checkout uses `persist-credentials: false`.

The final write job does not execute candidate code. It checks out the recorded trusted base revision, re-runs the trusted resolver, and requires the same source head, base SHA, and synthetic merge SHA that earlier jobs validated.

Changes to the promotion authority, policy, resolver, core harness runner, E2E runner/profile, or promotion contract test are manual-only. This prevents a candidate from weakening its own gate and then self-certifying the weakened rule.

## Exact candidate identity

Promotion proof is pinned to three Git identities:

1. `source_head_sha` — the authored PR head;
2. `base_sha` — the current default-branch head observed before validation;
3. `synthetic_merge_sha` — GitHub's merge candidate whose parents include both the recorded base and source head.

All promotion validation checks out the synthetic merge SHA. Immediately before mutation, the resolver requires all three identities to remain unchanged.

The write transport is `exact-synthetic-merge-fast-forward`: the default branch is advanced to the exact synthetic merge object already tested. The update is non-forced. If the base moved, the update is not a fast-forward and GitHub rejects it.

## Repository protection

The pipeline does not bypass branch protection or rulesets. The current exact-ref transport intentionally fails closed when the target branch reports `protected=true`. A future protected-branch mode must be designed around the provider's merge queue/protection semantics before enabling automated mutation there.

This is stricter than attempting an administrative bypass with a token.

## Harness E2E versus application E2E

These are separate proof layers.

### Harness proof

The pipeline invokes the existing canonical owners:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasHarnessContracts.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-sysadmin-harness.ps1 -OutputRoot .\survey\output\promotion\harness
```

This proves repository contracts, registries, fixtures, proof machinery, artifact registration, and the one-command harness path together.

### Application proof

The pipeline invokes the existing E2E owner for both applicable fixture-safe profiles:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasEndToEndValidation.ps1 -Profile default -OutputRoot .\survey\output\promotion\application-e2e
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasEndToEndValidation.ps1 -Profile autologon -OutputRoot .\survey\output\promotion\autologon-e2e
```

Every required journey must be `PASS`. A required `SKIP`, missing runtime, failed journey, external-network claim, or target-mutation claim fails promotion.

Fixture/loopback E2E does not claim protected-network, device, production, or operator acceptance.

## Permissions and concurrency

- default workflow permission: `contents: read`, `pull-requests: read`;
- validation jobs: read-only;
- promotion job only: `contents: write`, `pull-requests: write`;
- post-promotion job: read contents plus PR comment permission;
- candidate checkouts never persist credentials;
- promotion writes are serialized per target branch;
- `github-actions[bot]` cannot authorize another promotion run;
- the writer has no `push` trigger, preventing a promotion loop.

## Artifacts and receipts

The harness job uploads its complete proof directory plus a SHA-256 manifest receipt. The application job uploads the default and AutoLogon E2E receipts plus a promotion-specific receipt containing hashes of the canonical E2E results.

After mutation, `promotion-receipt.json` records:

- provider run ID, event, and actor;
- PR number;
- source head, base, and validated synthetic merge SHA;
- promotion policy hash;
- required job conclusions;
- harness/application/mutation receipt hashes;
- promotion target and transport;
- provider merge SHA;
- refreshed default-branch head;
- source-head and synthetic-merge containment;
- proof ceiling.

A successful API request alone is not completion. Post-promotion proof refreshes `main`, requires the source head and validated merge SHA to be ancestors, and requires GitHub to classify the PR as merged.

## Proof ceiling

The CI lane proves repository contracts plus fixture/loopback application behavior. It does not contact or mutate protected Northwell workstations, printers, Active Directory, package shares, devices, or production services. Features requiring those environments retain a separate field/live acceptance gate after repository integration.
