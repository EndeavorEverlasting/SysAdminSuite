"""Private receipt-producing typed AndroidProvider front door."""
from __future__ import annotations

import argparse
import json
import secrets
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from harness.api.android_provider import AndroidProvider, OWNED_DIR, ROLES, prepare_bundle, verify_bundle


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("status", "doctor", "prepare", "verify", "probe", "inventory", "tcpip-cert", "last-result"))
    parser.add_argument("--role", choices=sorted(ROLES))
    parser.add_argument("--identity-file", type=Path)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--archive-sha256")
    parser.add_argument("--authorize-transport", action="store_true")
    parser.add_argument("--fixture", type=Path, help="Synthetic status fixture; no device/runtime execution.")
    args = parser.parse_args(argv)
    output = ROOT / "survey/output/android-provider"
    output.mkdir(parents=True, exist_ok=True)
    if args.operation == "last-result":
        candidates = sorted(output.glob("receipt-*.json"))
        if not candidates:
            print("BLOCK: no provider receipt exists")
            return 2
        print(candidates[-1])
        return 0
    result = {"schema_version": "sas-android-provider-receipt/v1", "operation": args.operation,
              "node_role": args.role, "result": "BLOCK", "cleanup": "NOT_REQUIRED",
              "authority": "READ_ONLY_ALLOWED", "proof": "REPOSITORY_VALIDATED"}
    try:
        if args.fixture:
            if args.operation not in {"status", "doctor", "verify"}:
                raise ValueError("FIXTURE_ONLY_SUPPORTS_HOST_STATUS")
            fixture = json.loads(args.fixture.read_text(encoding="utf-8"))
            if fixture.get("synthetic") is not True or fixture.get("state") not in {"READY", "MISSING_BUNDLE"}:
                raise ValueError("SYNTHETIC_STATUS_FIXTURE_REQUIRED")
            result.update({"state": fixture["state"], "result": "SUCCESS" if fixture["state"] == "READY" else "BLOCK", "proof": "FIXTURE_ONLY"})
        else:
            # Node roles are explicit configuration authority, never guessed from hostname.
            node_file = OWNED_DIR.parent / "android-node.json"
            role = args.role or (json.loads(node_file.read_text(encoding="utf-8"))["node_role"] if node_file.is_file() else None)
            provider = AndroidProvider(role)
            if args.operation == "prepare":
                if not args.archive or not args.archive_sha256 or not args.role:
                    raise ValueError("PREPARE_REQUIRES_ROLE_LOCAL_ARCHIVE_AND_APPROVED_HASH")
                prepare_bundle(args.archive, args.archive_sha256)
                node_file.write_text(json.dumps({"node_role": role}) + "\n", encoding="utf-8")
            if args.operation in {"status", "doctor", "prepare", "verify"}:
                result.update(provider.status())
                result["result"] = "SUCCESS" if result["state"] == "READY" else "BLOCK"
                result["next_action"] = "Use the typed probe operation." if result["result"] == "SUCCESS" else "Prepare an approved local archive before field entry."
            else:
                identity = json.loads(args.identity_file.read_text(encoding="utf-8")) if args.identity_file else None
                result.update(provider.inspect(args.operation, identity, authorized=args.authorize_transport))
    except Exception as exc:
        # Exception text may contain private paths/identifiers; report only its class.
        result.update({"result": "BLOCK", "reason": type(exc).__name__, "next_action": "Resolve node configuration/runtime/identity admission before retry."})
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    path = output / f"receipt-{stamp}-{secrets.token_hex(4)}.json"
    result["evidence_location"] = str(path)
    path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"{result['result']}: {result.get('state', result.get('reason', 'UNKNOWN'))}")
    print(f"Evidence: {path}")
    return 0 if result["result"] == "SUCCESS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
