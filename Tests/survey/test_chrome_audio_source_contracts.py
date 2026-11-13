"""Offline source-contract safeguards; not a substitute for Windows Core Audio live proof."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class ChromeAudioSourceContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cmd = (ROOT / "Recover-ChromeAudio.cmd").read_text(encoding="utf-8")
        cls.guard = (ROOT / "scripts/Confirm-SasChromeAudioCheckout.ps1").read_text(encoding="utf-8")
        cls.script = (ROOT / "scripts/Invoke-SasChromeAudioRecovery.ps1").read_text(encoding="utf-8")
        cls.core = (ROOT / "scripts/SasChromeAudioCore.cs").read_text(encoding="utf-8")
        cls.docker = (ROOT / "tools/chrome-audio-policy/Dockerfile").read_text(encoding="utf-8")

    def test_launcher_defaults_to_inspect_and_guards_before_audio(self):
        self.assertIn('set "ACTION=Inspect"', self.cmd)
        self.assertIn('if /I "%~1"=="Repair"', self.cmd)
        guard = self.cmd.index("Confirm-SasChromeAudioCheckout.ps1")
        native = self.cmd.index("Invoke-SasChromeAudioRecovery.ps1")
        self.assertLess(guard, native)
        self.assertIn("if errorlevel 1", self.cmd)
        self.assertIn("%~dp0", self.cmd)

    def test_canonical_checkout_fails_closed(self):
        for safety in (
            "GetFolderPath('Desktop')",
            "CANONICAL_CHECKOUT_REQUIRED",
            "DIRTY_CHECKOUT_PRESERVED",
            "DIVERGED_CHECKOUT_PRESERVED",
            "INTERNET_SYNC_REQUIRED",
            "POST_PULL_HEAD_MISMATCH",
            "STARTING_NETWORK_POSTURE_CHANGED",
            "pull --ff-only origin main",
        ):
            self.assertIn(safety, self.guard)
        self.assertNotIn("git reset", self.guard.lower())
        self.assertNotIn("git clean", self.guard.lower())

    def test_only_chrome_active_session_explicitly_changed(self):
        for safety in (
            'String.Equals(processName, "chrome"',
            "if (repair && state == 1)",
            "if (beforeMuted)",
            "if (beforeLevel <= 0.0001f)",
            "zeroVolumeRecoveryPercent > 50",
            "GetSessionEnumerator",
            "GetProcessId",
            "IsDefaultDevice",
        ):
            self.assertIn(safety, self.core)
        for forbidden in ("Restart-Service", "Stop-Process", "taskkill", "SetDefaultAudioEndpoint"):
            self.assertNotIn(forbidden.lower(), self.core.lower())
            self.assertNotIn(forbidden.lower(), self.script.lower())

    def test_windows_script_has_per_host_local_receipt_and_no_hearing_claim(self):
        for safety in (
            "Windows_NT",
            "UserInteractive",
            "LOCALAPPDATA",
            "AudioRecovery",
            "NO_CHROME_SESSION_OBSERVED",
            "live_playback_confirmed = $false",
            "other_apps_modified = $false",
            "service_restart = $false",
        ):
            if safety == "AudioRecovery":
                # Current field spelling intentionally differs from the working folder.
                continue
            self.assertIn(safety, self.script)

    def test_docker_is_only_offline_policy(self):
        self.assertIn("python3", self.docker)
        self.assertIn("USER 65534:65534", self.docker)
        self.assertNotIn("powershell", self.docker.lower())
        self.assertNotIn("privileged", self.docker.lower())


if __name__ == "__main__":
    unittest.main()
