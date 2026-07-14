#!/usr/bin/env python3
"""Dependency-free contract tests for host eligibility policy schema and sample."""

import json
import os
import re
import sys

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SCHEMA_PATH = os.path.join(REPO_ROOT, 'schemas', 'harness', 'host-eligibility-policy.schema.json')
SAMPLE_PATH = os.path.join(REPO_ROOT, 'Config', 'host-eligibility-policy.sample.json')

REAL_HOSTNAMES = re.compile(r'(?i)CHEEX|LPW003ASI|NT2K|NORTHWELL|NSLIJ')


def load_json(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def test_schema_exists():
    assert os.path.isfile(SCHEMA_PATH), f'Schema not found: {SCHEMA_PATH}'


def test_sample_exists():
    assert os.path.isfile(SAMPLE_PATH), f'Sample policy not found: {SAMPLE_PATH}'


def test_schema_is_valid_json():
    schema = load_json(SCHEMA_PATH)
    assert schema.get('$id') == 'schemas/harness/host-eligibility-policy.schema.json'


def test_schema_requires_core_fields():
    schema = load_json(SCHEMA_PATH)
    required = schema.get('required', [])
    for field in ['schema_version', 'policy_id', 'policy_version', 'patterns']:
        assert field in required, f'Missing required field in schema: {field}'


def test_schema_pattern_requires_name_regex_actions():
    schema = load_json(SCHEMA_PATH)
    pattern_props = schema['properties']['patterns']['items']['properties']
    pattern_required = schema['properties']['patterns']['items']['required']
    for field in ['name', 'regex', 'actions']:
        assert field in pattern_required, f'Pattern missing required field: {field}'


def test_sample_schema_version():
    sample = load_json(SAMPLE_PATH)
    assert sample['schema_version'] == 'sas-host-eligibility-policy/v1'


def test_sample_has_policy_id_and_version():
    sample = load_json(SAMPLE_PATH)
    assert 'policy_id' in sample and len(sample['policy_id']) > 0
    assert re.match(r'^\d{4}\.\d{2}\.\d{2}$', sample['policy_version'])


def test_sample_has_patterns():
    sample = load_json(SAMPLE_PATH)
    patterns = sample.get('patterns', [])
    assert len(patterns) > 0, 'Sample policy must have at least one pattern'


def test_sample_patterns_have_required_fields():
    sample = load_json(SAMPLE_PATH)
    for pattern in sample['patterns']:
        assert 'name' in pattern and len(pattern['name']) > 0
        assert pattern.get('match_type') == 'regex'
        assert 'regex' in pattern and len(pattern['regex']) > 0
        assert 'actions' in pattern and len(pattern['actions']) > 0


def test_sample_no_real_hostnames():
    with open(SAMPLE_PATH, 'r', encoding='utf-8') as f:
        content = f.read()
    assert not REAL_HOSTNAMES.search(content), 'Sample policy contains real hostnames'


def test_sample_no_duplicate_pattern_names():
    sample = load_json(SAMPLE_PATH)
    names = [p['name'] for p in sample['patterns']]
    assert len(names) == len(set(names)), 'Sample policy has duplicate pattern names'


def test_sample_pattern_actions_are_valid():
    valid_actions = {'local', 'remote', 'fixture', 'vm'}
    sample = load_json(SAMPLE_PATH)
    for pattern in sample['patterns']:
        for action in pattern['actions']:
            assert action in valid_actions, f'Invalid action in pattern {pattern["name"]}: {action}'


def test_sample_regexes_are_valid():
    sample = load_json(SAMPLE_PATH)
    for pattern in sample['patterns']:
        try:
            re.compile(pattern['regex'])
        except re.error as e:
            assert False, f'Invalid regex in pattern {pattern["name"]}: {e}'


if __name__ == '__main__':
    tests = [v for k, v in sorted(globals().items()) if k.startswith('test_')]
    passed = 0
    failed = 0
    for test in tests:
        try:
            test()
            passed += 1
            print(f'  PASS  {test.__name__}')
        except AssertionError as e:
            failed += 1
            print(f'  FAIL  {test.__name__}: {e}')
        except Exception as e:
            failed += 1
            print(f'  ERROR {test.__name__}: {e}')
    print(f'\n{passed} passed, {failed} failed')
    sys.exit(1 if failed > 0 else 0)
