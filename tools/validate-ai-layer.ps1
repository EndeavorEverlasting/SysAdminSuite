[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $repoRoot

$failures = New-Object System.Collections.Generic.List[string]
$passes = 0

function Add-Pass([string]$Message) {
    $script:passes++
    Write-Host "[PASS] $Message"
}

function Add-Fail([string]$Message) {
    $script:failures.Add($Message) | Out-Null
    Write-Host "[FAIL] $Message"
}

function Read-SasJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Fail "missing JSON authority: $Path"
        return $null
    }
    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        Add-Fail "invalid JSON authority: $Path - $($_.Exception.Message)"
        return $null
    }
}

function Test-SasRepoRelativePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -match '^[A-Za-z]:[\\/]' -or $Path.StartsWith('/') -or $Path.StartsWith('~')) { return $false }
    return -not (($Path -replace '\\','/') -match '(^|/)\.\.(/|$)')
}

function Resolve-SasDeclaredPath([string]$Path) {
    if (-not (Test-SasRepoRelativePath -Path $Path)) { return $null }
    return Join-Path $repoRoot $Path
}

function Compare-SasSets([object[]]$Left, [object[]]$Right, [string]$Label) {
    $leftSet = @($Left | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $rightSet = @($Right | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $delta = @(Compare-Object -ReferenceObject $leftSet -DifferenceObject $rightSet)
    if ($delta.Count -eq 0) {
        Add-Pass "$Label sets match"
        return $true
    }
    Add-Fail "$Label set drift: $($delta | ForEach-Object { "$($_.SideIndicator)$($_.InputObject)" } | Sort-Object | Out-String)"
    return $false
}

Write-Host 'SYSADMIN AI LAYER VALIDATION'

$manifestPath = 'harness/api/agent-capability-manifest.json'
$routingPath = 'harness/api/agent-routing-manifest.json'
$harnessApiPath = 'harness/api/sas-harness-api.json'
$manifest = Read-SasJson -Path $manifestPath
$routing = Read-SasJson -Path $routingPath
$harnessApi = Read-SasJson -Path $harnessApiPath

$requiredFiles = @(
    'AGENTS.md',
    'CLAUDE.md',
    'CODEBASE_MAP.md',
    '.claudeignore',
    '.claude/agents/explorer.md',
    '.archon/workflows/sas-survey-change.yaml',
    '.archon/workflows/sas-docs-only.yaml',
    '.archon/workflows/sas-validate-pr.yaml',
    'docs/AI_LAYER.md',
    'docs/AI_HARNESS_ENTRYPOINT.md',
    'docs/HARNESS_DISCIPLINE.md',
    'docs/END_TO_END_TESTING_POSTURE.md',
    'docs/ENGLISH_LOG_ARTIFACT_CONTRACT.md',
    '.github/workflows/agent-instruction-contracts.yml',
    'Tests/survey/test_agent_instruction_factoring_contracts.py',
    'Tests/survey/test_agent_capability_manifest_contracts.py',
    'Tests/survey/test_agent_routing_manifest_contracts.py',
    'Tests/survey/test_agent_sprint_capsule_contracts.py',
    'Tests/Pester/SprintCapsule.Tests.ps1',
    'Tests/Fixtures/capsules/agent-sprint-capsule.v2.sample.json',
    $manifestPath,
    'schemas/harness/agent-capability-manifest.schema.json',
    $routingPath,
    'schemas/harness/agent-routing-manifest.schema.json',
    'schemas/harness/agent-sprint-capsule.schema.json',
    $harnessApiPath,
    'harness/workflows/agent-sprint-capsule.yaml',
    'scripts/SasRunContext.psm1',
    'scripts/Render-SasEnglishReport.ps1',
    'scripts/install-local-harness-hooks.sh',
    'tools/New-SasSprintCapsule.ps1',
    'tools/validate-ai-layer.ps1'
)

foreach ($file in $requiredFiles) {
    if (Test-Path -LiteralPath $file -PathType Leaf) { Add-Pass "required file exists: $file" }
    else { Add-Fail "missing required file: $file" }
}

$reviewableJsonFiles = @(
    $manifestPath,
    $routingPath,
    $harnessApiPath,
    'schemas/harness/agent-capability-manifest.schema.json',
    'schemas/harness/agent-routing-manifest.schema.json',
    'schemas/harness/agent-sprint-capsule.schema.json',
    'Tests/Fixtures/capsules/agent-sprint-capsule.v2.sample.json'
)
foreach ($file in $reviewableJsonFiles) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
    if (@(Get-Content -LiteralPath $file).Count -gt 1) {
        Add-Pass "JSON authority is human-reviewable: $file"
    } else {
        Add-Fail "JSON authority must not be minified: $file"
    }
}

$workflowFiles = @(
    '.archon/workflows/sas-survey-change.yaml',
    '.archon/workflows/sas-docs-only.yaml',
    '.archon/workflows/sas-validate-pr.yaml',
    'harness/workflows/agent-sprint-capsule.yaml'
)
foreach ($file in $workflowFiles) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
    $content = Get-Content -LiteralPath $file -Raw
    if ($content -match '(?m)^name:' -and $content -match '(?m)^(phases|nodes):' -and $content -match '(?m)^validation:') {
        Add-Pass "workflow has name, phases/nodes, and validation: $file"
    } else {
        Add-Fail "workflow missing name, phases/nodes, or validation: $file"
    }
}

if ($manifest) {
    if ($manifest.schema_version -eq 'sas-agent-capability-manifest/v1') { Add-Pass 'capability manifest schema version is current' }
    else { Add-Fail "unsupported capability manifest version: $($manifest.schema_version)" }

    $skills = @($manifest.skills)
    $capabilities = @($manifest.capabilities)
    $skillIds = @($skills | ForEach-Object { [string]$_.id })
    $capabilityIds = @($capabilities | ForEach-Object { [string]$_.id })

    if ($skillIds.Count -eq @($skillIds | Sort-Object -Unique).Count) { Add-Pass 'skill IDs are unique' }
    else { Add-Fail 'duplicate skill IDs in capability manifest' }
    if ($capabilityIds.Count -eq @($capabilityIds | Sort-Object -Unique).Count) { Add-Pass 'capability IDs are unique' }
    else { Add-Fail 'duplicate capability IDs in capability manifest' }

    $diskSkillIds = @(
        Get-ChildItem -LiteralPath '.claude/skills' -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } |
            ForEach-Object { $_.Name }
    )
    $diskCapabilityIds = @(
        Get-ChildItem -LiteralPath '.claude/capabilities' -Filter '*.md' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'README.md' } |
            ForEach-Object { $_.BaseName }
    )
    [void](Compare-SasSets -Left $skillIds -Right $diskSkillIds -Label 'manifest/disk skill')
    [void](Compare-SasSets -Left $capabilityIds -Right $diskCapabilityIds -Label 'manifest/disk capability')

    $agentsText = if (Test-Path -LiteralPath 'AGENTS.md') { Get-Content -LiteralPath 'AGENTS.md' -Raw } else { '' }
    $claudeText = if (Test-Path -LiteralPath 'CLAUDE.md') { Get-Content -LiteralPath 'CLAUDE.md' -Raw } else { '' }
    $agentLines = @($agentsText -split "`r?`n").Count
    if ($agentLines -le 120) { Add-Pass "AGENTS.md stays within compact line budget: $agentLines/120" }
    else { Add-Fail "AGENTS.md exceeds compact line budget: $agentLines/120" }

    $referencedCapabilities = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($skill in $skills) {
        $path = [string]$skill.path
        $resolved = Resolve-SasDeclaredPath -Path $path
        if (-not $resolved -or -not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            Add-Fail "skill path is missing or unsafe: $path"
            continue
        }
        if ($agentsText.IndexOf($path, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and
            $claudeText.IndexOf($path, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Add-Pass "human routers name skill: $($skill.id)"
        } else {
            Add-Fail "human router drift for skill: $($skill.id)"
        }

        $content = Get-Content -LiteralPath $resolved -Raw
        if ($content -match '(?m)^## Capability dependencies\s*$') { Add-Pass "skill declares capability dependencies: $($skill.id)" }
        else { Add-Fail "skill missing capability dependency section: $($skill.id)" }
        $linked = @([regex]::Matches($content, '\(\.\./\.\./capabilities/([A-Za-z0-9._-]+)\.md\)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $declared = @($skill.capability_ids | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        if (@(Compare-Object -ReferenceObject $declared -DifferenceObject $linked).Count -eq 0) {
            Add-Pass "skill capability dependencies match manifest: $($skill.id)"
            foreach ($id in $declared) { [void]$referencedCapabilities.Add($id) }
        } else {
            Add-Fail "skill capability dependency drift: $($skill.id)"
        }

        foreach ($field in @('authority_paths','validators')) {
            foreach ($value in @($skill.$field)) {
                $declaredPath = [string]$value
                $full = Resolve-SasDeclaredPath -Path $declaredPath
                if ($full -and (Test-Path -LiteralPath $full)) { Add-Pass "skill $field exists: $($skill.id) -> $declaredPath" }
                else { Add-Fail "skill $field missing or unsafe: $($skill.id) -> $declaredPath" }
            }
        }
    }

    foreach ($capability in $capabilities) {
        $path = [string]$capability.path
        $resolved = Resolve-SasDeclaredPath -Path $path
        if (-not $resolved -or -not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            Add-Fail "capability path is missing or unsafe: $path"
            continue
        }
        $content = Get-Content -LiteralPath $resolved -Raw
        if ($content -match '(?m)^## Contract\s*$' -and $content -match '(?m)^## Used by\s*$') {
            Add-Pass "capability is atomic and declares ownership: $($capability.id)"
        } else {
            Add-Fail "capability missing Contract or Used by section: $($capability.id)"
        }
        if ($referencedCapabilities.Contains([string]$capability.id)) { Add-Pass "capability is composed by a skill: $($capability.id)" }
        else { Add-Fail "orphan capability is not composed by a skill: $($capability.id)" }
        foreach ($field in @('authority_paths','validators')) {
            foreach ($value in @($capability.$field)) {
                $declaredPath = [string]$value
                $full = Resolve-SasDeclaredPath -Path $declaredPath
                if ($full -and (Test-Path -LiteralPath $full)) { Add-Pass "capability $field exists: $($capability.id) -> $declaredPath" }
                else { Add-Fail "capability $field missing or unsafe: $($capability.id) -> $declaredPath" }
            }
        }
    }
}

if ($routing -and $manifest -and $harnessApi) {
    if ($routing.schema_version -eq 'sas-agent-routing-manifest/v1') { Add-Pass 'routing manifest schema version is current' }
    else { Add-Fail "unsupported routing manifest version: $($routing.schema_version)" }

    $skillsById = @{}
    foreach ($skill in @($manifest.skills)) { $skillsById[[string]$skill.id] = $skill }
    $capsById = @{}
    foreach ($capability in @($manifest.capabilities)) { $capsById[[string]$capability.id] = $capability }
    $opsById = @{}
    foreach ($operation in @($harnessApi.operations)) { $opsById[[string]$operation.id] = $operation }

    $signals = @{}
    $routedSkills = New-Object System.Collections.Generic.List[string]
    foreach ($trigger in @($routing.triggers)) {
        $targetExists = switch ([string]$trigger.target_type) {
            'skill' { $skillsById.ContainsKey([string]$trigger.target) }
            'capability' { $capsById.ContainsKey([string]$trigger.target) }
            'harness_operation' { $opsById.ContainsKey([string]$trigger.target) }
            default { $false }
        }
        if ($targetExists) { Add-Pass "trigger target exists: $($trigger.id) -> $($trigger.target)" }
        else { Add-Fail "trigger target missing: $($trigger.id) -> $($trigger.target)" }
        if ($trigger.target_type -eq 'skill') { $routedSkills.Add([string]$trigger.target) }

        foreach ($signal in @($trigger.deterministic_task_signals)) {
            $normalized = ([string]$signal).Trim().ToLowerInvariant()
            if ($signals.ContainsKey($normalized)) { Add-Fail "duplicate deterministic signal: $signal" }
            else { $signals[$normalized] = [string]$trigger.id }
        }
        foreach ($validator in @($trigger.validators)) {
            $full = Resolve-SasDeclaredPath -Path ([string]$validator)
            if ($full -and (Test-Path -LiteralPath $full -PathType Leaf)) { Add-Pass "trigger validator exists: $($trigger.id) -> $validator" }
            else { Add-Fail "trigger validator missing or unsafe: $($trigger.id) -> $validator" }
        }
    }
    [void](Compare-SasSets -Left @($skillsById.Keys) -Right @($routedSkills) -Label 'manifest/routed skill')

    $rules = $routing.ambiguity_rules
    if ($rules.explicit_user_lane_wins -and $rules.safety_guard_triggers_compose_additively -and $rules.no_trigger_authorizes_mutation -and
        $rules.equal_priority_conflict_resolution -eq 'fail_closed_to_repository_sprint' -and $rules.unknown_signal_fallback -eq 'repository-sprint') {
        Add-Pass 'routing ambiguity rules fail closed'
    } else {
        Add-Fail 'routing ambiguity rules do not fail closed'
    }

    foreach ($operationId in @('agent_capability.catalog.read','agent_routing.catalog.read','agent_sprint_capsule.generate')) {
        if ($opsById.ContainsKey($operationId)) {
            $operation = $opsById[$operationId]
            if (-not $operation.network_activity -and -not $operation.target_mutation) { Add-Pass "agent harness operation is local and non-mutating: $operationId" }
            else { Add-Fail "agent harness operation exceeds local non-mutating boundary: $operationId" }
        } else {
            Add-Fail "missing agent harness operation: $operationId"
        }
    }
}

$harnessDocs = @('AGENTS.md','CLAUDE.md','CODEBASE_MAP.md','docs/AI_LAYER.md','docs/AI_HARNESS_ENTRYPOINT.md')
if ($manifest) {
    $harnessDocs += @($manifest.skills | ForEach-Object { [string]$_.path })
    $harnessDocs += @($manifest.capabilities | ForEach-Object { [string]$_.path })
}
$harnessDocs += $workflowFiles
$combinedHarnessText = ''
foreach ($file in @($harnessDocs | Sort-Object -Unique)) {
    if (Test-Path -LiteralPath $file -PathType Leaf) { $combinedHarnessText += "`n" + (Get-Content -LiteralPath $file -Raw) }
}

$requiredSafetyPhrases = @('authorized','read-only','low-noise','scoped','bounded','local evidence','dry-run','validation-first')
foreach ($phrase in $requiredSafetyPhrases) {
    if ($combinedHarnessText.IndexOf($phrase, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { Add-Pass "required safety phrase present: $phrase" }
    else { Add-Fail "required safety phrase missing: $phrase" }
}

$unsafeTerms = @('ste' + 'alth','eva' + 'sion','hi' + 'ding','by' + 'passing logs','defe' + 'ating monitoring','keeping q' + 'uiet','avoiding det' + 'ection')
foreach ($term in $unsafeTerms) {
    if ($combinedHarnessText.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { Add-Fail "unsafe wording found in harness docs: $term" }
    else { Add-Pass "unsafe wording absent from harness docs: $term" }
}

$forbiddenInstructionPhrases = @('PowerShell is deprecated','PowerShell is dead code','Treat existing `.ps1`, `.psm1`, and `.psd1` files as legacy/reference tooling')
foreach ($phrase in $forbiddenInstructionPhrases) {
    if ($combinedHarnessText.IndexOf($phrase, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { Add-Fail "contradictory instruction found: $phrase" }
    else { Add-Pass "contradictory instruction absent: $phrase" }
}

$requiredIgnoreEntries = @('targets/local/','logs/targets/','survey/input/','survey/output/','survey/artifacts/','logs/nmap/','Mapping/Output/GuiRuns/','runs/','*.xlsx','*.zip')
if (Test-Path -LiteralPath '.claudeignore' -PathType Leaf) {
    $ignoreText = Get-Content -LiteralPath '.claudeignore' -Raw
    foreach ($entry in $requiredIgnoreEntries) {
        if ($ignoreText -match [regex]::Escape($entry)) { Add-Pass ".claudeignore includes: $entry" }
        else { Add-Fail ".claudeignore missing: $entry" }
    }
}

if ($failures.Count -gt 0) {
    Write-Host "Result: $passes passed, $($failures.Count) failed"
    exit 1
}

Write-Host "Result: $passes passed, 0 failed"
exit 0
