#!/usr/bin/env python3
"""Dependency-free contracts for the host-eligibility-policy schema and fixtures."""
from __future__ import annotations
import json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / 'schemas/harness/host-eligibility-policy.schema.json'
VALID_POLICY = ROOT / 'Tests/fixtures/host-eligibility/valid-policy.json'
FIXTURE_ONLY = ROOT / 'Tests/fixtures/host-eligibility/fixture-only-policy.json'
FIXTURE_DIR = ROOT / 'Tests/fixtures/host-eligibility'
VALIDATOR = ROOT / 'scripts/Test-SasHostEligibility.ps1'
PESTER = ROOT / 'Tests/Pester/HostEligibility.Tests.ps1'
CODEBASE_MAP = ROOT / 'CODEBASE_MAP.md'
GITIGNORE = ROOT / '.gitignore'

VERSION = re.compile(r'^[0-9]+\.[0-9]+\.[0-9]+$')
CONTEXT_KEYS = {'fixture', 'vm', 'local', 'remote', 'cybernet_physical'}
NO_IP = re.compile(r'^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')


def read(path: Path) -> str:
    assert path.is_file(), f'missing: {path.relative_to(ROOT).as_posix()}'
    return path.read_text(encoding='utf-8')


def load_json(path: Path):
    return json.loads(read(path))


def test_schema_is_fail_closed():
    schema = load_json(SCHEMA)
    assert schema['$schema'] == 'https://json-schema.org/draft/2020-12/schema'
    assert schema['$id'] == 'schemas/harness/host-eligibility-policy.schema.json'
    assert schema['additionalProperties'] is False
    required = set(schema['required'])
    assert required == {'schema_version', 'policy_version', 'execution_contexts', 'authorization', 'fallback_behavior'}


def test_schema_enforces_fail_closed_fallback():
    schema = load_json(SCHEMA)
    fb = schema['properties']['fallback_behavior']
    assert fb['enum'] == ['fail_closed']
    assert fb.get('default') == 'fail_closed'


def test_schema_requires_context_minimum():
    schema = load_json(SCHEMA)
    ctx = schema['properties']['execution_contexts']
    assert ctx['minProperties'] >= 1
    assert ctx['additionalProperties'] is False
    allowed = set(ctx['properties'].keys())
    assert allowed == CONTEXT_KEYS


def test_valid_policy_matches_schema():
    policy = load_json(VALID_POLICY)
    assert policy['schema_version'] == 'sas-host-eligibility-policy/v1'
    assert VERSION.fullmatch(policy['policy_version'])
    assert policy['fallback_behavior'] == 'fail_closed'
    assert set(policy['execution_contexts'].keys()) == CONTEXT_KEYS


def test_valid_policy_has_patterns_per_context():
    policy = load_json(VALID_POLICY)
    for ctx_name, ctx_rule in policy['execution_contexts'].items():
        assert 'enabled' in ctx_rule
        assert 'hostname_patterns' in ctx_rule
        assert 'require_authorization' in ctx_rule
        if ctx_rule['enabled']:
            assert len(ctx_rule['hostname_patterns']) >= 1, f'{ctx_name} enabled but no patterns'


def test_valid_policy_no_ip_in_patterns():
    policy = load_json(VALID_POLICY)
    for ctx_name, ctx_rule in policy['execution_contexts'].items():
        for pattern in ctx_rule['hostname_patterns']:
            assert not NO_IP.fullmatch(pattern), f'IP address in {ctx_name} pattern: {pattern}'
            assert '..' not in pattern, f'traversal in {ctx_name} pattern: {pattern}'


def test_valid_policy_authorization_spec():
    policy = load_json(VALID_POLICY)
    auth = policy['authorization']
    assert 'require_ticket_reference' in auth
    assert 'require_change_reference' in auth
    assert 'allowed_authorizers' in auth
    assert len(auth['allowed_authorizers']) >= 1


def test_fixture_only_policy_has_only_fixture():
    policy = load_json(FIXTURE_ONLY)
    assert set(policy['execution_contexts'].keys()) == {'fixture'}
    assert policy['execution_contexts']['fixture']['enabled'] is True
    assert policy['execution_contexts']['fixture']['require_authorization'] is False


def test_all_fixtures_are_well_formed():
    fixture_files = sorted(FIXTURE_DIR.glob('*.json'))
    assert len(fixture_files) >= 6, f'expected at least 6 fixtures, found {len(fixture_files)}'
    for ffile in fixture_files:
        data = load_json(ffile)
        if '_description' in data:
            assert '_expect' in data, f'{ffile.name} has _description but no _expect'


def test_validator_script_exists():
    assert VALIDATOR.is_file(), f'missing: {VALIDATOR.relative_to(ROOT).as_posix()}'


def test_pester_test_exists():
    assert PESTER.is_file(), f'missing: {PESTER.relative_to(ROOT).as_posix()}'


def test_codebase_map_lists_artifacts():
    text = read(CODEBASE_MAP)
    assert 'schemas/harness/host-eligibility-policy.schema.json' in text
    assert 'scripts/Test-SasHostEligibility.ps1' in text


def test_gitignore_has_policy_local():
    text = read(GITIGNORE)
    assert 'host-eligibility-policy.local.json' in text


def main():
    tests = [
        test_schema_is_fail_closed,
        test_schema_enforces_fail_closed_fallback,
        test_schema_requires_context_minimum,
        test_valid_policy_matches_schema,
        test_valid_policy_has_patterns_per_context,
        test_valid_policy_no_ip_in_patterns,
        test_valid_policy_authorization_spec,
        test_fixture_only_policy_has_only_fixture,
        test_all_fixtures_are_well_formed,
        test_validator_script_exists,
        test_pester_test_exists,
        test_codebase_map_lists_artifacts,
        test_gitignore_has_policy_local,
    ]
    for test in tests:
        test()
    print(f'PASS: {len(tests)} host eligibility contracts')


if __name__ == '__main__':
    main()
