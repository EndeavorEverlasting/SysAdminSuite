#!/usr/bin/env python3
"""Dependency-free contracts for the agent sprint capsule schema and fixtures."""
from __future__ import annotations
import json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / 'schemas/harness/agent-sprint-capsule.schema.json'
FIXTURE_DIR = ROOT / 'Tests/fixtures/capsules'
VALID_FIXTURE = FIXTURE_DIR / 'valid-capsule.json'
GENERATOR = ROOT / 'tools/New-SasSprintCapsule.ps1'
CODEBASE_MAP = ROOT / 'CODEBASE_MAP.md'
PESTER_TEST = ROOT / 'Tests/Pester/SprintCapsule.Tests.ps1'

KEBAB = re.compile(r'^[a-z][a-z0-9-]*$')
SNAKE = re.compile(r'^[a-z][a-z0-9_]*$')
REPO_PATH = re.compile(
    r'^(?!/)(?![A-Za-z]:\\\\)(?!.*(?:^|/)\.\.(?:/|$)).+'
)
ISO_TS = re.compile(
    r'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
)
VERSION = re.compile(r'^[0-9]+\.[0-9]+\.[0-9]+$')
WINDOWS_ABS = re.compile(r'^[A-Za-z]:\\\\')
UNIX_ABS = re.compile(r'^/(?:tmp|home|etc|var|usr|opt)/')
LOCAL_ABS = re.compile(r'^(?:[A-Za-z]:\\\\|/[a-z])')

PROOF_LEVELS = [
    'P0_schema_validation', 'P1_static_lint', 'P2_unit_proof',
    'P3_integration', 'P4_unit_test', 'P5_smoke', 'P6_E2E_fixture',
    'P7_E2E_live', 'P8_runtime',
]


def read(path: Path) -> str:
    assert path.is_file(), f'missing required file: {path.relative_to(ROOT).as_posix()}'
    return path.read_text(encoding='utf-8')


def load_json(path: Path):
    return json.loads(read(path))


def test_schema_is_valid_json_schema():
    schema = load_json(SCHEMA)
    assert schema['$schema'] == 'https://json-schema.org/draft/2020-12/schema'
    assert schema['$id'] == 'schemas/harness/agent-sprint-capsule.schema.json'
    assert schema['additionalProperties'] is False
    required = set(schema['required'])
    assert required == {
        'schema_version', 'schema_path', 'capsule', 'sprint', 'branch',
        'scope', 'skills', 'capabilities', 'preflight', 'validation',
        'proof_ceiling', 'adapters',
    }


def test_schema_defines_rejection_patterns():
    schema = load_json(SCHEMA)
    defs = schema['$defs']

    branch = defs['branch_spec']['properties']['branch_name']
    assert 'pattern' in branch
    assert branch['pattern'].startswith('^[')

    sprint = defs['sprint_spec']['properties']['sprint_id']
    assert '$ref' in sprint or 'pattern' in sprint

    path_def = defs['repo_relative_path']
    assert 'pattern' in path_def
    assert 'traversal' in path_def.get('description', '') or '//' not in path_def['pattern']

    ceiling = defs['proof_ceiling_spec']['properties']['level']
    assert ceiling['enum'] == PROOF_LEVELS


def test_valid_fixture_matches_schema():
    capsule = load_json(VALID_FIXTURE)
    assert capsule['schema_version'] == 'sas-agent-sprint-capsule/v1'
    assert capsule['schema_path'] == 'schemas/harness/agent-sprint-capsule.schema.json'
    assert KEBAB.fullmatch(capsule['sprint']['sprint_id'])
    assert KEBAB.fullmatch(capsule['skills']['primary_skill'])
    assert ISO_TS.fullmatch(capsule['capsule']['generated_at'])
    assert VERSION.fullmatch(capsule['capsule']['generator_version'])
    assert capsule['proof_ceiling']['level'] in PROOF_LEVELS
    for lvl in capsule['proof_ceiling']['levels']:
        assert lvl in PROOF_LEVELS
        assert PROOF_LEVELS.index(lvl) <= PROOF_LEVELS.index(capsule['proof_ceiling']['level'])


def test_valid_fixture_scope_no_leakage():
    capsule = load_json(VALID_FIXTURE)
    for p in capsule['scope']['owned_paths']:
        assert not LOCAL_ABS.search(p), f'local path leakage in owned: {p}'
        assert '..' not in Path(p).parts, f'traversal in owned: {p}'
    for p in capsule['scope']['forbidden_scope']:
        assert not LOCAL_ABS.search(p), f'local path leakage in forbidden: {p}'
        assert '..' not in Path(p).parts, f'traversal in forbidden: {p}'
    owned = set(p.lower() for p in capsule['scope']['owned_paths'])
    forbidden = set(p.lower() for p in capsule['scope']['forbidden_scope'])
    assert owned.isdisjoint(forbidden), 'owned/forbidden overlap'


def test_valid_fixture_validation_commands_all_present():
    capsule = load_json(VALID_FIXTURE)
    v = capsule['validation']
    for key in ('schema_validate_command', 'pester_command',
                'ai_layer_validate_command', 'contract_command'):
        assert key in v, f'missing validation key: {key}'
        assert v[key], f'empty validation command: {key}'


def test_valid_fixture_adapters_defined():
    capsule = load_json(VALID_FIXTURE)
    assert 'opencode' in capsule['adapters']
    assert 'antigravity' in capsule['adapters']
    oc = capsule['adapters']['opencode']
    assert oc['root_instruction'] == 'AGENTS.md'
    assert 'capsule_source' in oc
    assert 'skill_load_method' in oc
    ag = capsule['adapters']['antigravity']
    assert 'capsule_source' in ag
    assert 'skill_load_method' in ag


def test_rejection_fixtures_are_well_formed():
    rejection_files = sorted(FIXTURE_DIR.glob('*-rejection.json'))
    assert len(rejection_files) >= 5, f'expected at least 5 rejection fixtures, found {len(rejection_files)}'
    for rfile in rejection_files:
        data = load_json(rfile)
        assert '_description' in data, f'{rfile.name} missing _description'
        assert '_expect' in data, f'{rfile.name} missing _expect'
        assert 'params' in data, f'{rfile.name} missing params'
        params = data['params']
        assert 'SprintId' in params, f'{rfile.name} missing SprintId'
        assert 'OwnedPaths' in params, f'{rfile.name} missing OwnedPaths'
        assert 'ForbiddenScope' in params, f'{rfile.name} missing ForbiddenScope'
        assert 'ProofCeiling' in params, f'{rfile.name} missing ProofCeiling'


def test_generator_script_exists():
    assert GENERATOR.is_file(), f'missing generator: {GENERATOR.relative_to(ROOT).as_posix()}'


def test_pester_test_exists():
    assert PESTER_TEST.is_file(), f'missing Pester test: {PESTER_TEST.relative_to(ROOT).as_posix()}'


def test_schema_and_fixture_listed_in_codebase_map():
    text = read(CODEBASE_MAP)
    assert 'schemas/harness/agent-sprint-capsule.schema.json' in text
    assert 'tools/New-SasSprintCapsule.ps1' in text


def main():
    tests = [
        test_schema_is_valid_json_schema,
        test_schema_defines_rejection_patterns,
        test_valid_fixture_matches_schema,
        test_valid_fixture_scope_no_leakage,
        test_valid_fixture_validation_commands_all_present,
        test_valid_fixture_adapters_defined,
        test_rejection_fixtures_are_well_formed,
        test_generator_script_exists,
        test_pester_test_exists,
        test_schema_and_fixture_listed_in_codebase_map,
    ]
    for test in tests:
        test()
    print(f'PASS: {len(tests)} agent sprint capsule contracts')


if __name__ == '__main__':
    main()
