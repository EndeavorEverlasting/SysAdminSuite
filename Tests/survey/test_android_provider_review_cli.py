"""Offline source-admission and private profile routing regressions."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch, MagicMock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from harness.api import android_provider_cli as cli


class CliReviewTests(unittest.TestCase):
    def admission(self, *, dirty=False, behind=False, diverged=False, owned=True, branch="main", equality=True):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        calls = []
        pulled = False

        def run(argv, **kwargs):
            nonlocal pulled
            calls.append(argv)
            text, code = "", 0
            if argv[0] == "powershell.exe":
                if "-File" in argv:
                    text = json.dumps({"canonical_development_checkout": str(root)})
                elif "Get-Acl" in argv[-1]:
                    text = "True" if owned else "False"
                else:
                    text = json.dumps({"classification": "GUEST_INTERNET"})
            else:
                command = argv[3:]
                if command == ["remote", "get-url", "origin"]:
                    text = "https://github.com/EndeavorEverlasting/SysAdminSuite.git"
                elif command == ["status", "--porcelain"]:
                    text = " M synthetic.py" if dirty else ""
                elif command == ["rev-parse", "--absolute-git-dir"]:
                    text = str(root / ".git")
                elif command == ["symbolic-ref", "refs/remotes/origin/HEAD"]:
                    text = "refs/remotes/origin/main"
                elif command == ["symbolic-ref", "--short", "HEAD"]:
                    text = branch
                elif command == ["rev-parse", "refs/remotes/origin/main"]:
                    text = "b" * 40
                elif command == ["rev-parse", "HEAD"]:
                    text = "a" * 40 if behind and (not pulled or not equality) else "b" * 40
                elif command[:2] == ["merge-base", "--is-ancestor"]:
                    code = int(diverged)
                elif command[:2] == ["pull", "--ff-only"]:
                    pulled = True
            return subprocess.CompletedProcess(argv, code, text, "")

        with patch.object(cli, "ROOT", root), patch.object(cli.subprocess, "run", side_effect=run), patch.dict(cli.os.environ, {"LOCALAPPDATA": str(root)}):
            try:
                result = cli.admit_source()
            except RuntimeError as exc:
                result = str(exc)
        return result, calls

    def test_clean_behind_uses_only_bounded_pull_and_proves_equality(self):
        result, calls = self.admission(behind=True)
        self.assertTrue(result["source_updated"])
        self.assertEqual(result["source_commit"], "b" * 40)
        self.assertIn(["pull", "--ff-only", "origin", "main"], [call[3:] for call in calls])

    def test_dirty_diverged_unowned_nondefault_never_pull(self):
        for scenario in ({"dirty": True}, {"behind": True, "diverged": True}, {"owned": False}, {"branch": "feature"}):
            with self.subTest(scenario=scenario):
                result, calls = self.admission(**scenario)
                self.assertIsInstance(result, str)
                self.assertFalse(any("pull" in call for call in calls))

    def test_post_pull_wrong_head_blocks(self):
        result, _ = self.admission(behind=True, equality=False)
        self.assertEqual(result, "CANONICAL_CHECKOUT_NOT_CURRENT")

    def test_updated_source_reexecutes_before_provider_construction(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(cli, "ROOT", Path(temporary)), patch.object(cli, "admit_source", return_value={"source_updated": True}), patch.object(cli, "AndroidProvider", side_effect=AssertionError("stale provider used")), patch.object(cli.subprocess, "run", return_value=subprocess.CompletedProcess([], 7)) as child, patch.dict(cli.os.environ, {"SAS_ANDROID_SOURCE_RESTART": "0"}):
            self.assertEqual(cli.main(["status", "--role", "ptop_lab"]), 7)
            self.assertEqual(child.call_args.kwargs["env"]["SAS_ANDROID_SOURCE_RESTART"], "1")
            self.assertEqual(child.call_args.args[0][2:], ["status", "--role", "ptop_lab"])

    def test_private_profile_routed_without_inference(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            profile = {"schema_version": "sas-android-target-profile/v1", "synthetic": True}
            path = root / "profile.json"
            path.write_text(json.dumps(profile))
            instance = MagicMock()
            instance.inspect.return_value = {"result": "BLOCK", "state": "PROFILE_REQUIRED"}
            with patch.object(cli, "ROOT", root), patch.object(cli, "admit_source", return_value={}), patch.object(cli, "AndroidProvider", return_value=instance):
                self.assertEqual(cli.main(["tcpip-cert", "--role", "ptop_lab", "--profile-file", str(path), "--authorize-transport"]), 2)
            instance.inspect.assert_called_once_with("tcpip-cert", None, authorized=True, profile_authority=profile)


if __name__ == "__main__":
    unittest.main()
