#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Set-SasHostEligibilityLocalTarget.ps1"
GITIGNORE = ROOT / ".gitignore"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_requires_explicit_local_authorization() -> None:
    text = read(SCRIPT)
    assert "ConfirmLocalAuthorization" in text
    assert "Explicit -ConfirmLocalAuthorization is required" in text


def test_writes_only_operator_local_policy_and_exact_regex() -> None:
    text = read(SCRIPT)
    assert "Config\\host-eligibility-policy.local.json" in text
    assert "[regex]::Escape($normalizedTarget)" in text
    assert "'^(?i:'" in text
    assert "actions = @($ExecContext)" in text
    assert "ValidateSet('remote')" in text
    assert "patterns = @($exactPattern) + $patterns" in text


def test_authorizer_rechecks_existing_fail_closed_validator() -> None:
    text = read(SCRIPT)
    assert "Test-SasHostEligibility.ps1" in text
    assert "-Target $normalizedTarget -ExecContext $ExecContext" in text
    assert "-not [bool]$result.eligible" in text
    assert "[string]$result.matched_pattern -ne $patternName" in text


def test_local_policy_is_gitignored() -> None:
    text = read(GITIGNORE)
    assert "Config/host-eligibility-policy.local.json" in text


def test_helper_does_not_embed_live_hosts_or_broad_remote_wildcard() -> None:
    text = read(SCRIPT).lower()
    for forbidden in ("wpj075", "northwell", "nslijhs.net", "regex = '.*'", 'regex = ".*"'):
        assert forbidden not in text, forbidden


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: host eligibility local authorizer contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
