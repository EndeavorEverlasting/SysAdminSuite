from __future__ import annotations

import csv
import importlib.util
import json
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = REPO_ROOT / "scripts" / "software_tracker_installs.py"
FIXTURES = REPO_ROOT / "Tests" / "fixtures"
CONFIG = REPO_ROOT / "Config" / "software-tracker.example.json"
INSTALLER_FIXTURES = REPO_ROOT / "Tests" / "fixtures" / "installers"


def load_module():
    spec = importlib.util.spec_from_file_location("software_tracker_installs", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def options(module, tracker: Path, tmp_path: Path, *, execute=False, allow=False, software_name=None):
    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    return module.PlanOptions(
        tracker_path=tracker,
        output_dir=tmp_path,
        execute=execute,
        allow_discovered_folder_installs=allow,
        config_path=CONFIG,
        software_name=software_name,
        path_aliases=config["pathAliases"],
    )


def test_catalog_dry_run_consumes_directories_fixture_and_never_executes(monkeypatch, tmp_path):
    module = load_module()
    called = []
    monkeypatch.setattr(module.subprocess, "run", lambda *a, **k: called.append((a, k)))

    items, reports = module.run(options(module, FIXTURES / "software_tracker_directories_schema.xlsx", tmp_path))

    assert INSTALLER_FIXTURES.exists()
    assert "Tests/fixtures/installers" in CONFIG.read_text(encoding="utf-8")
    assert called == []
    assert len(items) >= 9
    assert any(item.software_name == "DemoMSI" and item.status == "DryRun" for item in items)
    assert any(item.software_name == "DemoURL" and item.reason == "URL_EXECUTION_BLOCKED" for item in items)
    assert Path(reports["json"]).exists()
    assert Path(reports["csv"]).exists()
    assert Path(reports["text"]).exists()


def test_bad_rows_fixture_reports_clear_errors_not_crashes(tmp_path):
    module = load_module()
    items, _ = module.run(options(module, FIXTURES / "software_tracker_bad_rows.xlsx", tmp_path))
    reasons = {item.reason for item in items}

    assert "MISSING_SOFTWARE_NAME" in reasons
    assert "MISSING_INSTALLER_PATH" in reasons
    assert "AMBIGUOUS_INSTALL_REQUIRED" in reasons
    assert all(item.status == "Blocked" for item in items)


def test_execute_mode_required_for_mutation(monkeypatch, tmp_path):
    module = load_module()
    calls = []
    monkeypatch.setattr(module.subprocess, "run", lambda *a, **k: calls.append((a, k)))

    items, _ = module.run(options(module, FIXTURES / "software_tracker_directories_schema.xlsx", tmp_path, software_name="DemoMSI"))

    assert calls == []
    assert items[0].status == "DryRun"
    assert items[0].command_argv[0] == "msiexec.exe"


def test_execute_mode_invokes_safe_argv_without_shell(monkeypatch, tmp_path):
    module = load_module()
    calls = []

    class Completed:
        returncode = 0

    def fake_run(argv, shell=False, check=False):
        calls.append({"argv": argv, "shell": shell, "check": check})
        return Completed()

    monkeypatch.setattr(module.subprocess, "run", fake_run)
    items, _ = module.run(
        options(module, FIXTURES / "software_tracker_directories_schema.xlsx", tmp_path, execute=True, software_name="DemoMSI")
    )

    assert calls
    assert calls[0]["shell"] is False
    assert calls[0]["argv"][:2] == ["msiexec.exe", "/i"]
    assert items[0].status == "Succeeded"
    assert items[0].executed is True


def test_exe_without_silent_args_is_blocked_even_with_execute(tmp_path):
    module = load_module()
    items, _ = module.run(
        options(module, FIXTURES / "software_tracker_directories_schema.xlsx", tmp_path, execute=True, software_name="DemoEXE")
    )

    assert len(items) == 1
    assert items[0].status == "Blocked"
    assert items[0].reason == "EXE_REQUIRES_EXPLICIT_SILENT_ARGS"


def test_url_entries_are_never_opened_or_executed(monkeypatch, tmp_path):
    module = load_module()
    calls = []
    monkeypatch.setattr(module.subprocess, "run", lambda *a, **k: calls.append((a, k)))

    items, _ = module.run(
        options(module, FIXTURES / "software_tracker_directories_schema.xlsx", tmp_path, execute=True, software_name="DemoURL")
    )

    assert calls == []
    assert items[0].path_kind == "url"
    assert items[0].reason == "URL_EXECUTION_BLOCKED"


def test_folder_paths_are_manual_review_by_default(tmp_path):
    module = load_module()
    items, _ = module.run(options(module, FIXTURES / "software_tracker_directories_schema.xlsx", tmp_path, software_name="DemoFolder"))

    assert items[0].path_kind == "directory_path"
    assert items[0].status == "ManualReview"
    assert items[0].reason == "DIRECTORY_PATH_REQUIRES_MANUAL_REVIEW"


def test_folder_discovery_requires_execute_plus_allow_flag(tmp_path):
    module = load_module()
    dry_items, _ = module.run(
        options(module, FIXTURES / "software_tracker_directories_schema.xlsx", tmp_path / "dry", allow=True, software_name="DemoFolder")
    )
    exec_items, _ = module.run(
        options(
            module,
            FIXTURES / "software_tracker_directories_schema.xlsx",
            tmp_path / "exec",
            execute=True,
            allow=True,
            software_name="DemoFolder",
        )
    )

    assert dry_items[0].status == "ManualReview"
    assert exec_items[0].action == "DiscoverFolderInstallers"
    assert exec_items[0].reason.startswith("DISCOVERED_")


def test_quoted_spaces_unc_and_multi_paths_are_classified_safely(tmp_path):
    module = load_module()

    assert module.classify_path('"\\\\example-server\\share\\Demo\\setup.msi"') == "direct_installer_file"
    assert module.classify_path(r"\\example-server\share\Folder With Spaces") == "directory_path"

    items, _ = module.run(options(module, FIXTURES / "software_tracker_directories_schema.xlsx", tmp_path, software_name="DemoMulti"))
    normalized = {item.normalized_path for item in items}

    assert r"\\example-server\share\Multi\install.cmd" in normalized
    assert r"Z:\Multi\setup.msi" in normalized
    assert len(items) == 2


def test_reports_are_json_csv_and_text_with_expected_counts(tmp_path):
    module = load_module()
    items, reports = module.run(options(module, FIXTURES / "software_tracker_directories_schema.xlsx", tmp_path))

    data = json.loads(Path(reports["json"]).read_text(encoding="utf-8"))
    with Path(reports["csv"]).open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    text = Path(reports["text"]).read_text(encoding="utf-8")

    assert data["summary"]["total"] == len(items)
    assert len(rows) == len(items)
    assert "SysAdminSuite Software Tracker install plan" in text


def test_cli_wrapper_generates_reports_from_fixture(tmp_path):
    out_dir = tmp_path / "cli"
    result = subprocess.run(
        [
            "python",
            str(MODULE_PATH),
            "--tracker",
            str(FIXTURES / "software_tracker_directories_schema.xlsx"),
            "--config",
            str(CONFIG),
            "--output-dir",
            str(out_dir),
        ],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0
    assert (out_dir / "install-summary.json").exists()
    assert "reports" in result.stdout
