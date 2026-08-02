#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "harness/api/rework-prevention-registry.json"


def main() -> int:
    parser = argparse.ArgumentParser(description="Render the tracked SysAdminSuite rework-prevention registry in English.")
    parser.add_argument("--output", help="Optional output path. Defaults to stdout.")
    args = parser.parse_args()

    data = json.loads(REGISTRY.read_text(encoding="utf-8"))
    lines: list[str] = []
    lines.append("# SysAdminSuite Rework Prevention Status")
    lines.append("")
    lines.append(f"Registry: `{REGISTRY.relative_to(ROOT).as_posix()}`")
    lines.append(f"Controls: **{len(data['controls'])}**")
    lines.append(f"Known failure patterns: **{len(data['known_failure_patterns'])}**")
    lines.append("")
    lines.append("## Enforced controls")
    lines.append("")
    for item in data["controls"]:
        lines.append(f"- **{item['id']}** — {item['required_behavior']}")
        lines.append(f"  - Trigger: {item['trigger']}")
        lines.append(f"  - Forbidden: {item['forbidden_behavior']}")
        lines.append(f"  - Proof role: `{item['proof_artifact']}`")
    lines.append("")
    lines.append("## Known failure patterns")
    lines.append("")
    for item in data["known_failure_patterns"]:
        lines.append(f"- **{item['id']}** — {item['signal']}")
        lines.append(f"  - Controls: {', '.join(item['prevention_controls'])}")
    lines.append("")
    lines.append("## Forbidden retry patterns")
    lines.append("")
    for item in data["policy"]["forbidden_retry_patterns"]:
        lines.append(f"- `{item}`")
    lines.append("")
    lines.append("Proof ceiling: tracked static harness policy and wiring only; no live source, target, deployment, cleanup, reboot, or runtime proof is implied.")
    rendered = "\n".join(lines) + "\n"

    if args.output:
        path = Path(args.output)
        if not path.is_absolute():
            path = ROOT / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(rendered, encoding="utf-8")
        print(path)
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
