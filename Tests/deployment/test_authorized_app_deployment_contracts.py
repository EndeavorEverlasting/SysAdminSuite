import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-AuthorizedAppDeployment.ps1"
SCHEMA = ROOT / "config" / "deployment-manifest.schema.json"
POLICY = ROOT / "config" / "log-operation-policy.json"
CLASSIFIER = ROOT / "config" / "log-classification.json"
EXAMPLE_CSV = ROOT / "examples" / "deployment-manifest.example.csv"
FIXTURE_MANIFEST = ROOT / "Tests" / "fixtures" / "deployment" / "deployment-manifest.fixture.json"
FIXTURE_INSTALLER = ROOT / "Tests" / "fixtures" / "deployment" / "fixture-installer.txt"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_deployment_script_contract_guards_present():
    content = text(SCRIPT)
    assert "[switch]$Execute" in content
    assert "DRY-RUN" in content
    assert "Test-SasSafeDeploymentCleanupPath" in content
    assert "C:\\ProgramData\\SysAdminSuite\\DeploymentTemp" in content
    assert "New-PSSession" in content
    assert "Copy-Item" in content and "-ToSession" in content
    assert "Get-FileHash" in content and "SHA256" in content
    assert "Remove-Item -LiteralPath $TempRoot" in content
    assert "deployment-results.json" in content
    assert "validation-report.json" in content


def test_no_forbidden_log_or_security_mutation_code_paths():
    combined = "\n".join(text(p) for p in [SCRIPT, ROOT / "scripts" / "validate-log-policy.ps1"])
    forbidden_patterns = [
        r"Clear-EventLog",
        r"Remove-EventLog",
        r"wevtutil\s+cl",
        r"Get-WinEvent\s+-ComputerName",
        r"Set-MpPreference\s+.*Disable",
        r"Stop-Service\s+.*(Defender|WinDefend|EDR)",
        r"Disable-.*Audit",
        r"Remove-Item\s+.*\.evtx",
    ]
    for pattern in forbidden_patterns:
        assert not re.search(pattern, combined, flags=re.IGNORECASE), pattern


def test_manifest_schema_requires_expected_fields_and_sha256():
    schema = json.loads(text(SCHEMA))
    required = set(schema["items"]["required"])
    for field in ["TargetHostname", "ApplicationName", "NetworkSharePath", "InstallerPath", "ExpectedSha256", "SilentInstallArguments", "InstallDetectionMethod", "Owner", "RequestReference", "ChangeReference", "TicketReference"]:
        assert field in required
    assert schema["items"]["properties"]["ExpectedSha256"]["pattern"] == "^[A-Fa-f0-9]{64}$"


def test_example_manifest_is_sanitized_and_complete():
    rows = list(csv.DictReader(EXAMPLE_CSV.open(newline="", encoding="utf-8")))
    assert len(rows) == 1
    row = rows[0]
    assert row["TargetHostname"] == "WORKSTATION001"
    assert "example.internal" in row["NetworkSharePath"]
    assert re.fullmatch(r"[0-9a-f]{64}", row["ExpectedSha256"])


def test_operation_policy_forbids_destructive_and_live_log_ops():
    policy = json.loads(text(POLICY))["operations"]
    for op in ["LIVE_READ_HOST_LOG", "EXPORT_HOST_LOG", "CLEAR_LOG", "DELETE_LOG", "MUTATE_LOG", "DISABLE_LOGGING", "SUPPRESS_AUDIT"]:
        assert policy[op]["decision"] == "forbidden"
    assert policy["CLEAN_SCRIPT_CREATED_TEMP_FILES"]["decision"] == "allowed"
    assert "DeploymentTemp" in policy["CLEAN_SCRIPT_CREATED_TEMP_FILES"]["scope"]


def test_log_classifier_is_render_only_and_plans_only():
    classifier = json.loads(text(CLASSIFIER))
    assert classifier["mode"] == "render-only"
    assert classifier["liveHostLogQueriesAllowed"] is False
    for plan in (ROOT / "examples").glob("log-plan.*.json"):
        data = json.loads(text(plan))
        assert data["mode"] == "render-only"
        assert data["liveHostLogQueriesAllowed"] is False
        assert "LIVE_READ_HOST_LOG" in data["forbiddenOperations"]


def test_gitignore_keeps_runtime_deployment_outputs_local_only():
    gi = text(ROOT / ".gitignore")
    assert "output/deployments/*" in gi
    assert "!output/deployments/.gitkeep" in gi


def test_result_json_shape_fields_are_declared():
    content = text(SCRIPT)
    for field in ["DeploymentId", "Hostname", "Application", "ManifestRow", "StartTime", "EndTime", "NetworkSharePath", "InstallerName", "ExpectedSha256", "ActualSha256", "HashValidationStatus", "InstallAttempted", "InstallerExitCode", "InstallResult", "RebootRequired", "CleanupAttempted", "CleanupResult", "ErrorCategory", "ErrorMessage", "NextRecommendedAction"]:
        assert field in content


def test_dry_run_fixture_manifest_points_to_local_fixture_without_execute():
    rows = json.loads(text(FIXTURE_MANIFEST))
    assert len(rows) == 1
    row = rows[0]
    assert row["TargetHostname"] == "WORKSTATION001"
    assert row["NetworkSharePath"].startswith(r"\\fileserver.example.internal\software")
    installer_path = Path(row["InstallerPath"])
    if not installer_path.is_absolute():
        installer_path = ROOT / installer_path
    assert installer_path.resolve() == FIXTURE_INSTALLER.resolve()
    import hashlib
    assert hashlib.sha256(FIXTURE_INSTALLER.read_bytes()).hexdigest() == row["ExpectedSha256"]


def test_deployment_validator_has_safe_default_fixture_and_no_execute():
    validator = text(ROOT / "scripts" / "validate-deployment-config.ps1")
    assert "Tests/fixtures/deployment/deployment-manifest.fixture.json" in validator
    assert "fixture-dry-run" in validator
    assert "-TargetLimit 1" in validator
    assert "-Execute" not in validator
