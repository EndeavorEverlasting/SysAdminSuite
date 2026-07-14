#!/usr/bin/env python3
"""Contracts for the factored SysAdminSuite agent instruction architecture."""
from __future__ import annotations
import re
from pathlib import Path
REPO_ROOT=Path(__file__).resolve().parents[2]
AGENTS=REPO_ROOT/'AGENTS.md'; CLAUDE=REPO_ROOT/'CLAUDE.md'; CAPABILITY_ROOT=REPO_ROOT/'.claude'/'capabilities'; WORKFLOW=REPO_ROOT/'.github'/'workflows'/'agent-instruction-contracts.yml'; SKILL_ROOT=REPO_ROOT/'.claude'/'skills'
REQUIRED_SKILLS={'repository-sprint','language-runtime','field-workflow','scoped-validation','end-to-end-validation','live-data-guard','survey-low-noise'}
REQUIRED_CAPABILITIES={'repository-evidence.md','proof-and-checkpointing.md','end-to-end-testing.md','language-runtime-selection.md','mutation-and-evidence-boundaries.md','field-command-design.md'}
FORBIDDEN_ROOT_DETAILS={'naabu -list','get-netadapter','new-netipaddress','ip addr','journalctl'}
FORBIDDEN_CONTRADICTIONS={'powershell is deprecated','powershell is dead code','legacy/reference tooling'}
CAPABILITY_LINK=re.compile(r'\(\.\./\.\./capabilities/([A-Za-z0-9._-]+\.md)\)')
def read(path:Path)->str:
    assert path.is_file(),f'missing required file: {path.relative_to(REPO_ROOT)}'
    return path.read_text(encoding='utf-8')
def test_agents_is_compact_router()->None:
    text=read(AGENTS); lines=text.splitlines()
    assert len(lines)<=120,f'AGENTS.md must remain compact: {len(lines)} lines'
    assert '## Skill router' in text and 'Progressive disclosure is a repository requirement' in text
    assert 'End-to-end proof is the default merge and release target' in text
    lowered=text.lower()
    for detail in FORBIDDEN_ROOT_DETAILS: assert detail not in lowered,f'root instruction contains routed detail: {detail}'
    for skill_name in REQUIRED_SKILLS:
        expected=f'.claude/skills/{skill_name}/SKILL.md'; assert expected in text,f'AGENTS.md does not route to {expected}'
def test_required_skills_compose_capabilities()->None:
    referenced=set()
    for skill_name in REQUIRED_SKILLS:
        path=SKILL_ROOT/skill_name/'SKILL.md'; text=read(path)
        assert '## Capability dependencies' in text,f'{skill_name} has no capability dependency section'
        links=CAPABILITY_LINK.findall(text); assert links,f'{skill_name} does not reference a capability'
        for filename in links:
            assert (CAPABILITY_ROOT/filename).is_file(),f'{skill_name} references missing capability {filename}'; referenced.add(filename)
    assert REQUIRED_CAPABILITIES<=referenced,'required capabilities are orphaned: '+', '.join(sorted(REQUIRED_CAPABILITIES-referenced))
def test_capabilities_are_atomic_and_catalogued()->None:
    catalog=read(CAPABILITY_ROOT/'README.md')
    for filename in REQUIRED_CAPABILITIES:
        text=read(CAPABILITY_ROOT/filename)
        assert '## Contract' in text,f'capability missing contract section: {filename}'
        assert '## Used by' in text,f'capability missing used-by section: {filename}'
        assert filename in catalog,f'capability missing from catalog: {filename}'
        assert len(text.splitlines())<=80,f'capability is too broad and should be factored again: {filename}'
def test_instruction_sources_do_not_reintroduce_language_conflict()->None:
    paths=[AGENTS,CLAUDE]; paths.extend(SKILL_ROOT/name/'SKILL.md' for name in REQUIRED_SKILLS); paths.extend(CAPABILITY_ROOT/name for name in REQUIRED_CAPABILITIES)
    combined='\n'.join(read(path) for path in paths).lower()
    for phrase in FORBIDDEN_CONTRADICTIONS: assert phrase not in combined,f'contradictory PowerShell instruction remains: {phrase}'
    language=read(CAPABILITY_ROOT/'language-runtime-selection.md')
    assert 'Bash-first on Windows' in language and 'PowerShell files are active production-relevant tooling' in language and 'Windows-native operations' in language
def test_claude_front_door_uses_progressive_disclosure()->None:
    text=read(CLAUDE); assert 'Do not preload' in text and '.claude/capabilities/README.md' in text and 'Load only the selected `SKILL.md` files' in text
    assert '.claude/skills/end-to-end-validation/SKILL.md' in text
def test_ci_runs_portable_windows_and_e2e_contracts()->None:
    text=read(WORKFLOW)
    assert 'ubuntu-latest' in text and 'windows-latest' in text
    assert 'python3 Tests/survey/test_agent_instruction_factoring_contracts.py' in text
    assert 'python3 Tests/survey/test_agent_capability_manifest_contracts.py' in text
    assert 'python3 Tests/survey/test_e2e_default_posture_contracts.py' in text
    assert 'tools\\validate-ai-layer.ps1' in text
def main()->None:
    tests=[test_agents_is_compact_router,test_required_skills_compose_capabilities,test_capabilities_are_atomic_and_catalogued,test_instruction_sources_do_not_reintroduce_language_conflict,test_claude_front_door_uses_progressive_disclosure,test_ci_runs_portable_windows_and_e2e_contracts]
    for test in tests:test()
    print(f'PASS: {len(tests)} agent instruction factoring contracts')
if __name__=='__main__':main()
