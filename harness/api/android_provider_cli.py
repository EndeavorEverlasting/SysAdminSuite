"""Private receipt-producing typed AndroidProvider front door."""
from __future__ import annotations

import argparse
import json
import os
import re
import secrets
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from harness.api.android_provider import AndroidProvider, OWNED_DIR, ROLES, prepare_bundle, verify_bundle


def admit_source(expected_commit: str | None = None) -> dict:
    """Reuse the existing seal, or require a clean current canonical checkout.

    This never changes network posture or pulls a dirty/diverged checkout.
    Engineering worktrees execute synthetic fixtures only.
    """
    def run(argv, cwd=None):
        completed = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=60)
        if completed.returncode:
            raise RuntimeError("SOURCE_ADMISSION_FAILED")
        return completed.stdout.strip()

    state_file = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "SysAdminSuite/autologon-short-runtime.json"
    state = json.loads(state_file.read_text(encoding="utf-8-sig")) if state_file.is_file() else {}
    if state.get("runtime_root") and Path(state["runtime_root"]).resolve() == ROOT.resolve():
        if not expected_commit or not re.fullmatch(r"[a-f0-9]{40}", expected_commit):
            raise RuntimeError("SELECTED_REFRESHED_COMMIT_REQUIRED")
        required = {"harness/api/android_provider.py", "harness/api/android_provider_cli.py", "Run-SasAndroidProvider.cmd", "scripts/Test-SasAutoLogonRuntimeSeal.ps1"}
        sealed_paths = {str(entry.get("path", "")).replace("\\", "/") for entry in state.get("tracked_file_hashes", [])}
        if not required.issubset(sealed_paths):
            raise RuntimeError("ANDROID_CAPABILITY_NOT_SEALED")
        seal = ROOT / "scripts/Test-SasAutoLogonRuntimeSeal.ps1"
        if not seal.is_file():
            raise RuntimeError("SEALED_RUNTIME_AUTHORITY_MISSING")
        run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(seal), "-RuntimeRoot", str(ROOT), "-ExpectedCommit", expected_commit])
        return {"source_admission": "EXISTING_TRACKED_FILE_SEAL", "source_currentness": "SELECTED_PREPARED_OFFLINE", "source_commit": expected_commit}
    resolved = json.loads(run(["powershell.exe", "-NoProfile", "-File", str(ROOT / "scripts/Resolve-SasCanonicalDevelopmentPath.ps1"), "-AsJson", "-RequireCheckout"]))
    canonical = Path(resolved["canonical_development_checkout"])
    if ROOT.resolve() != canonical.resolve():
        raise RuntimeError("CANONICAL_DEVELOPMENT_CHECKOUT_REQUIRED")
    prefix = ["git", "-C", str(ROOT)]
    origin = run(prefix + ["remote", "get-url", "origin"])
    if origin not in {"https://github.com/EndeavorEverlasting/SysAdminSuite.git", "git@github.com:EndeavorEverlasting/SysAdminSuite.git"}:
        raise RuntimeError("UNSUPPORTED_GIT_ORIGIN")
    # Capture starting posture, refuse protected-profile Git rather than making
    # an implicit organization-specific Wi-Fi/VPN transition.
    starting = json.loads(run(["powershell.exe", "-NoProfile", "-Command", "Import-Module './scripts/SasNetworkIntent.psm1' -Force; Get-SasNetworkIntentState -RepoRoot (Get-Location).Path | ConvertTo-Json -Compress"], cwd=ROOT))
    if starting.get("classification") != "GUEST_INTERNET":
        raise RuntimeError("PREPARED_OFFLINE_RUNTIME_REQUIRED_ON_PROTECTED_NETWORK")
    if run(prefix + ["status", "--porcelain"]):
        raise RuntimeError("DIRTY_CANONICAL_CHECKOUT")
    run(prefix + ["fetch", "origin", "--prune", "--tags"])
    default = run(prefix + ["symbolic-ref", "refs/remotes/origin/HEAD"])
    selected = run(prefix + ["rev-parse", default])
    head = run(prefix + ["rev-parse", "HEAD"])
    if head != selected:
        raise RuntimeError("CANONICAL_CHECKOUT_NOT_CURRENT")
    return {"source_admission": "CANONICAL_CURRENT_CLEAN", "source_commit": head, "starting_network": starting,
            "network_restore": "NOT_CHANGED"}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("status", "doctor", "prepare", "verify", "probe", "inventory", "tcpip-cert", "stop-server", "last-result"))
    parser.add_argument("--role", choices=sorted(ROLES))
    parser.add_argument("--identity-file", type=Path)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--archive-sha256")
    parser.add_argument("--authorize-transport", action="store_true")
    parser.add_argument("--expected-commit", help="Provider-selected refreshed 40-character commit for offline sealed source admission.")
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
              "authority": "READ_ONLY_ALLOWED", "proof": "REPOSITORY_VALIDATED",
              "next_action": "Inspect the private receipt and resolve the next typed gate."}
    try:
        if args.fixture:
            if args.operation not in {"status", "doctor", "verify"}:
                raise ValueError("FIXTURE_ONLY_SUPPORTS_HOST_STATUS")
            fixture = json.loads(args.fixture.read_text(encoding="utf-8"))
            if fixture.get("synthetic") is not True or fixture.get("state") not in {"READY", "MISSING_BUNDLE"}:
                raise ValueError("SYNTHETIC_STATUS_FIXTURE_REQUIRED")
            result.update({"state": fixture["state"], "result": "SUCCESS" if fixture["state"] == "READY" else "BLOCK", "proof": "FIXTURE_ONLY"})
        else:
            result.update(admit_source(args.expected_commit))
            # Node roles are explicit configuration authority, never guessed from hostname.
            node_file = OWNED_DIR.parent / "android-node.json"
            role = args.role or (json.loads(node_file.read_text(encoding="utf-8"))["node_role"] if node_file.is_file() else None)
            provider = AndroidProvider(role)
            if args.operation == "prepare":
                if not args.archive or not args.archive_sha256 or not args.role:
                    raise ValueError("PREPARE_REQUIRES_ROLE_LOCAL_ARCHIVE_AND_APPROVED_HASH")
                prepare_bundle(args.archive, args.archive_sha256)
                node_file.write_text(json.dumps({"node_role": role}) + "\n", encoding="utf-8")
            if args.operation in {"doctor", "stop-server"}:
                result.update(provider.server(stop=args.operation == "stop-server"))
            elif args.operation in {"status", "prepare", "verify"}:
                result.update(provider.status())
                result["result"] = "SUCCESS" if result["state"] == "READY" else "BLOCK"
                result["next_action"] = "Use the typed probe operation." if result["result"] == "SUCCESS" else "Prepare an approved local archive before field entry."
            else:
                identity = json.loads(args.identity_file.read_text(encoding="utf-8")) if args.identity_file else None
                result.update(provider.inspect(args.operation, identity, authorized=args.authorize_transport))
    except Exception as exc:
        # Exception text may contain private paths/identifiers; report only its class.
        code = str(exc)
        result.update({"result": "BLOCK", "reason": code if re.fullmatch(r"[A-Z][A-Z0-9_]{3,80}", code) else type(exc).__name__, "next_action": "Resolve the named source/node/runtime/identity admission gate before retry."})
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    path = output / f"receipt-{stamp}-{secrets.token_hex(4)}.json"
    result["evidence_location"] = str(path)
    path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"{result['result']}: {result.get('state', result.get('reason', 'UNKNOWN'))}")
    print(f"Evidence: {path}")
    return 0 if result["result"] == "SUCCESS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
