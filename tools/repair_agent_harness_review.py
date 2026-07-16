#!/usr/bin/env python3
"""Apply the bounded PR #224 review repairs, then delete this file in CI."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one replacement, found {count}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


def replace_count(path: str, old: str, new: str, expected: int) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    count = text.count(old)
    if count != expected:
        raise RuntimeError(f"{path}: expected {expected} replacements, found {count}")
    target.write_text(text.replace(old, new), encoding="utf-8")


def update_json(path: str, mutate) -> None:
    target = ROOT / path
    value = json.loads(target.read_text(encoding="utf-8"))
    mutate(value)
    target.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def repair_generator() -> None:
    path = "tools/New-SasSprintCapsule.ps1"
    replace_once(
        path,
        r'''function Assert-SasSafeHandoffText {
    param([Parameter(Mandatory)][string]$Value,[Parameter(Mandatory)][string]$Field)
    if ([string]::IsNullOrWhiteSpace($Value)) { throw "REJECT: $Field must not be empty." }
    if ($Value -match '(?i)(?:[A-Za-z]:[\\/]|/(?:home|Users|mnt/c)/|%USERPROFILE%|\$HOME|BEGIN (?:RSA |OPENSSH )?PRIVATE KEY|(?:password|token|secret)\s*[:=])') {
        throw "REJECT: $Field contains a machine-local path or secret-like value."
    }
}
''',
        r'''function Assert-SasSafeHandoffText {
    param([Parameter(Mandatory)][string]$Value,[Parameter(Mandatory)][string]$Field)
    if ([string]::IsNullOrWhiteSpace($Value)) { throw "REJECT: $Field must not be empty." }
    if ($Value.Length -gt 1000) { throw "REJECT: $Field exceeds the 1000-character capsule limit." }
    if ($Value -match '(?i)(?:[A-Za-z]:[\\/]|(?:^|\s)/(?!/)\S*|%USERPROFILE%|\$HOME|BEGIN (?:RSA |OPENSSH )?PRIVATE KEY|(?:password|token|secret)\s*[:=])') {
        throw "REJECT: $Field contains a machine-local path or secret-like value."
    }
}
''',
    )
    replace_once(
        path,
        "function Test-SasPathOverlap {\n",
        r'''function Assert-SasUniqueList {
    param([object[]]$Values,[Parameter(Mandatory)][string]$Field)
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($value in @($Values)) {
        $text = [string]$value
        if (-not $seen.Add($text)) { throw "REJECT: $Field must contain unique values: $text" }
    }
}

function Get-SasPathComparison {
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        return [System.StringComparison]::OrdinalIgnoreCase
    }
    return [System.StringComparison]::Ordinal
}

function Test-SasPathOverlap {
''',
    )
    replace_once(
        path,
        "    if (-not $pathFull.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'REJECT: generated artifact escaped the repository root.' }",
        "    $comparison = Get-SasPathComparison\n    if (-not $pathFull.StartsWith($prefix,$comparison)) { throw 'REJECT: generated artifact escaped the repository root.' }",
    )
    replace_once(
        path,
        "if (-not ([IO.Path]::GetFullPath($gitRoot)).Equals($script:ResolvedRepoRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'REJECT: RepoRoot does not match the active Git repository root.' }",
        "if (-not ([IO.Path]::GetFullPath($gitRoot)).Equals($script:ResolvedRepoRoot,(Get-SasPathComparison))) { throw 'REJECT: RepoRoot does not match the active Git repository root.' }",
    )
    replace_once(
        path,
        r'''$owned = @($OwnedPaths | ForEach-Object { Assert-SasRepoRelativePath $_ 'OwnedPaths' })
$forbidden = @($ForbiddenScope | ForEach-Object { Assert-SasRepoRelativePath $_ 'ForbiddenScope' })
$expected = @($ExpectedArtifacts | ForEach-Object { Assert-SasRepoRelativePath $_ 'ExpectedArtifacts' })
$workflow = Assert-SasRepoRelativePath $WorkflowSpec 'WorkflowSpec'
foreach ($left in $owned) { foreach ($right in $forbidden) { if (Test-SasPathOverlap $left $right) { throw "REJECT: owned and forbidden scope overlap: $left <-> $right" } } }
if (-not (Test-Path -LiteralPath (Join-Path $script:ResolvedRepoRoot $workflow) -PathType Leaf)) { throw "REJECT: workflow spec does not exist: $workflow" }
foreach ($value in @($Title,$Mission,$ProofCeiling,$NextCommand) + $Completed + $Remaining + $Blockers + $ValidationCommands + $SkippedChecks + $ClaimsNotMade) { Assert-SasSafeHandoffText $value 'handoff text' }
''',
        r'''$owned = @($OwnedPaths | ForEach-Object { Assert-SasRepoRelativePath $_ 'OwnedPaths' })
$forbidden = @($ForbiddenScope | ForEach-Object { Assert-SasRepoRelativePath $_ 'ForbiddenScope' })
$expected = @($ExpectedArtifacts | ForEach-Object { Assert-SasRepoRelativePath $_ 'ExpectedArtifacts' })
$workflow = Assert-SasRepoRelativePath $WorkflowSpec 'WorkflowSpec'
Assert-SasUniqueList -Values $owned -Field 'OwnedPaths'
Assert-SasUniqueList -Values $forbidden -Field 'ForbiddenScope'
Assert-SasUniqueList -Values $expected -Field 'ExpectedArtifacts'
Assert-SasUniqueList -Values @($Dependencies) -Field 'Dependencies'
Assert-SasUniqueList -Values @($AdditionalSkills) -Field 'AdditionalSkills'
$handoffLists = [ordered]@{
    Completed = @($Completed)
    Remaining = @($Remaining)
    Blockers = @($Blockers)
    ValidationCommands = @($ValidationCommands)
    SkippedChecks = @($SkippedChecks)
    ClaimsNotMade = @($ClaimsNotMade)
}
foreach ($entry in $handoffLists.GetEnumerator()) {
    Assert-SasUniqueList -Values $entry.Value -Field $entry.Key
    foreach ($value in @($entry.Value)) { Assert-SasSafeHandoffText -Value ([string]$value) -Field $entry.Key }
}
foreach ($entry in ([ordered]@{ Title=$Title; Mission=$Mission; ProofCeiling=$ProofCeiling; NextCommand=$NextCommand }).GetEnumerator()) {
    Assert-SasSafeHandoffText -Value ([string]$entry.Value) -Field $entry.Key
}
foreach ($left in $owned) { foreach ($right in $forbidden) { if (Test-SasPathOverlap $left $right) { throw "REJECT: owned and forbidden scope overlap: $left <-> $right" } } }
if (-not (Test-Path -LiteralPath (Join-Path $script:ResolvedRepoRoot $workflow) -PathType Leaf)) { throw "REJECT: workflow spec does not exist: $workflow" }
''',
    )


def repair_schema_and_manifests() -> None:
    def mutate_schema(schema: dict) -> None:
        schema["$defs"]["repoPath"]["pattern"] = r"^(?!/)(?!~)(?![A-Za-z]:[\\/])(?!.*\\)(?!.*(?:^|/)\.\.(?:/|$)).+"
        schema["$defs"]["safeText"]["not"]["pattern"] = r"(?i)(?:[A-Za-z]:[\\/]|(?:^|\s)/(?!/)\S*|%USERPROFILE%|\$HOME|BEGIN (?:RSA |OPENSSH )?PRIVATE KEY|(?:password|token|secret)\s*[:=])"

    update_json("schemas/harness/agent-sprint-capsule.schema.json", mutate_schema)

    def mutate_routing(routing: dict) -> None:
        trigger = next(item for item in routing["triggers"] if item["target"] == "agent_sprint_capsule.generate")
        trigger["required_inputs"] = [
            "repository_git_state",
            "bounded_sprint_scope",
            "selected_skills",
            "validation_results",
            "proof_ceiling",
            "next_command",
        ]

    update_json("harness/api/agent-routing-manifest.json", mutate_routing)

    def mutate_api(api: dict) -> None:
        operation = next(item for item in api["operations"] if item["id"] == "agent_sprint_capsule.generate")
        marker = "Mandatory_inputs_collected_from_routing_and_workflow_mapping"
        if marker not in operation["guardrails"]:
            operation["guardrails"].append(marker)

    update_json("harness/api/sas-harness-api.json", mutate_api)


def repair_workflow_and_docs() -> None:
    replace_once(
        "harness/workflows/agent-sprint-capsule.yaml",
        '''inputs:
  - sprint identity
  - repository Git state
  - owned and forbidden scope
  - selected skills
  - expected artifacts
  - validation commands and skipped checks
  - proof ceiling
phases:
''',
        '''inputs:
  - sprint identity
  - repository Git state
  - owned and forbidden scope
  - selected skills
  - workflow spec
  - expected artifacts
  - validation commands and skipped checks
  - proof level and ceiling
  - completed, remaining, and blocked work
  - next command
input_mapping:
  repository_git_state: inspected by the generator from the active Git repository
  bounded_sprint_scope: SprintId, Title, Lane, Mission, OwnedPaths, ForbiddenScope, and Dependencies
  selected_skills: PrimarySkill and AdditionalSkills
  validation_results: ValidationCommands and SkippedChecks
  proof_ceiling: ProofLevel, ProofCeiling, and ClaimsNotMade
  next_command: NextCommand
  workflow_and_artifacts: WorkflowSpec and ExpectedArtifacts
  handoff_state: Completed, Remaining, and Blockers
phases:
''',
    )
    replace_once(
        "AGENTS.md",
        '''3. Use `harness/api/agent-routing-manifest.json` when the request matches an exact deterministic task signal; unknown or conflicting signals fail closed to the repository-sprint skill.
4. Load only the skill rows that match the task.
5. Load the capability dependencies named by those skills.
6. Read deeper product or harness docs only when the selected skill points to them.

Triggers route work only. They never authorize network activity, target mutation, destructive Git operations, or proof claims.
''',
        '''3. Use `harness/api/agent-routing-manifest.json` when the request matches an exact deterministic task signal; unknown or conflicting signals fail closed to the repository-sprint skill.
4. For a `skill` route, load only the selected skill and its declared capability dependencies.
5. For a `harness_operation` route, collect every declared `required_inputs` value and apply the registered workflow input mapping before invoking its repo-owned entrypoint.
6. Read deeper product or harness docs only when the selected skill or operation points to them.

Triggers route work only. They never authorize network activity, target mutation, destructive Git operations, or proof claims. A harness-operation route is not a skill and cannot omit mandatory operation inputs.
''',
    )
    replace_once(
        "docs/AI_HARNESS_ENTRYPOINT.md",
        '''3. Match exact task signals in `harness/api/agent-routing-manifest.json`. Conflicting or unknown primary signals fail closed to `repository-sprint`; additive safety guards may compose.
4. Load the selected `.claude/skills/*/SKILL.md` file and only the capability dependencies it declares.
5. Inspect Git, worktrees, open PRs, generated-output policy, and the current implementation before mutating anything.
''',
        '''3. Match exact task signals in `harness/api/agent-routing-manifest.json`. Conflicting or unknown primary signals fail closed to `repository-sprint`; additive safety guards may compose.
4. For a `skill` target, load the selected `.claude/skills/*/SKILL.md` file and only its declared capability dependencies. For a `harness_operation` target, collect every declared required input and apply the input mapping from its registered workflow before invoking the repo-owned entrypoint.
5. Inspect Git, worktrees, open PRs, generated-output policy, and the current implementation before mutating anything.
''',
    )
    replace_once(
        "docs/AI_HARNESS_ENTRYPOINT.md",
        '''The routing manifest declares deterministic signals, target skill or harness operation, required inputs, outputs, preconditions, guardrails, validators, owner, and proof ceiling.

Routing rules:
''',
        '''The routing manifest declares deterministic signals, target skill or harness operation, required inputs, outputs, preconditions, guardrails, validators, owner, and proof ceiling. Skill routes load skill and capability instructions. Harness-operation routes must collect the operation's complete required-input set and translate it through the workflow's `input_mapping`; they do not silently invent defaults.

Routing rules:
''',
    )
    replace_count(
        ".github/workflows/agent-instruction-contracts.yml",
        "      - 'tools/New-SasSprintCapsule.ps1'\n      - 'tools/validate-ai-layer.ps1'\n",
        "      - 'tools/New-SasSprintCapsule.ps1'\n      - 'tools/validate-ai-layer.ps1'\n      - 'tools/Test-Pester5Suite.ps1'\n      - 'scripts/SasRunContext.psm1'\n",
        2,
    )


def repair_python_contracts() -> None:
    path = "Tests/survey/test_agent_sprint_capsule_contracts.py"
    replace_once(
        path,
        r'''LOCAL_PATTERN = re.compile(r"(?i)(?:[A-Za-z]:[\\/]|/(?:home|Users|mnt/c)/|%USERPROFILE%|\$HOME|BEGIN (?:RSA |OPENSSH )?PRIVATE KEY)")''',
        r'''LOCAL_PATTERN = re.compile(r"(?i)(?:[A-Za-z]:[\\/]|(?:^|\s)/(?!/)\S*|%USERPROFILE%|\$HOME|BEGIN (?:RSA |OPENSSH )?PRIVATE KEY|(?:password|token|secret)\s*[:=])")''',
    )
    replace_once(
        path,
        '''    for marker in ("owned and forbidden scope overlap", "machine-local path or secret-like value", "worktree is dirty", "primary skill is not uniquely routed", "generated artifact escaped the repository root"):
''',
        '''    for marker in ("owned and forbidden scope overlap", "machine-local path or secret-like value", "1000-character capsule limit", "must contain unique values", "worktree is dirty", "primary skill is not uniquely routed", "generated artifact escaped the repository root", "Get-SasPathComparison"):
''',
    )
    replace_once(
        path,
        '''    assert triggers["agent_sprint_capsule.generate"]["target_type"] == "harness_operation"
    assert (ROOT / triggers["agent_sprint_capsule.generate"]["validators"][0]).is_file()
''',
        '''    trigger = triggers["agent_sprint_capsule.generate"]
    assert trigger["target_type"] == "harness_operation"
    assert set(trigger["required_inputs"]) == set(operation["inputs"])
    assert "Mandatory_inputs_collected_from_routing_and_workflow_mapping" in operation["guardrails"]
    assert (ROOT / trigger["validators"][0]).is_file()
''',
    )
    replace_once(
        path,
        '''    assert "register-artifact" in workflow_text and "render-handoff" in workflow_text
    assert "No_machine_local_paths_in_capsule" in workflow_text
''',
        '''    assert "register-artifact" in workflow_text and "render-handoff" in workflow_text
    assert "No_machine_local_paths_in_capsule" in workflow_text
    assert "input_mapping:" in workflow_text and "next_command: NextCommand" in workflow_text
''',
    )
    replace_once(
        path,
        '''    assert "python3 Tests/survey/test_agent_sprint_capsule_contracts.py" in ci
    assert "Tests\\Pester\\SprintCapsule.Tests.ps1" in ci
''',
        '''    assert "python3 Tests/survey/test_agent_sprint_capsule_contracts.py" in ci
    assert "Tests\\Pester\\SprintCapsule.Tests.ps1" in ci
    assert "tools/Test-Pester5Suite.ps1" in ci
    assert "scripts/SasRunContext.psm1" in ci
''',
    )
    replace_once(
        path,
        '''    for bad in (r"C:\\\\Users\\\\operator\\\\repo", "/home/operator/repo", "/mnt/c/Users/operator/repo"):
        candidate = copy.deepcopy(fixture)
        candidate["handoff"]["next_command"] = bad
        try:
            jsonschema.validate(candidate, schema)
        except jsonschema.ValidationError:
            pass
        else:
            raise AssertionError(f"schema accepted machine-local handoff text: {bad}")
''',
        '''    for bad in (r"C:\\\\Users\\\\operator\\\\repo", "/home/operator/repo", "/mnt/c/Users/operator/repo", "/workspace/SysAdminSuite", "/tmp/sas-run", "token=abc", "password: abc", "secret = abc"):
        candidate = copy.deepcopy(fixture)
        candidate["handoff"]["next_command"] = bad
        try:
            jsonschema.validate(candidate, schema)
        except jsonschema.ValidationError:
            pass
        else:
            raise AssertionError(f"schema accepted machine-local or secret-like handoff text: {bad}")
    candidate = copy.deepcopy(fixture)
    candidate["scope"]["owned_paths"][0] = r"safe\\..\\outside"
    try:
        jsonschema.validate(candidate, schema)
    except jsonschema.ValidationError:
        pass
    else:
        raise AssertionError("schema accepted a backslash parent-traversal repository path")
''',
    )

    path = "Tests/survey/test_agent_routing_manifest_contracts.py"
    replace_once(
        path,
        '''    capsule = by_target["agent_sprint_capsule.generate"]
    assert "final handoff compression" in [s.lower() for s in capsule["deterministic_task_signals"]]
    assert capsule["proof_ceiling"] == "schema, fixture, run-context, artifact-registration, and local handoff proof"
''',
        '''    capsule = by_target["agent_sprint_capsule.generate"]
    assert "final handoff compression" in [s.lower() for s in capsule["deterministic_task_signals"]]
    operation = {item["id"]: item for item in load(HARNESS_API)["operations"]}["agent_sprint_capsule.generate"]
    assert set(capsule["required_inputs"]) == set(operation["inputs"])
    assert capsule["proof_ceiling"] == "schema, fixture, run-context, artifact-registration, and local handoff proof"
''',
    )
    replace_once(
        path,
        '''    for marker in ("name:", "mode: local_transform", "network_activity: false", "target_mutation: false", "phases:", "artifacts:", "validation:", "next_actions:"):
''',
        '''    for marker in ("name:", "mode: local_transform", "network_activity: false", "target_mutation: false", "input_mapping:", "next_command: NextCommand", "phases:", "artifacts:", "validation:", "next_actions:"):
''',
    )


def repair_pester_contracts() -> None:
    path = ROOT / "Tests/Pester/SprintCapsule.Tests.ps1"
    text = path.read_text(encoding="utf-8")
    anchor = "    It 'keeps the schema closed and machine-local-path-free' {\n"
    if text.count(anchor) != 1:
        raise RuntimeError("Pester schema anchor not found exactly once")
    insertion = r'''    It 'rejects generic POSIX paths, secret assignments, duplicates, and overlong handoff text before run creation' {
        foreach ($unsafe in @('/workspace/SysAdminSuite','review /tmp/sas-run','token=abc')) {
            {
                & $script:generator -SprintId 'boundary-fixture' -Title 'Boundary fixture' -Lane 'harness' `
                    -Mission 'Reject unsafe handoff input before creating a run.' `
                    -OwnedPaths @('harness/api') -ForbiddenScope @('dashboard') `
                    -PrimarySkill 'repository-sprint' -WorkflowSpec 'harness/workflows/agent-sprint-capsule.yaml' `
                    -ExpectedArtifacts @('harness/api/agent-routing-manifest.json') `
                    -Completed @('No work.') -ValidationCommands @('python3 Tests/survey/test_agent_sprint_capsule_contracts.py') `
                    -ProofLevel 'P1_static_lint' -ProofCeiling 'Static rejection proof only.' `
                    -ClaimsNotMade @('No mutation occurred.') -NextCommand $unsafe `
                    -RepositorySlug 'EndeavorEverlasting/SysAdminSuite'
            } | Should -Throw '*machine-local path or secret-like value*'
        }
        {
            & $script:generator -SprintId 'duplicate-fixture' -Title 'Duplicate fixture' -Lane 'harness' `
                -Mission 'Reject duplicate schema values before creating a run.' `
                -OwnedPaths @('harness/api','harness/api') -ForbiddenScope @('dashboard') `
                -PrimarySkill 'repository-sprint' -WorkflowSpec 'harness/workflows/agent-sprint-capsule.yaml' `
                -ExpectedArtifacts @('harness/api/agent-routing-manifest.json') `
                -Completed @('No work.') -ValidationCommands @('python3 Tests/survey/test_agent_sprint_capsule_contracts.py') `
                -ProofLevel 'P1_static_lint' -ProofCeiling 'Static rejection proof only.' `
                -ClaimsNotMade @('No mutation occurred.') -NextCommand 'git status --short' `
                -RepositorySlug 'EndeavorEverlasting/SysAdminSuite'
        } | Should -Throw '*must contain unique values*'
        {
            & $script:generator -SprintId 'long-fixture' -Title 'Long fixture' -Lane 'harness' `
                -Mission ('x' * 1001) -OwnedPaths @('harness/api') -ForbiddenScope @('dashboard') `
                -PrimarySkill 'repository-sprint' -WorkflowSpec 'harness/workflows/agent-sprint-capsule.yaml' `
                -ExpectedArtifacts @('harness/api/agent-routing-manifest.json') `
                -Completed @('No work.') -ValidationCommands @('python3 Tests/survey/test_agent_sprint_capsule_contracts.py') `
                -ProofLevel 'P1_static_lint' -ProofCeiling 'Static rejection proof only.' `
                -ClaimsNotMade @('No mutation occurred.') -NextCommand 'git status --short' `
                -RepositorySlug 'EndeavorEverlasting/SysAdminSuite'
        } | Should -Throw '*1000-character capsule limit*'
    }

'''
    path.write_text(text.replace(anchor, insertion + anchor, 1), encoding="utf-8")


def main() -> None:
    repair_generator()
    repair_schema_and_manifests()
    repair_workflow_and_docs()
    repair_python_contracts()
    repair_pester_contracts()
    print("PASS: bounded agent harness review repairs applied")


if __name__ == "__main__":
    main()
