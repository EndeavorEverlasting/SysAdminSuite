#!/usr/bin/env python3
"""Static safety contracts for the opt-in Windows live-proof command."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
SCRIPT=ROOT/"scripts/Invoke-SasWindowsWorkstationLiveProof.ps1"
SCHEMA=ROOT/"schemas/harness/developer-workstation-live-proof.schema.json"


def test_surfaces_parse_and_schema_is_closed() -> None:
    schema=json.loads(SCHEMA.read_text(encoding="utf-8"))
    assert schema["properties"]["proof"]["properties"]["operator_accepted"]["const"] is False
    assert schema["properties"]["proof"]["properties"]["provider_response_observed"]["const"] is False
    parser="& { $e=$null; [Management.Automation.Language.Parser]::ParseFile($args[0],[ref]$null,[ref]$e)|Out-Null; if($e.Count){exit 1} }"
    subprocess.run(["pwsh","-NoProfile","-Command",parser,str(SCRIPT)],cwd=ROOT,check=True)


def test_runtime_proof_is_scoped_and_content_free() -> None:
    text=SCRIPT.read_text(encoding="utf-8-sig")
    assert "tmux', 'send-keys'" in text and "--help >/dev/null 2>&1" in text
    assert "$HOME/.local/agent-switchboard/bin" in text
    assert "Stop-Process -Id" in text and "Stop-Process -Name" not in text
    assert "detach-client" in text and "WezTerm tmux.lnk" in text
    assert "chat_content" not in text and "token" not in text.lower()
    assert "provider_response_observed = $false" in text and "operator_accepted = $false" in text


if __name__=="__main__":
    tests=[value for name,value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:test()
    print(f"PASS: {len(tests)} Windows live-proof safety contract groups")
