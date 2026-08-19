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
    module_policy = text.index("if (Test-Path -LiteralPath $moduleConfigPath -PathType Leaf)")
    module_policy_return = text.index("return $moduleConfigPath", module_policy)
    legacy_root = text.index("if ($env:SAS_REPO_ROOT)")
    legacy_return = text.index("return (Join-Path $env:SAS_REPO_ROOT 'Config\\sas-network-guard.local.json')", legacy_root)
    final_module_fallback = text.rindex("return $moduleConfigPath")

    # Prove precedence from executable control flow, not a comment that can be
    # removed without changing behavior: executing-checkout policy wins first,
    # the legacy repository root is consulted only afterward, and the module
    # path remains the final fallback when neither source resolves a file.
    assert module_policy < module_policy_return < legacy_root < legacy_return < final_module_fallback


if __name__ == "__main__":
    test_explicit_network_guard_config_remains_highest_priority()
    test_executing_checkout_policy_precedes_legacy_repo_root()
    test_legacy_repo_root_is_fallback_only()
    print("Network guard config precedence contracts passed")
