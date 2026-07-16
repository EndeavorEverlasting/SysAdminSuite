#!/usr/bin/env python3
"""Normalize one structural test rewrite in the temporary PR #224 repair helper."""
from pathlib import Path

path = Path(__file__).with_name("repair_agent_harness_review.py")
text = path.read_text(encoding="utf-8")
start = text.index("    replace_once(\n        path,\n        '''    for bad in")
end = text.index('\n\n    path = "Tests/survey/test_agent_routing_manifest_contracts.py"', start)
replacement = """    target = ROOT / path
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
path.write_text(text[:start] + replacement + text[end:], encoding="utf-8")
print("PASS: temporary repair helper normalized")
