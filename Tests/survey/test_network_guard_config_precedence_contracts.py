from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "scripts" / "SasNetworkGuard.psm1"


def read() -> str:
    return MODULE.read_text(encoding="utf-8")


def test_explicit_network_guard_config_remains_highest_priority() -> None:
    text = read()
    explicit = text.index("if ($env:SAS_NETWORK_GUARD_CONFIG)")
    module_root = text.index("$moduleRepoRoot =")
    assert explicit < module_root


def test_executing_checkout_policy_precedes_legacy_repo_root() -> None:
    text = read()
    module_policy = text.index("if (Test-Path -LiteralPath $moduleConfigPath -PathType Leaf)")
    legacy_root = text.index("if ($env:SAS_REPO_ROOT)")
    assert module_policy < legacy_root
    assert "return $moduleConfigPath" in text


def test_legacy_repo_root_is_fallback_only() -> None:
    text = read()
    assert "Preserve compatibility for legacy callers" in text
    assert "Join-Path $env:SAS_REPO_ROOT 'Config\\sas-network-guard.local.json'" in text


if __name__ == "__main__":
    test_explicit_network_guard_config_remains_highest_priority()
    test_executing_checkout_policy_precedes_legacy_repo_root()
    test_legacy_repo_root_is_fallback_only()
    print("Network guard config precedence contracts passed")
