from __future__ import annotations

import csv
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "survey" / "fixtures" / "artifact_delivery"
VALIDATE = REPO_ROOT / "survey" / "sas-artifact-validate.py"
REVIEW_BUILD = REPO_ROOT / "survey" / "sas-review-queue-build.py"
PACKAGE = REPO_ROOT / "survey" / "sas-artifact-package.py"
SOURCE_EXTRACT = REPO_ROOT / "survey" / "sas-artifact-source-extract.py"
DASHBOARD = REPO_ROOT / "deployment-audit" / "sas-render-artifact-delivery-dashboard.py"


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, headers: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers)
        writer.writeheader()
        writer.writerows(rows)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class ArtifactDeliveryTests(unittest.TestCase):
    def run_cmd(self, args: list[str], expected: int = 0) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(args, cwd=REPO_ROOT, text=True, capture_output=True)
        self.assertEqual(
            result.returncode,
            expected,
            msg=f"Command failed.\nArgs: {args}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}",
        )
        return result

    def validate_fixture(self, fixture_name: str, artifact_type: str, tempdir: Path, expected: int = 0, extra: list[str] | None = None):
        output = tempdir / f"{fixture_name}.clean.csv"
        errors = tempdir / f"{fixture_name}.errors.csv"
        warnings = tempdir / f"{fixture_name}.warnings.csv"
        args = [
            sys.executable,
            str(VALIDATE),
            "--input",
            str(FIXTURES / fixture_name),
            "--artifact-type",
            artifact_type,
            "--output",
            str(output),
            "--errors",
            str(errors),
            "--warnings",
            str(warnings),
        ]
        if extra:
            args.extend(extra)
        self.run_cmd(args, expected=expected)
        return output, errors, warnings

    def test_source_extract_maps_deployment_tracker_export_shape(self):
        with tempfile.TemporaryDirectory() as td:
            output = Path(td) / "workstation_source.csv"
            self.run_cmd([
                sys.executable,
                str(SOURCE_EXTRACT),
                "--input",
                str(FIXTURES / "deployment_tracker_export_sample.csv"),
                "--profile",
                "deployment-tracker",
                "--source-file",
                "sample_deployment_tracker.xlsx::Deployments",
                "--output",
                str(output),
            ])
            rows = read_csv(output)
            self.assertEqual(len(rows), 2)
            self.assertEqual(rows[0]["SourceFile"], "sample_deployment_tracker.xlsx::Deployments")
            self.assertEqual(rows[0]["SourceRow"], "2")
            self.assertEqual(rows[0]["Hostname"], "SAMPLE-CYB-001")
            self.assertEqual(rows[0]["SerialNumber"], "SAMPLESER001")
            self.assertEqual(rows[0]["AssociatedNeuron"], "SAMPLE-NEURON-A")

    def test_source_extract_expands_ticket_tracker_multiline_hostnames(self):
        with tempfile.TemporaryDirectory() as td:
            output = Path(td) / "workstation_source.csv"
            self.run_cmd([
                sys.executable,
                str(SOURCE_EXTRACT),
                "--input",
                str(FIXTURES / "ticket_tracker_export_sample.csv"),
                "--profile",
                "ticket-tracker",
                "--source-file",
                "sample_ticket_tracker.xlsx::General",
                "--output",
                str(output),
            ])
            rows = read_csv(output)
            self.assertEqual([row["Hostname"] for row in rows], ["SAMPLE-CYB-010", "SAMPLE-CYB-011"])
            self.assertTrue(all(row["SourceRow"] == "2" for row in rows))
            self.assertTrue(all(row["DeviceType"] == "AutoLogon" for row in rows))

    def test_workstation_template_validates_clean_rows(self):
        with tempfile.TemporaryDirectory() as td:
            tempdir = Path(td)
            output, errors, warnings = self.validate_fixture(
                "workstation_source_clean_expected.csv",
                "workstation-source",
                tempdir,
            )
            self.assertEqual(read_csv(output), read_csv(FIXTURES / "workstation_source_clean_expected.csv"))
            self.assertEqual(read_csv(errors), [])

    def test_missing_identifiers_produce_validation_error(self):
        with tempfile.TemporaryDirectory() as td:
            tempdir = Path(td)
            output, errors, warnings = self.validate_fixture(
                "workstation_source_dirty.csv",
                "workstation-source",
                tempdir,
                expected=1,
            )
            error_types = {row["ErrorType"] for row in read_csv(errors)}
            self.assertIn("MissingIdentifier", error_types)
            self.assertEqual(len(read_csv(output)), 2)

    def test_mac_normalization_works(self):
        with tempfile.TemporaryDirectory() as td:
            tempdir = Path(td)
            output, errors, warnings = self.validate_fixture(
                "workstation_source_dirty.csv",
                "workstation-source",
                tempdir,
                expected=1,
            )
            rows = read_csv(output)
            self.assertEqual(rows[0]["MACAddress"], "AA:BB:CC:DD:EE:01")
            self.assertEqual(rows[1]["MACAddress"], "AA:BB:CC:DD:EE:02")

    def test_serial_normalization_works(self):
        with tempfile.TemporaryDirectory() as td:
            tempdir = Path(td)
            output, errors, warnings = self.validate_fixture(
                "workstation_source_dirty.csv",
                "workstation-source",
                tempdir,
                expected=1,
            )
            self.assertEqual(read_csv(output)[0]["SerialNumber"], "CYBFAKE001")

    def test_duplicate_serial_prefix_creates_warning(self):
        with tempfile.TemporaryDirectory() as td:
            tempdir = Path(td)
            output, errors, warnings = self.validate_fixture(
                "serial_prefixes_sample.csv",
                "serial-prefixes",
                tempdir,
            )
            warning_types = {row["WarningType"] for row in read_csv(warnings)}
            self.assertIn("DuplicateSerialPrefix", warning_types)

    def test_placeholder_serial_prefix_fails_in_production_mode(self):
        with tempfile.TemporaryDirectory() as td:
            tempdir = Path(td)
            output, errors, warnings = self.validate_fixture(
                "serial_prefixes_sample.csv",
                "serial-prefixes",
                tempdir,
                expected=1,
                extra=["--production-mode"],
            )
            error_types = {row["ErrorType"] for row in read_csv(errors)}
            self.assertIn("PlaceholderSerialPrefix", error_types)

    def test_review_queue_created_for_missing_serial_evidence(self):
        with tempfile.TemporaryDirectory() as td:
            output = Path(td) / "review_queue.csv"
            self.run_cmd([
                sys.executable,
                str(REVIEW_BUILD),
                "--reconciliation",
                str(FIXTURES / "reconciliation_sample.csv"),
                "--output",
                str(output),
            ])
            issue_types = [row["IssueType"] for row in read_csv(output)]
            self.assertIn("Missing serial evidence", issue_types)

    def test_review_queue_created_for_needs_field_capture(self):
        with tempfile.TemporaryDirectory() as td:
            output = Path(td) / "review_queue.csv"
            self.run_cmd([
                sys.executable,
                str(REVIEW_BUILD),
                "--reconciliation",
                str(FIXTURES / "reconciliation_sample.csv"),
                "--output",
                str(output),
            ])
            issue_types = [row["IssueType"] for row in read_csv(output)]
            self.assertIn("Needs field capture", issue_types)

    def test_review_queue_severity_rules_work(self):
        with tempfile.TemporaryDirectory() as td:
            output = Path(td) / "review_queue.csv"
            self.run_cmd([
                sys.executable,
                str(REVIEW_BUILD),
                "--reconciliation",
                str(FIXTURES / "reconciliation_sample.csv"),
                "--output",
                str(output),
            ])
            rows = read_csv(output)
            severities_by_issue = {}
            for row in rows:
                severities_by_issue.setdefault(row["IssueType"], set()).add(row["Severity"])

            self.assertIn("critical", severities_by_issue["Serial prefix conflict"])
            self.assertIn("critical", severities_by_issue["MAC conflict"])
            self.assertIn("critical", severities_by_issue["Duplicate serial"])
            self.assertIn("medium", severities_by_issue["Surveyed unreachable"])
            self.assertIn("medium", severities_by_issue["Hostname/IP missing"])
            self.assertIn("medium", severities_by_issue["Low confidence"])

    def test_artifact_package_creates_index_and_handoff_files(self):
        with tempfile.TemporaryDirectory() as td:
            tempdir = Path(td)
            review_queue = tempdir / "review_queue.csv"
            dashboard = tempdir / "dashboard.html"
            self.run_cmd([
                sys.executable,
                str(REVIEW_BUILD),
                "--reconciliation",
                str(FIXTURES / "reconciliation_sample.csv"),
                "--output",
                str(review_queue),
            ])
            self.run_cmd([
                sys.executable,
                str(DASHBOARD),
                "--review-queue",
                str(review_queue),
                "--reconciliation",
                str(FIXTURES / "reconciliation_sample.csv"),
                "--output",
                str(dashboard),
            ])
            self.run_cmd([
                sys.executable,
                str(PACKAGE),
                "--manifest",
                str(FIXTURES / "workstation_source_clean_expected.csv"),
                "--nmap-evidence",
                str(FIXTURES / "reconciliation_sample.csv"),
                "--reconciliation",
                str(FIXTURES / "reconciliation_sample.csv"),
                "--dashboard",
                str(dashboard),
                "--review-queue",
                str(review_queue),
                "--output-dir",
                str(tempdir / "delivery"),
                "--package-name",
                "sample_delivery",
            ])
            package_dirs = list((tempdir / "delivery").glob("sample_delivery_*"))
            self.assertEqual(len(package_dirs), 1)
            package_dir = package_dirs[0]
            self.assertTrue((package_dir / "ARTIFACT_INDEX.md").exists())
            self.assertTrue((package_dir / "handoff_summary.md").exists())
            self.assertTrue((package_dir / "workbook_import_notes.md").exists())
            self.assertTrue((package_dir / "05_dashboard.html").exists())

    def test_package_excludes_raw_nmap_output_unless_include_raw_is_passed(self):
        with tempfile.TemporaryDirectory() as td:
            tempdir = Path(td)
            raw_nmap = tempdir / "raw_nmap_output.txt"
            raw_nmap.write_text("Nmap scan report for 192.0.2.55\nHost is up.\n", encoding="utf-8")
            review_queue = tempdir / "review_queue.csv"
            dashboard = tempdir / "dashboard.html"
            shutil.copy2(FIXTURES / "review_queue_expected.csv", review_queue)
            dashboard.write_text("<html>sample</html>", encoding="utf-8")

            self.run_cmd([
                sys.executable,
                str(PACKAGE),
                "--manifest",
                str(FIXTURES / "workstation_source_clean_expected.csv"),
                "--nmap-evidence",
                str(raw_nmap),
                "--reconciliation",
                str(FIXTURES / "reconciliation_sample.csv"),
                "--dashboard",
                str(dashboard),
                "--review-queue",
                str(review_queue),
                "--output-dir",
                str(tempdir / "delivery"),
                "--package-name",
                "sample_delivery",
            ])
            package_dir = next((tempdir / "delivery").glob("sample_delivery_*"))
            self.assertFalse((package_dir / "02_nmap_workstation_evidence.csv").exists())
            self.assertIn("excluded", (package_dir / "ARTIFACT_INDEX.md").read_text(encoding="utf-8").lower())

            self.run_cmd([
                sys.executable,
                str(PACKAGE),
                "--manifest",
                str(FIXTURES / "workstation_source_clean_expected.csv"),
                "--nmap-evidence",
                str(raw_nmap),
                "--reconciliation",
                str(FIXTURES / "reconciliation_sample.csv"),
                "--dashboard",
                str(dashboard),
                "--review-queue",
                str(review_queue),
                "--output-dir",
                str(tempdir / "delivery2"),
                "--package-name",
                "sample_delivery",
                "--include-raw",
            ])
            package_dir_with_raw = next((tempdir / "delivery2").glob("sample_delivery_*"))
            self.assertTrue((package_dir_with_raw / "02_nmap_workstation_evidence.csv").exists())

    def test_input_files_are_never_modified(self):
        with tempfile.TemporaryDirectory() as td:
            tempdir = Path(td)
            source = tempdir / "workstation_source_dirty.csv"
            shutil.copy2(FIXTURES / "workstation_source_dirty.csv", source)
            before = sha256(source)
            self.run_cmd([
                sys.executable,
                str(VALIDATE),
                "--input",
                str(source),
                "--artifact-type",
                "workstation-source",
                "--output",
                str(tempdir / "clean.csv"),
                "--errors",
                str(tempdir / "errors.csv"),
                "--warnings",
                str(tempdir / "warnings.csv"),
            ], expected=1)
            self.assertEqual(sha256(source), before)

            recon = tempdir / "reconciliation_sample.csv"
            shutil.copy2(FIXTURES / "reconciliation_sample.csv", recon)
            before_recon = sha256(recon)
            review_queue = tempdir / "review_queue.csv"
            self.run_cmd([
                sys.executable,
                str(REVIEW_BUILD),
                "--reconciliation",
                str(recon),
                "--output",
                str(review_queue),
            ])
            self.assertEqual(sha256(recon), before_recon)


if __name__ == "__main__":
    unittest.main()
