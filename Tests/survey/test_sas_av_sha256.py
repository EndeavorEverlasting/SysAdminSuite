"""First-party signature controls and quiet callback integration."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import sas_antivirus as runner
import sas_av_sha256 as owned


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


class OwnedScannerTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="sas owned scanner ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.scope = self.root / "scan this folder"
        self.scope.mkdir()
        self.fixture = b"Benign SysAdminSuite detection fixture\n"
        self.signatures = self.root / "signature fixture.json"
        document = json.dumps({"schema_version": owned.SIGNATURE_SCHEMA,
                               "sha256": [sha256(self.fixture)]}).encode()
        self.signatures.write_bytes(document)
        self.pin = sha256(document)
        self.options = ("--scan-directory", str(self.scope), "--signatures", str(self.signatures),
                        "--signature-sha256", self.pin)

    def request(self, pin=None):
        return json.dumps({"scan_directory": str(self.scope), "signatures": str(self.signatures),
                           "signature_sha256": pin or self.pin}, sort_keys=True) + "\n"

    def scan(self):
        return owned.scan_directory(self.scope, owned.validate_scope(self.scope),
                                    owned.load_signatures(self.signatures, self.pin))

    def test_exact_match_and_one_byte_negative_control(self):
        path = self.scope / "benign fixture.bin"
        path.write_bytes(self.fixture + b"!")
        self.assertEqual(self.scan(), owned.NO_MATCH)
        path.write_bytes(self.fixture)
        self.assertEqual(self.scan(), owned.MATCH)
        self.assertEqual(path.read_bytes(), self.fixture)

    def test_incomplete_match_precedes_incomplete_control(self):
        (self.scope / "too large").write_bytes(b"x" * (len(self.fixture) + 1))
        with patch.object(owned, "MAX_FILE_BYTES", len(self.fixture)):
            self.assertEqual(self.scan(), owned.INCOMPLETE)
            (self.scope / "match").write_bytes(self.fixture)
            self.assertEqual(self.scan(), owned.MATCH_INCOMPLETE)
        self.assertIsNone(runner.development_candidate("DETECTION_REPORTED_INCOMPLETE"))

    def test_work_cap_and_changed_file_prevent_no_match_claim(self):
        (self.scope / "ordinary").write_bytes(b"small")
        with patch.object(owned, "MAX_ENTRIES", 0):
            self.assertEqual(self.scan(), owned.INCOMPLETE)
        with patch.object(owned, "digest_file", side_effect=ValueError("changed")):
            self.assertEqual(self.scan(), owned.INCOMPLETE)

    def test_scope_excludes_nested_directories_and_links(self):
        nested = self.scope / "nested"
        nested.mkdir()
        (nested / "payload").write_bytes(self.fixture)
        self.assertEqual(self.scan(), owned.NO_MATCH)
        try:
            (self.scope / "link").symlink_to(nested / "payload")
            (self.root / "alias").symlink_to(self.scope, target_is_directory=True)
        except (NotImplementedError, OSError):
            self.skipTest("test account cannot create symlinks")
        self.assertEqual(self.scan(), owned.NO_MATCH)
        with self.assertRaises(ValueError):
            owned.validate_scope(self.root / "alias")
        with self.assertRaises(ValueError):
            owned.validate_scope(Path(self.scope.anchor))

    def test_approved_document_must_be_exact_and_nonempty(self):
        payload = self.signatures.read_bytes()
        self.signatures.write_bytes(payload + b" ")
        with self.assertRaises(ValueError):
            owned.load_signatures(self.signatures, self.pin)
        for invalid in (
            json.dumps({"schema_version": owned.SIGNATURE_SCHEMA, "sha256": []}),
            json.dumps({"schema_version": owned.SIGNATURE_SCHEMA,
                        "sha256": [sha256(self.fixture)] * 2}),
            '{"schema_version":"sas-antivirus-sha256-signatures/v1","sha256":[],"sha256":[]}',
            "[" * 1100,
        ):
            self.signatures.write_bytes(invalid.encode())
            self.assertEqual(runner.scan(runner.owned_scanner(
                self.request(sha256(invalid.encode())), validate_only=True
            )), "OWNED_POLICY_REJECTED")

    def test_directory_change_and_hard_link_are_incomplete(self):
        (self.scope / "ordinary").write_bytes(b"ordinary file")
        digest = owned.digest_file
        def mutate(*args):
            result = digest(*args)
            (self.scope / "new").write_bytes(b"another file")
            return result
        with patch.object(owned, "digest_file", side_effect=mutate):
            self.assertEqual(self.scan(), owned.INCOMPLETE)
        outside = self.root / "outside"
        outside.write_bytes(self.fixture)
        try:
            os.link(outside, self.scope / "alias")
        except (AttributeError, OSError):
            self.skipTest("test account cannot create hard links")
        self.assertEqual(self.scan(), owned.INCOMPLETE)

    def test_cross_api_windows_ctime_difference(self):
        path = self.scope / "ordinary"
        path.write_bytes(b"bytes")
        st = path.stat()
        names = ("st_dev", "st_ino", "st_mode", "st_nlink", "st_size", "st_mtime_ns", "st_ctime_ns")
        copy = SimpleNamespace(**{name: getattr(st, name) for name in names})
        copy.st_ctime_ns += 1
        with patch.object(owned.os, "name", "nt"):
            self.assertTrue(owned.same_opened_file(st, copy))
            copy.st_ino += 1
            self.assertFalse(owned.same_opened_file(st, copy))

    @unittest.skipUnless(Path("/proc/sys/kernel/random/uuid").is_file(), "Linux pseudo-file control")
    def test_zero_reported_size_requires_real_eof(self):
        path = Path("/proc/sys/kernel/random/uuid")
        root = owned.validate_scope(path.parent)
        with self.assertRaisesRegex(ValueError, "recorded size"):
            owned.digest_file(SimpleNamespace(name=path.name), path.stat(), path.parent,
                              owned.identity(root), None, float("inf"))

    @unittest.skipUnless(sys.platform.startswith("linux"), "requires a native Linux cron shell")
    def test_quiet_callback_matches_then_rejects_changed_policy(self):
        checkout = self.root / "disposable checkout"
        (checkout / "scripts").mkdir(parents=True)
        for name in ("sas_antivirus.py", "sas_av_sha256.py"):
            shutil.copyfile(ROOT / "scripts" / name, checkout / "scripts" / name)
        subprocess.run(["git", "init", "-q", str(checkout)], check=True)
        (checkout / ".gitignore").write_text("evidence/*\n", encoding="utf-8")
        state = self.root / "private state"
        prefix = (sys.executable, "-I", str(checkout / "scripts/sas_antivirus.py"),
                  "--state-dir", str(state), *self.options)
        preview = json.loads(subprocess.check_output(
            (*prefix, "schedule", "plan", "--platform", "linux"), text=True
        ))
        shell = preview["plan"].split(maxsplit=5)[5]
        task = json.loads(subprocess.check_output(
            (*prefix, "schedule", "plan", "--platform", "windows"), text=True
        ))["plan"]
        scanner_command = " ".join(runner.owned_scanner(self.request()).command)
        for private in (str(self.scope), str(self.signatures), self.pin):
            for surface in (shell, task, scanner_command):
                self.assertNotIn(private, surface)
        self.assertFalse(state.exists())
        # Register through the production CLI with an isolated scheduler fixture.
        fixture_bin = self.root / "scheduler-bin"
        fixture_bin.mkdir()
        cron = fixture_bin / "crontab"
        cron.write_text(
            '#!/bin/sh\ncase "$1" in -l) printf "no crontab for fixture\\n" >&2; exit 1;; '
            '-) cat > "$SAS_TEST_CRONTAB";; esac\n', encoding="utf-8"
        )
        cron.chmod(0o700)
        installed = self.root / "registered cron"
        env = dict(os.environ, PATH=str(fixture_bin) + os.pathsep + os.environ["PATH"],
                   SAS_TEST_CRONTAB=str(installed))
        registration = json.loads(subprocess.check_output(
            (*prefix, "schedule", "install"), text=True, env=env
        ))
        self.assertEqual(registration["status"], "INSTALLED")
        self.assertEqual(installed.read_text().rstrip(), preview["plan"])
        fixture_name = "private scan filename.bin"
        (self.scope / fixture_name).write_bytes(self.fixture)
        for edit, expected in (("none", "DETECTION_REPORTED"), ("list", "OWNED_POLICY_REJECTED"),
                               ("profile", "OWNED_POLICY_REJECTED")):
            if edit == "list":
                payload = self.signatures.read_bytes()
                self.signatures.write_bytes(payload + b" ")
            elif edit == "profile":
                self.signatures.write_bytes(payload)
                profile = next(state.glob("owned-scan-*.json"))
                profile.write_bytes(profile.read_bytes() + b" ")
            process = subprocess.run(("/bin/sh", "-c", shell), capture_output=True, check=False)
            self.assertEqual((process.returncode, process.stdout, process.stderr), (1, b"", b""))
            raw = (state / "latest.json").read_text(encoding="utf-8")
            receipt = json.loads(raw)
            self.assertEqual((receipt["provider"], receipt["status"]),
                             ("sysadminsuite_sha256", expected))
            self.assertNotIn(fixture_name, raw)
            self.assertNotIn(self.pin, raw)
        queue = checkout / runner.QUEUE
        self.assertEqual([p.name for p in queue.iterdir()], ["owned_policy_rejected.json"])
        candidate = json.loads(next(queue.iterdir()).read_text(encoding="utf-8"))
        self.assertEqual(candidate, runner.development_candidate("OWNED_POLICY_REJECTED"))
        self.assertNotIn(self.pin, json.dumps(candidate))


if __name__ == "__main__":
    unittest.main()
