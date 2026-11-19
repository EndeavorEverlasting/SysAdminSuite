"""Status-only contract used by SysAdminSuite's FileSteward scheduler adapter."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

PRODUCER_VERSION = "filesteward.antivirus-detection/v1"
# The first column is FileSteward's outcome. The second is a SysAdminSuite
# operational receipt status. An interpreter failure can also exit 1.
OUTCOMES = {
    0: ("COMPLETED", "SCAN_COMPLETED"),
    1: ("LOCAL_STATE_UNAVAILABLE", "SCAN_FAILED"),
    10: ("INCOMPLETE", "SCAN_INCOMPLETE"),
    12: ("POLICY_REJECTED", "DETECTOR_POLICY_REJECTED"),
    13: ("DEPENDENCY_UNAVAILABLE", "DETECTOR_DEPENDENCY_UNAVAILABLE"),
}
FILESTEWARD_RESULTS = {code: status for code, (_, status) in OUTCOMES.items()}

EXPECTED_SCHEDULER = {
    "consumer": "SysAdminSuite",
    "operations": {"check": "VALIDATE_POLICY_AND_SCOPE", "run": "INSPECT_APPROVED_SCOPE"},
    "transport": "EXIT_STATUS_ONLY",
    "exit_codes": {outcome: code for code, (outcome, _) in OUTCOMES.items()},
    "completion_is_match_independent": True,
    "forwards_file_evidence": False,
    "grants_action_authority": False,
}


def validate_filesteward_contract(document: object) -> bool:
    """Verify the exact v1 scheduler contract with type-sensitive comparison."""
    if not isinstance(document, dict):
        return False
    if document.get("schema_version") != PRODUCER_VERSION or document.get("owner") != "FileSteward":
        return False
    # JSON equality keeps false/true distinct from integer statuses.
    return json.dumps(document.get("scheduler"), sort_keys=True) == json.dumps(
        EXPECTED_SCHEDULER, sort_keys=True
    )


def _unique_object(pairs):
    result = dict(pairs)
    if len(result) != len(pairs):
        raise ValueError("Duplicate contract key")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("contract", help="FileSteward's public contract JSON, or - for stdin")
    arg = parser.parse_args().contract
    try:
        if arg == "-":
            raw = sys.stdin.buffer.read(65537)
        else:
            with Path(arg).open("rb") as stream:
                raw = stream.read(65537)
        valid = len(raw) <= 65536 and validate_filesteward_contract(
            json.loads(raw, object_pairs_hook=_unique_object)
        )
    except (OSError, ValueError, RecursionError):
        valid = False
    print("FILESTEWARD_SCHEDULER_CONTRACT_COMPATIBLE" if valid else "FILESTEWARD_SCHEDULER_CONTRACT_REJECTED")
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
