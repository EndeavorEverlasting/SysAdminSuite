#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POLICY = ROOT / "Config" / "promotion-policy.json"
AUTHORITY = ROOT / ".github" / "workflows" / "validated-promotion.yml"
CONTRACTS = ROOT / ".github" / "workflows" / "validated-promotion-contracts.yml"
RESOLVER = ROOT / "scripts" / "Resolve-SasPromotionCandidate.ps1"
DEFAULT_E2E = ROOT / ".github" / "workflows" / "default-e2e-validation.yml"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    policy = json.loads(POLICY.read_text(encoding="utf-8"))
    authority = AUTHORITY.read_text(encoding="utf-8")
    contracts = CONTRACTS.read_text(encoding="utf-8")
    resolver = RESOLVER.read_text(encoding="utf-8")
    default_e2e = DEFAULT_E2E.read_text(encoding="utf-8")

    require(policy["schema_version"] == "sas-promotion-policy/v1", "promotion policy schema drift")
    require(policy["allowed_targets"] == ["main"], "promotion target allowlist must remain main-only")
    require(policy["source_branch_prefix"] == "promote/", "promotion source prefix drift")
    require(policy["authorization_marker"] == "Promotion-Intent: validated-mainline", "authorization marker drift")
    require(policy["merge_method"] == "merge", "promotion must preserve source-head ancestry")
    require(policy["required_skip_is_failure"] is True, "required SKIP must fail closed")
    require(policy["base_movement_invalidates_promotion"] is True, "base movement must invalidate proof")

    require("pull_request_target:" in authority, "write authority must run from trusted base workflow code")
    require("pull_request:" not in authority, "write authority must not execute from candidate-owned pull_request workflow")
    require("workflow_dispatch:" in authority, "bounded operator dispatch path missing")
    require("contents: read" in authority, "workflow must default to read-only contents")
    require("pull-requests: read" in authority, "workflow must default to read-only PR access")
    require("permissions:\n      contents: write\n      pull-requests: write" in authority, "write permission must be job-scoped to promotion")
    require("persist-credentials: false" in authority, "candidate validation checkout must not persist credentials")
    require("needs: [resolve-candidate, promotion-contracts, harness-e2e, application-e2e]" in authority, "promotion must depend on every required gate")
    require("concurrency:" in authority and "sas-validated-promotion-" in authority, "promotion writer must be serialized")
    require("Resolve-SasPromotionCandidate.ps1" in authority, "authority must compose canonical candidate resolver")
    require("Invoke-SasHarnessContracts.ps1" in authority, "authority must compose canonical harness contracts")
    require("validate-sysadmin-harness.ps1" in authority, "authority must run canonical harness E2E")
    require("Invoke-SasEndToEndValidation.ps1" in authority and "-Profile default" in authority, "authority must run canonical application E2E profile")
    require("git diff --check" in authority, "exact merge candidate diff check missing")
    require("pulls/$prNumber/merge" in authority, "promotion must use provider PR merge endpoint")
    require("merge-base --is-ancestor" in authority, "post-promotion ancestry containment proof missing")
    require("promotion-receipt.json" in authority, "machine-readable promotion receipt missing")
    require("continue-on-error" not in authority, "promotion-critical jobs may not continue on error")
    require("github-actions[bot]" in resolver, "recursive writer guard missing")
    require("ExpectedCandidateSha" in resolver and "Candidate moved" in resolver, "exact-head stale proof guard missing")
    require("ExpectedBaseSha" in resolver and "Base moved after validation" in resolver, "base stale proof guard missing")
    require("Synthetic merge candidate" in resolver, "synthetic merge identity guard missing")
    require("Cross-repository promotion is forbidden" in resolver, "same-repository guard missing")
    require("Unauthorized promotion target" in resolver, "target allowlist guard missing")

    require("pull_request:" in contracts, "unprivileged promotion contracts must run on candidate PRs")
    require("contents: read" in contracts, "contract workflow must be read-only")
    require("python Tests/survey/test_validated_promotion_contracts.py" in contracts, "canonical promotion contract test not invoked")

    for path in (
        "Config/promotion-policy.json",
        ".github/workflows/validated-promotion.yml",
        ".github/workflows/validated-promotion-contracts.yml",
        "scripts/Resolve-SasPromotionCandidate.ps1",
        "Tests/survey/test_validated_promotion_contracts.py",
    ):
        require(path in default_e2e, f"default E2E workflow does not observe promotion surface: {path}")

    print("PASS: validated promotion contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
