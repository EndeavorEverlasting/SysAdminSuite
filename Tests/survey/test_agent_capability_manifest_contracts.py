#!/usr/bin/env python3
"""Contracts for the machine-readable SysAdminSuite agent capability manifest."""
from __future__ import annotations
import json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; MANIFEST=ROOT/'harness/api/agent-capability-manifest.json'; SCHEMA=ROOT/'schemas/harness/agent-capability-manifest.schema.json'; CAPABILITY_CATALOG=ROOT/'.claude/capabilities/README.md'; AI_LAYER_DOC=ROOT/'docs/AI_LAYER.md'; CODEBASE_MAP=ROOT/'CODEBASE_MAP.md'; WORKFLOW=ROOT/'.github/workflows/agent-instruction-contracts.yml'; RUNNER=ROOT/'tests/survey/run_offline_survey_tests.sh'; HARNESS_API=ROOT/'harness/api/sas-harness-api.json'
REQUIRED_CAPABILITY_IDS={'repository-evidence','proof-and-checkpointing','end-to-end-testing','language-runtime-selection','mutation-and-evidence-boundaries','field-command-design'}
REQUIRED_SKILL_IDS={'repository-sprint','language-runtime','field-workflow','scoped-validation','end-to-end-validation','live-data-guard','survey-low-noise'}
ID_PATTERN=re.compile(r'^[a-z][a-z0-9-]*$'); VERSION_PATTERN=re.compile(r'^[0-9]+\.[0-9]+\.[0-9]+$'); CAPABILITY_LINK=re.compile(r'\(\.\./\.\./capabilities/([A-Za-z0-9._-]+\.md)\)')
def read(path):
    assert path.is_file(),f'missing required file: {path.relative_to(ROOT).as_posix()}'; return path.read_text(encoding='utf-8')
def load_json(path):return json.loads(read(path))
def repo_path(value):
    assert value and not value.startswith('/'),f'path must be repository-relative: {value!r}'; assert not re.match(r'^[A-Za-z]:[\\/]',value),f'absolute Windows path is forbidden: {value}'; assert '..' not in Path(value).parts,f'parent traversal is forbidden: {value}'; return ROOT/value
def assert_unique_ids(items,item_type):
    ids=[item['id'] for item in items]; assert len(ids)==len(set(ids)),f'duplicate {item_type} IDs: {ids}'
    for item_id in ids:assert ID_PATTERN.fullmatch(item_id),f'invalid {item_type} ID: {item_id}'
    return set(ids)
def assert_common_metadata(item):
    assert len(item['summary'])>=20; assert item['lanes'] and len(item['lanes'])==len(set(item['lanes']))
    for lane in item['lanes']:assert ID_PATTERN.fullmatch(lane),f'invalid lane {lane!r} for {item["id"]}'
    assert item['default_network_activity'] is False and item['default_target_mutation'] is False
    assert item['network_activity_mode'] in {'none','control-plane','gated-target'} and item['target_mutation_mode'] in {'none','repository','gated-target'}
    assert repo_path(item['path']).is_file(),f'missing declared item path: {item["path"]}'
    for field in ('authority_paths','validators'):
        values=item[field]; assert values and len(values)==len(set(values)),f'{item["id"]} has invalid {field}'
        for value in values:assert repo_path(value).exists(),f'{item["id"]} references missing {field}: {value}'
def test_manifest_and_schema_define_fail_closed_contract():
    manifest=load_json(MANIFEST); schema=load_json(SCHEMA)
    assert manifest['schema_version']=='sas-agent-capability-manifest/v1'; assert manifest['schema_path']=='schemas/harness/agent-capability-manifest.schema.json'; assert schema['$schema']=='https://json-schema.org/draft/2020-12/schema'; assert schema['$id']==manifest['schema_path']; assert schema['additionalProperties'] is False
    assert {'schema_version','schema_path','authority','posture','capabilities','skills'}<=set(schema['required'])
    posture=manifest['posture']; assert posture=={'progressive_disclosure_required':True,'end_to_end_default_required':True,'unit_tests_sufficient_for_merge':False,'default_network_activity':False,'default_target_mutation':False,'tracked_runtime_evidence_allowed':False}
    for value in manifest['authority'].values():assert repo_path(value).exists(),f'manifest authority path missing: {value}'
def test_capability_entries_are_complete_and_atomic():
    caps=load_json(MANIFEST)['capabilities']; assert assert_unique_ids(caps,'capability')==REQUIRED_CAPABILITY_IDS
    for cap in caps:assert VERSION_PATTERN.fullmatch(cap['version']); assert cap['path']==f'.claude/capabilities/{cap["id"]}.md'; assert_common_metadata(cap)
def test_skill_dependencies_match_markdown_exactly():
    manifest=load_json(MANIFEST); capabilities={i['id']:i for i in manifest['capabilities']}; skills=manifest['skills']; assert assert_unique_ids(skills,'skill')==REQUIRED_SKILL_IDS; referenced=set()
    for skill in skills:
        assert skill['path']==f'.claude/skills/{skill["id"]}/SKILL.md'; assert_common_metadata(skill); ids=skill['capability_ids']; assert ids and len(ids)==len(set(ids)) and set(ids)<=set(capabilities)
        linked={Path(filename).stem for filename in CAPABILITY_LINK.findall(read(repo_path(skill['path'])))}; assert linked==set(ids),f'{skill["id"]} manifest dependencies differ from Markdown'; referenced.update(ids)
    assert referenced==REQUIRED_CAPABILITY_IDS,f'orphan capabilities: {REQUIRED_CAPABILITY_IDS-referenced}'
def test_manifest_is_discoverable_and_wired_into_validation():
    required_path='harness/api/agent-capability-manifest.json'; schema_path='schemas/harness/agent-capability-manifest.schema.json'; test_path='Tests/survey/test_agent_capability_manifest_contracts.py'
    for doc in (CAPABILITY_CATALOG,AI_LAYER_DOC,CODEBASE_MAP):assert required_path in read(doc),f'{doc.relative_to(ROOT)} does not name manifest'
    assert schema_path in read(AI_LAYER_DOC); assert test_path in read(WORKFLOW); assert f'python3 {test_path}' in read(RUNNER)
    op={i['id']:i for i in load_json(HARNESS_API)['operations']}['agent_capability.catalog.read']; assert op['mode']=='local_read' and op['network_activity'] is False and op['target_mutation'] is False; assert required_path in op['inputs'] and schema_path in op['inputs'] and 'No_second_run_context' in op['guardrails']
def test_schema_validation_when_available():
    try:import jsonschema
    except ImportError:return
    jsonschema.validate(load_json(MANIFEST),load_json(SCHEMA))
def main():
    tests=[test_manifest_and_schema_define_fail_closed_contract,test_capability_entries_are_complete_and_atomic,test_skill_dependencies_match_markdown_exactly,test_manifest_is_discoverable_and_wired_into_validation,test_schema_validation_when_available]
    for test in tests:test()
    print(f'PASS: {len(tests)} agent capability manifest contracts')
if __name__=='__main__':main()
