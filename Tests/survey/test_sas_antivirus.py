"""Host-antivirus tests use synthetic scanner outcomes and isolated scheduler state."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import sas_antivirus as av


class AntivirusTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="sas av private fixture ")
        self.addCleanup(temp.cleanup)
        self.temp = Path(temp.name).resolve()
        self.state = self.temp / "private state"
        self.home = self.temp / "private home"
        self.programs = [self.temp / "Program Files"]

    def test_selection_never_uses_registration_command(self):
        windows = lambda probe, names: av.choose_scanner(
            "windows", probe, lambda path: path.name in names, self.programs, self.home
        )
        self.assertEqual(windows("DEFENDER_READY", {"ecls.exe"})[0].provider, "defender")
        module_dir = self.programs[0] / "ESET" / "ESET Security" / "Modules"
        module_dir.mkdir(parents=True)
        eset = windows("REGISTERED", {"ecls.exe"})[0]
        self.assertEqual(eset.provider, "eset")
        self.assertIn("/clean-mode=none", eset.command)
        self.assertIn(f"/base-dir={module_dir}", eset.command)
        self.assertEqual(eset.working_directory, module_dir.parent)
        self.assertEqual(eset.results[10], "SCAN_INCOMPLETE")
        self.assertEqual(windows("REGISTERED", {"mbam.exe"}), (None, "VENDOR_SCHEDULER_REQUIRED"))
        self.assertEqual(windows("REGISTERED", set()), (None, "UNSUPPORTED_PROVIDER"))
        self.assertEqual(windows("NONE", set()), (None, "NO_PROVIDER"))
        self.assertEqual(windows("DISCOVERY_FAILED", set()), (None, "DISCOVERY_FAILED"))
        self.assertEqual(av.choose_scanner("wsl", "", lambda _: True, [], self.home),
                         (None, "UNSUPPORTED_HOST"))

    def test_clamav_outcomes_do_not_retain_output(self):
        scanner, _ = av.choose_scanner(
            "linux", "", lambda path: path.name == "clamscan", [], self.home
        )
        self.assertIn("--cross-fs=no", scanner.command)
        self.assertEqual(scanner.command[-1], str(self.home))
        for code, expected in ((0, "NO_DETECTIONS_REPORTED"), (1, "DETECTION_REPORTED"),
                               (2, "SCAN_FAILED")):
            with self.subTest(code=code), patch.object(av, "execute", return_value=(
                subprocess.CompletedProcess(scanner.command, code, "PRIVATE-FILE", "PRIVATE-HOST")
            )) as proc:
                self.assertEqual(av.scan(scanner), expected)
                proc.assert_called_once_with(scanner.command, timeout=av.SCAN_TIMEOUT_SECONDS, cwd=None)
        with patch.object(av, "execute", side_effect=subprocess.TimeoutExpired("fixture", 1)):
            self.assertEqual(av.scan(scanner), "SCAN_TIMEOUT")

    def test_defender_acknowledgment_is_not_completion(self):
        scanner = av.choose_scanner("windows", "DEFENDER_READY", lambda _: False, [], self.home)[0]
        with patch.object(av, "powershell", return_value=("ven",)), patch.object(av, "execute") as run:
            run.return_value.returncode = 11
            self.assertEqual(av.scan(scanner), "SCAN_UNCONFIRMED")
            run.return_value.returncode = 0
            self.assertEqual(av.scan(scanner), "SCAN_COMPLETED")
        self.assertIn("QuickScanStartTime", av.DEFENDER_SCAN)
        self.assertIn("QuickScanEndTime", av.DEFENDER_SCAN)

    def test_privacy_projection_and_checkout_sync(self):
        subprocess.run(["git", "init", "-q", str(self.temp)], check=True)
        (self.temp / ".gitignore").write_text("evidence/*\n", encoding="utf-8")
        av.persist(self.state, dict(av.new_receipt("windows", "none", "UNSUPPORTED_PROVIDER"),
                                    forbidden="PRIVATE-HOST PRIVATE-PATH PRIVATE-IDENTITY"))
        av.persist(self.state, av.new_receipt("linux", "clamav", "DETECTION_REPORTED"))
        av.persist(self.state, av.new_receipt("linux", "clamav", "NO_DETECTIONS_REPORTED"))
        self.assertEqual(av.sync_candidates(self.state, self.temp), "SYNCED_LOCAL")
        outbox = self.temp / av.QUEUE
        self.assertEqual([p.name for p in outbox.iterdir()], ["unsupported_provider.json"])
        content = next(outbox.iterdir()).read_text(encoding="utf-8")
        self.assertEqual(json.loads(content), {
            "schema_version": "sas-antivirus-development-candidate/v1",
            "gap_code": "UNSUPPORTED_PROVIDER",
            "next_action": "ADD_DOCUMENTED_PROVIDER_ADAPTER",
            "publication_state": "LOCAL_REVIEW_REQUIRED",
        })
        self.assertEqual(av.sync_candidates(self.state, self.temp), "SYNCED_LOCAL")
        self.assertEqual(next(outbox.iterdir()).read_text(encoding="utf-8"), content)
        (self.temp / ".gitignore").write_text("", encoding="utf-8")
        self.assertEqual(av.sync_candidates(self.state, self.temp), "SYNC_UNSAFE")
        subprocess.run(["git", "-C", str(self.temp), "add", str(next(outbox.iterdir()))], check=True)
        (self.temp / ".gitignore").write_text("evidence/*\n", encoding="utf-8")
        self.assertEqual(av.sync_candidates(self.state, self.temp), "SYNC_UNSAFE")
        with patch.dict(os.environ, {"GIT_INDEX_FILE": str(self.temp / "alternate-index")}):
            self.assertEqual(av.sync_candidates(self.state, self.temp), "SYNC_UNSAFE")

    def test_one_scan_per_state_and_crash_recovery(self):
        with av.state_lock(self.state) as acquired:
            self.assertTrue(acquired)
            with patch.object(av, "discover") as discover:
                self.assertEqual(av.run_once(self.state), ({"status": "ALREADY_RUNNING"}, 0))
                discover.assert_not_called()
        av.persist(self.state, av.new_receipt("linux", "clamav", "RUNNING"), retain=False)
        with patch.object(av, "discover", return_value=(None, "NO_PROVIDER")), patch.object(
            av, "sync_candidates", side_effect=OSError("PRIVATE-PATH")
        ):
            receipt, code = av.run_once(self.state)
        self.assertEqual(code, 1)
        self.assertEqual(receipt["status"], "NO_PROVIDER")
        self.assertEqual(receipt["repository_sync"], "SYNC_FAILED")
        self.assertEqual(receipt["sync_next_action"], "RETRY_LOCAL_QUEUE_SYNC")
        self.assertNotIn("PRIVATE", json.dumps(receipt))
        self.assertEqual(
            {json.loads(p.read_text())["status"] for p in (self.state / "history").glob("*.json")},
            {"NO_PROVIDER", "SCAN_INTERRUPTED"},
        )

    def test_bounded_history(self):
        history = self.state / "history"
        history.mkdir(parents=True)
        unrelated = history / "0-unrelated-user.json"
        unrelated.write_text("preserve this file", encoding="utf-8")
        for _ in range(av.HISTORY_LIMIT + 4):
            av.persist(self.state, av.new_receipt("linux", "clamav", "NO_DETECTIONS_REPORTED"))
        self.assertEqual(len(list(history.glob("run-*.json"))), av.HISTORY_LIMIT)
        self.assertEqual(unrelated.read_text(encoding="utf-8"), "preserve this file")

    def test_private_state_rejects_other_git_worktrees(self):
        worktree = self.temp / "other worktree"
        worktree.mkdir()
        (worktree / ".git").write_text("gitdir: fixture", encoding="utf-8")
        with self.assertRaises(ValueError):
            av.private_state_path(worktree / "private nested")

    def test_linux_crontab_install_repeat_and_rollback(self):
        # Include a Unicode line separator and a non-UTF-8 byte in unrelated entries.
        other = "# unrelated cron entry\r\n17 4 * * * command '\u2028'\n".encode() + b"# \xff\n"
        line = av.cron_line(av.callback(self.state), "Monday", "04:47")
        original = other
        calls = []
        def crontab(command, **kwargs):
            if command[-1] == "-l":
                return subprocess.CompletedProcess(command, 0, original, b"")
            calls.append(kwargs["input"])
            return subprocess.CompletedProcess(command, 0)
        with patch.object(av.shutil, "which", return_value="/fixture/crontab"), patch.object(
            av.subprocess, "run", side_effect=crontab
        ):
            self.assertEqual(av.apply_cron(None), "UNCHANGED")
            self.assertEqual(len(calls), 0)
            self.assertEqual(av.apply_cron(line), "INSTALLED")
            self.assertEqual(calls[-1], other + os.fsencode(line) + b"\n")
            original = calls[-1]
            self.assertEqual(av.apply_cron(line), "UNCHANGED")
            self.assertEqual(len(calls), 1)
            self.assertEqual(av.apply_cron(None), "REMOVED")
            self.assertEqual(calls[-1], other)
        with self.assertRaises(ValueError):
            av.cron_line(("private%path",), "Monday", "04:47")

    @unittest.skipUnless(os.name == "posix", "requires a POSIX cron command shell")
    def test_cron_callback_runs_silently_through_cli(self):
        # Execute the generated command in cron's shell with a fresh checkout and
        # only the real CLI. No scheduler is installed and no live scanner runs.
        (self.temp / "scripts").mkdir()
        entrypoint = self.temp / "scripts/sas_antivirus.py"
        av.shutil.copyfile(av.__file__, entrypoint)
        fixture = entrypoint.with_name("offline-provider-fixture.py")
        fixture.write_text(
            "import sys\nfrom pathlib import Path\n"
            "sys.path.insert(0, str(Path(__file__).resolve().parent))\n"
            "import sas_antivirus\n"
            "sas_antivirus.discover = lambda host: (None, 'NO_PROVIDER')\n"
            "raise SystemExit(sas_antivirus.main())\n",
            encoding="utf-8",
        )
        subprocess.run(["git", "init", "-q", str(self.temp)], check=True)
        (self.temp / ".gitignore").write_text("evidence/*\n", encoding="utf-8")
        state = self.temp.parent / (self.temp.name + " external state")
        self.addCleanup(av.shutil.rmtree, state, True)
        line = av.cron_line((sys.executable, "-I", str(fixture), "--state-dir",
                             str(state), "run", "--quiet"), "Monday", "04:47")
        self.assertTrue(line.startswith("47 4 * * 1 "))
        task = subprocess.run(["/bin/sh", "-c", line.split(maxsplit=5)[5]],
                              capture_output=True, text=True, check=False)
        self.assertEqual((task.returncode, task.stdout, task.stderr), (1, "", ""))
        actual = json.loads((state / "latest.json").read_text(encoding="utf-8"))
        self.assertEqual(actual["status"], "NO_PROVIDER")
        self.assertEqual(actual["repository_sync"], "SYNCED_LOCAL")
        self.assertTrue((self.temp / av.QUEUE / "no_provider.json").exists())

    def test_windows_powershell_prefers_native_view(self):
        shell = Path("WindowsPowerShell/v1.0/powershell.exe")
        native = self.programs[0] / "Sysnative" / shell
        native.parent.mkdir(parents=True)
        native.touch()
        with patch.dict(os.environ, {"SystemRoot": str(self.programs[0])}):
            self.assertEqual(av.powershell("exit 0")[0], str(native))
            native.unlink()
            self.assertEqual(av.powershell("exit 0")[0], str(self.programs[0] / "System32" / shell))

    def test_windows_task_xml_and_registration_dispatch(self):
        command = (r"C:\Program Files\Python\python.exe", "-I", r"C:\test dir\tool.py",
                   "--state-dir", r"C:\test state", "run", "--quiet")
        xml = av.scheduled_task_xml(command, "Friday", "06:30")
        root = ET.fromstring(xml)
        ns = {"t": av.TASK_NS}
        self.assertIsNotNone(root.find(".//t:DaysOfWeek/t:Friday", ns))
        self.assertTrue(root.findtext(".//t:StartBoundary", namespaces=ns).endswith("T06:30:00"))
        self.assertEqual(root.findtext(".//t:Command", namespaces=ns), command[0])
        self.assertEqual(root.findtext(".//t:Arguments", namespaces=ns),
                         subprocess.list2cmdline(command[1:]))
        self.assertEqual(root.findtext(".//t:LogonType", namespaces=ns), "S4U")
        self.assertEqual(root.findtext(".//t:RunLevel", namespaces=ns), "LeastPrivilege")
        self.assertEqual(root.findtext(".//t:MultipleInstancesPolicy", namespaces=ns), "IgnoreNew")
        self.assertEqual(root.findtext(".//t:DisallowStartIfOnBatteries", namespaces=ns), "true")
        self.assertEqual(root.findtext(".//t:StopIfGoingOnBatteries", namespaces=ns), "true")
        with patch.object(av, "powershell", return_value=("fixture-powershell",)) as ps, patch.object(
            av, "execute", return_value=subprocess.CompletedProcess((), 0, "INSTALLED\n", "")
        ):
            self.assertEqual(av.apply_windows_task(xml), "INSTALLED")
            script = ps.call_args.args[0]
            self.assertIn("Register-ScheduledTask", script)
            self.assertIn("GetCurrent().User.Value", script)
            self.assertNotIn("ExecutionPolicy Bypass", script)


if __name__ == "__main__":
    unittest.main()
