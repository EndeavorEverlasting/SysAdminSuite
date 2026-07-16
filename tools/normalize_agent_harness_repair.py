#!/usr/bin/env python3
"""Normalize exact-match quoting in the temporary PR #224 repair helper."""
from pathlib import Path

path = Path(__file__).with_name("repair_agent_harness_review.py")
text = path.read_text(encoding="utf-8")

schema_start = text.index("    replace_once(\n        path,\n        '''    for bad in")
schema_end = text.index('\n\n    path = "Tests/survey/test_agent_routing_manifest_contracts.py"', schema_start)
schema_replacement = """    target = ROOT / path
    source = target.read_text(encoding=\"utf-8\")
    function_start = source.index(\"def test_schema_rejects_local_paths_when_jsonschema_is_available() -> None:\\n\")
    function_end = source.index(\"\\n\\ndef main() -> None:\", function_start)
    replacement_function = '''def test_schema_rejects_local_paths_when_jsonschema_is_available() -> None:
    try:
        import jsonschema
    except ImportError:
        return
    schema, fixture = load(SCHEMA), load(FIXTURE)
    jsonschema.validate(fixture, schema)
    for bad in (r\"C:\\\\Users\\\\operator\\\\repo\", \"/home/operator/repo\", \"/mnt/c/Users/operator/repo\", \"/workspace/SysAdminSuite\", \"/tmp/sas-run\", \"token=abc\", \"password: abc\", \"secret = abc\"):
        candidate = copy.deepcopy(fixture)
        candidate[\"handoff\"][\"next_command\"] = bad
        try:
            jsonschema.validate(candidate, schema)
        except jsonschema.ValidationError:
            pass
        else:
            raise AssertionError(f\"schema accepted machine-local or secret-like handoff text: {bad}\")
    candidate = copy.deepcopy(fixture)
    candidate[\"scope\"][\"owned_paths\"][0] = r\"safe\\\\..\\\\outside\"
    try:
        jsonschema.validate(candidate, schema)
    except jsonschema.ValidationError:
        pass
    else:
        raise AssertionError(\"schema accepted a backslash parent-traversal repository path\")
'''
    target.write_text(source[:function_start] + replacement_function + source[function_end:], encoding=\"utf-8\")"""
text = text[:schema_start] + schema_replacement + text[schema_end:]

ci_start = text.index("    replace_once(\n        path,\n        '''    assert \"python3 Tests/survey/test_agent_sprint_capsule_contracts.py\" in ci")
ci_end = text.index("\n    target = ROOT / path", ci_start)
ci_replacement = """    target = ROOT / path
    source = target.read_text(encoding=\"utf-8\")
    marker = '    assert \"python3 Tests/survey/test_agent_sprint_capsule_contracts.py\" in ci\\n'
    if source.count(marker) != 1:
        raise RuntimeError(f\"expected one capsule CI assertion, found {source.count(marker)}\")
    additions = '    assert \"tools/Test-Pester5Suite.ps1\" in ci\\n    assert \"scripts/SasRunContext.psm1\" in ci\\n'
    source = source.replace(marker, marker + additions, 1)
    target.write_text(source, encoding=\"utf-8\")
"""
text = text[:ci_start] + ci_replacement + text[ci_end:]

before = text
text = text.replace(r"\S*", r"\S+")
if text == before:
    raise RuntimeError("no staged POSIX path pattern was tightened")
path.write_text(text, encoding="utf-8")
print("PASS: temporary repair helper normalized")
