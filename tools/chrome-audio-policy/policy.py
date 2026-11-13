#!/usr/bin/env python3
"""Container-safe, read-only decision policy for local SysAdminSuite audio receipts.

Never opens an audio device, changes host settings, or interprets absence as OS corruption.
The actual repair remains Windows interactive-user Core Audio, not a Docker privilege trick.
"""
import argparse
import json
from pathlib import Path


SCHEMA = "sas.chrome-audio-recovery/v1"


def evaluate(receipt):
    if not isinstance(receipt, dict) or receipt.get("schema_version") != SCHEMA:
        raise ValueError("UNSUPPORTED_RECEIPT_SCHEMA")
    if receipt.get("action") not in ("Inspect", "Repair"):
        raise ValueError("UNSUPPORTED_ACTION")
    sessions = receipt.get("after")
    if not isinstance(sessions, list):
        raise ValueError("MISSING_AFTER_SESSIONS")
    for session in sessions:
        if not isinstance(session, dict):
            raise ValueError("INVALID_SESSION")
        if session.get("SessionState") not in ("ACTIVE", "INACTIVE", "EXPIRED"):
            raise ValueError("INVALID_SESSION_STATE")
        if type(session.get("IsDefaultDevice")) is not bool:
            raise ValueError("INVALID_DEFAULT_DEVICE_FLAG")
        if type(session.get("Muted")) is not bool:
            raise ValueError("INVALID_MUTE_FLAG")
        volume = session.get("VolumePercent")
        if type(volume) is not int or not 0 <= volume <= 100:
            raise ValueError("INVALID_VOLUME")
    if receipt.get("other_apps_modified") is not False or receipt.get("service_restart") is not False:
        raise ValueError("UNSAFE_RECOVERY_RECEIPT")

    active = [session for session in sessions if session["SessionState"] == "ACTIVE"]
    changed = receipt.get("changed_session_count", 0)
    if type(changed) is not int or changed < 0 or changed > len(sessions):
        raise ValueError("INVALID_CHANGE_COUNT")
    if receipt["action"] == "Inspect" and changed:
        raise ValueError("INSPECT_CANNOT_MUTATE")

    if not receipt.get("chrome_running", False):
        decision, instruction = "CHROME_NOT_RUNNING", "Launch Chrome and start playback before retesting."
    elif not sessions:
        decision, instruction = "NO_SESSION_INCONCLUSIVE", "Unmute the website/player, start playback, then inspect again."
    elif not active:
        decision, instruction = "NO_ACTIVE_SESSION", "Play audible media and inspect again; do not reset Windows."
    elif not any(s["IsDefaultDevice"] for s in active):
        decision, instruction = "NONDEFAULT_ENDPOINT", "Review Chrome's chosen output endpoint; do not automatically reroute it."
    elif any(s["Muted"] or s["VolumePercent"] == 0 for s in active):
        decision, instruction = "CHROME_MUTED_OR_ZERO", "Explicit Windows-host Repair may unmute or restore zero-volume Chrome sessions."
    else:
        decision, instruction = "CORE_AUDIO_SESSION_PRESENT", "Check website mute, site audio permissions and audible playback."

    return {
        "schema_version": "sas.chrome-audio-policy/v1",
        "decision": decision,
        "instruction": instruction,
        "chrome_sessions": len(sessions),
        "active_chrome_sessions": len(active),
        "repair_applied_to_chrome_sessions": changed,
        "user_hearing_verified": bool(receipt.get("user_acceptance_confirmed") is True),
        "auto_reset_authorized": False,
        "other_apps_modified": False,
        "runtime": "offline-policy-only",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="Local JSON receipt path (volume mount in Docker)")
    args = parser.parse_args()
    receipt = json.loads(Path(args.input).read_text(encoding="utf-8"))
    print(json.dumps(evaluate(receipt), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
