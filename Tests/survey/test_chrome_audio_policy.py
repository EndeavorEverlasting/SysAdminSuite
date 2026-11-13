"""Synthetic, no-Windows-required regression tests for the portable decision boundary."""
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tools" / "chrome-audio-policy" / "policy.py"
spec = importlib.util.spec_from_file_location("sas_chrome_audio_policy", SOURCE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def receipt(sessions=(), running=True, action="Inspect", changed=0):
    return {
        "schema_version": "sas.chrome-audio-recovery/v1",
        "action": action,
        "chrome_running": running,
        "after": list(sessions),
        "changed_session_count": changed,
        "service_restart": False,
        "other_apps_modified": False,
        "user_acceptance_confirmed": False,
    }


def session(state="ACTIVE", default=True, muted=False, volume=25):
    return {
        "SessionState": state,
        "IsDefaultDevice": default,
        "Muted": muted,
        "VolumePercent": volume,
    }


class ChromeAudioPolicyTests(unittest.TestCase):
    def test_muted_youtube_no_session_is_inconclusive_not_corruption(self):
        result = module.evaluate(receipt())
        self.assertEqual(result["decision"], "NO_SESSION_INCONCLUSIVE")
        self.assertFalse(result["auto_reset_authorized"])

    def test_no_chrome_process(self):
        self.assertEqual(module.evaluate(receipt(running=False))["decision"], "CHROME_NOT_RUNNING")

    def test_inactive_audio_session(self):
        self.assertEqual(
            module.evaluate(receipt([session(state="INACTIVE")]))["decision"],
            "NO_ACTIVE_SESSION",
        )

    def test_nondefault_endpoint_is_not_auto_rerouted(self):
        result = module.evaluate(receipt([session(default=False)]))
        self.assertEqual(result["decision"], "NONDEFAULT_ENDPOINT")
        self.assertFalse(result["auto_reset_authorized"])

    def test_muted_session_eligible_only_for_explicit_host_repair(self):
        self.assertEqual(
            module.evaluate(receipt([session(muted=True)]))["decision"],
            "CHROME_MUTED_OR_ZERO",
        )

    def test_zero_volume_session(self):
        self.assertEqual(
            module.evaluate(receipt([session(volume=0)]))["decision"],
            "CHROME_MUTED_OR_ZERO",
        )

    def test_existing_volume_is_not_a_repair_candidate(self):
        self.assertEqual(
            module.evaluate(receipt([session(volume=35)]))["decision"],
            "CORE_AUDIO_SESSION_PRESENT",
        )

    def test_repair_receipt_never_claims_hearing_proof(self):
        result = module.evaluate(receipt([session()], action="Repair", changed=1))
        self.assertEqual(result["repair_applied_to_chrome_sessions"], 1)
        self.assertFalse(result["user_hearing_verified"])

    def test_inspect_cannot_claim_mutation(self):
        with self.assertRaisesRegex(ValueError, "INSPECT_CANNOT_MUTATE"):
            module.evaluate(receipt([session()], changed=1))

    def test_cross_app_mutation_prohibited(self):
        row = receipt([session()])
        row["other_apps_modified"] = True
        with self.assertRaisesRegex(ValueError, "UNSAFE_RECOVERY_RECEIPT"):
            module.evaluate(row)

    def test_service_restart_prohibited(self):
        row = receipt([session()])
        row["service_restart"] = True
        with self.assertRaisesRegex(ValueError, "UNSAFE_RECOVERY_RECEIPT"):
            module.evaluate(row)

    def test_schema_drift_fails_closed(self):
        row = receipt()
        row["schema_version"] = "unknown"
        with self.assertRaisesRegex(ValueError, "UNSUPPORTED_RECEIPT_SCHEMA"):
            module.evaluate(row)

    def test_invalid_volume_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "INVALID_VOLUME"):
            module.evaluate(receipt([session(volume=150)]))


if __name__ == "__main__":
    unittest.main()
