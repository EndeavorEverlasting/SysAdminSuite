#!/usr/bin/env python3
"""Contracts for the machine-readable SysAdminSuite agent trigger and routing manifest."""
from __future__ import annotations
import json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'harness/api/agent-routing-manifest.json'
SCHEMA = ROOT / 'schemas/harness/agent-routing-manifest.schema.json'
AI_LAYER_DOC = ROOT / 'docs/AI_LAYER.md'
CODEBASE_MAP = ROOT / 'CODEBASE_MAP.md'
RUNNER = ROOT / 'tests/survey/run_offline_survey_tests.sh'
HARNESS_API = ROOT / 'harness/api/sas-harness-api.json'

REQUIRED_TRIGGER_IDS = {
    'repository-sprint-trigger',
    'language-runtime-trigger',
    'field-workflow-trigger',
    'scoped-validation-trigger',
    'end-to-end-validation-trigger',
    'live-data-guard-trigger',
    'survey-low-noise-trigger',
    'developer-workstation-trigger',
    'agent-sprint-capsule-trigger'
}

ID_PATTERN = re.compile(r'^[a-z][a-z0-9-]*$')

def read(path):
    assert path.is_file(), f'missing required file: {path.relative_to(ROOT).as_posix()}'
    return path.read_text(encoding='utf-8')

def load_json(path):
    return json.loads(read(path))

def test_manifest_and_schema_define_fail_closed_contract():
    manifest = load_json(MANIFEST)
    schema = load_json(SCHEMA)
    assert manifest['schema_version'] == 'sas-agent-routing-manifest/v1'
    assert manifest['schema_path'] == 'schemas/harness/agent-routing-manifest.schema.json'
    assert schema['$schema'] == 'https://json-schema.org/draft/2020-12/schema'
    assert schema['$id'] == manifest['schema_path']
    assert schema['additionalProperties'] is False
    assert {'schema_version', 'schema_path', 'triggers', 'ambiguity_rules'} <= set(schema['required'])

    rules = manifest['ambiguity_rules']
    assert rules['explicit_user_lane_wins'] is True
    assert rules['safety_guard_triggers_compose_additively'] is True
    assert rules['equal_priority_conflict_resolution'] == 'fail_closed_to_repository_sprint'
    assert rules['no_trigger_authorizes_mutation'] is True

def test_trigger_entries_are_complete_and_valid():
    triggers = load_json(MANIFEST)['triggers']
    ids = [t['id'] for t in triggers]
    assert len(ids) == len(set(ids)), f'duplicate trigger IDs: {ids}'
    for trigger_id in ids:
        assert ID_PATTERN.fullmatch(trigger_id), f'invalid trigger ID: {trigger_id}'
    assert set(ids) == REQUIRED_TRIGGER_IDS

    for t in triggers:
        assert len(t['summary']) >= 20
        assert isinstance(t['deterministic_task_signals'], list)
        assert len(t['deterministic_task_signals']) >= 2
        assert isinstance(t['priority'], int)
        assert t['composition_mode'] in {'exclusive', 'additive', 'fallback'}
        assert t['target_type'] in {'skill', 'capability', 'harness_operation'}
        assert isinstance(t['target'], str)
        assert isinstance(t['required_inputs'], list)
        assert isinstance(t['outputs'], list)
        assert isinstance(t['preconditions'], list)
        assert isinstance(t['guardrails'], list)
        assert isinstance(t['owner'], str)
        assert isinstance(t['validators'], list)
        assert isinstance(t['proof_ceiling'], str)

def test_manifest_is_wired_and_referenced():
    required_path = 'harness/api/agent-routing-manifest.json'
    schema_path = 'schemas/harness/agent-routing-manifest.schema.json'
    assert required_path in read(CODEBASE_MAP), f'CODEBASE_MAP.md does not name manifest'
    assert schema_path in read(CODEBASE_MAP), f'CODEBASE_MAP.md does not name schema'

def test_schema_validation_when_available():
    try:
        import jsonschema
    except ImportError:
        return
    jsonschema.validate(load_json(MANIFEST), load_json(SCHEMA))

def main():
    tests = [
        test_manifest_and_schema_define_fail_closed_contract,
        test_trigger_entries_are_complete_and_valid,
        test_manifest_is_wired_and_referenced,
        test_schema_validation_when_available
    ]
    for test in tests:
        test()
    print(f'PASS: {len(tests)} agent trigger and routing manifest contracts')

if __name__ == '__main__':
    main()
