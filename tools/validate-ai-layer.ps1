[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $repoRoot

$skillFiles = @(
  '.claude/skills/repository-sprint/SKILL.md',
  '.claude/skills/language-runtime/SKILL.md',
  '.claude/skills/field-workflow/SKILL.md',
  '.claude/skills/scoped-validation/SKILL.md',
  '.claude/skills/live-data-guard/SKILL.md',
  '.claude/skills/survey-low-noise/SKILL.md',
  '.claude/skills/developer-workstation/SKILL.md'
)

$capabilityFiles = @(
  '.claude/capabilities/README.md',
  '.claude/capabilities/repository-evidence.md',
  '.claude/capabilities/proof-and-checkpointing.md',
  '.claude/capabilities/language-runtime-selection.md',
  '.claude/capabilities/mutation-and-evidence-boundaries.md',
  '.claude/capabilities/field-command-design.md',
  '.claude/capabilities/workstation-inventory.md',
  '.claude/capabilities/workstation-planning.md',
  '.claude/capabilities/workstation-managed-configuration.md',
  '.claude/capabilities/workstation-backend-lifecycle.md',
  '.claude/capabilities/workstation-session-lifecycle.md',
  '.claude/capabilities/workstation-agent-domain-resolution.md',
  '.claude/capabilities/agentswitchboard-invocation.md',
  '.claude/capabilities/workstation-rollback.md'
)

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
  '.github/workflows/agent-instruction-contracts.yml',
  'Tests/survey/test_agent_instruction_factoring_contracts.py',
  'Tests/survey/test_agent_capability_manifest_contracts.py',
  'harness/api/agent-capability-manifest.json',
  'schemas/harness/agent-capability-manifest.schema.json',
    'harness/api/sas-harness-api.json',
    'tools/validate-ai-layer.ps1',
    'schemas/harness/agent-sprint-capsule.schema.json',
    'tools/New-SasSprintCapsule.ps1',
    'Tests/survey/test_agent_sprint_capsule_contracts.py',
    'harness/api/agent-routing-manifest.json',
    'schemas/harness/agent-routing-manifest.schema.json'
) + $skillFiles + $capabilityFiles

$workflowFiles = @(
  '.archon/workflows/sas-survey-change.yaml',
  '.archon/workflows/sas-docs-only.yaml',
  '.archon/workflows/sas-validate-pr.yaml'
)

$harnessDocs = @(
  'AGENTS.md',
  'CLAUDE.md',
  'CODEBASE_MAP.md',
  '.claude/agents/explorer.md',
  'docs/AI_LAYER.md'
) + $skillFiles + $capabilityFiles + $workflowFiles

$requiredSafetyPhrases = @(
  'authorized',
  'read-only',
  'low-noise',
  'scoped',
  'bounded',
  'local evidence',
  'dry-run',
  'validation-first'
)

$requiredIgnoreEntries = @(
  'targets/local/',
  'logs/targets/',
  'survey/input/',
  'survey/output/',
  'survey/artifacts/',
  'logs/nmap/',
  'Mapping/Output/GuiRuns/',
  'runs/',
  '*.xlsx',
  '*.zip'
)

$unsafeTerms = @(
  'ste' + 'alth',
  'eva' + 'sion',
  'hi' + 'ding',
  'by' + 'passing logs',
  'defe' + 'ating monitoring',
  'keeping q' + 'uiet',
  'avoiding det' + 'ection'
)

$forbiddenInstructionPhrases = @(
  'PowerShell is deprecated',
  'PowerShell is dead code',
  'Treat existing `.ps1`, `.psm1`, and `.psd1` files as legacy/reference tooling'
)

# Split command-like sentinels so repository-wide raw-command checks do not
# mistake this validator's search terms for operator guidance.
$rootDetailMarkers = @(
  ('naabu ' + '-list'),
  'Get-NetAdapter',
  'New-NetIPAddress',
  'ip addr',
  'journalctl'
)

$failures = New-Object System.Collections.Generic.List[string]
$passes = 0

function Add-Pass($Message) {
  $script:passes++
  Write-Host "[PASS] $Message"
}

function Add-Fail($Message) {
  $script:failures.Add($Message) | Out-Null
  Write-Host "[FAIL] $Message"
}

Write-Host 'SYSADMIN AI LAYER VALIDATION'

foreach ($file in $requiredFiles) {
  if (Test-Path -LiteralPath $file -PathType Leaf) {
    Add-Pass "required file exists: $file"
  } else {
    Add-Fail "missing required file: $file"
  }
}

foreach ($file in $workflowFiles) {
  if (Test-Path -LiteralPath $file -PathType Leaf) {
    $content = Get-Content -LiteralPath $file -Raw
    if ($content -match '(?m)^name:' -and $content -match '(?m)^phases:' -and $content -match '(?m)^validation:') {
      Add-Pass "workflow has required sections: $file"
    } else {
      Add-Fail "workflow missing name/phases/validation section: $file"
    }
  }
}

if (Test-Path -LiteralPath 'AGENTS.md' -PathType Leaf) {
  $agentLines = @(Get-Content -LiteralPath 'AGENTS.md').Count
  if ($agentLines -le 120) {
    Add-Pass "AGENTS.md stays within compact line budget: $agentLines/120"
  } else {
    Add-Fail "AGENTS.md exceeds compact line budget: $agentLines/120"
  }

  $agentText = Get-Content -LiteralPath 'AGENTS.md' -Raw
  foreach ($skill in $skillFiles) {
    if ($agentText.IndexOf($skill, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
      Add-Pass "AGENTS.md routes to skill: $skill"
    } else {
      Add-Fail "AGENTS.md missing skill route: $skill"
    }
  }

  foreach ($marker in $rootDetailMarkers) {
    if ($agentText.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
      Add-Fail "AGENTS.md contains detail that belongs in a skill/capability: $marker"
    } else {
      Add-Pass "AGENTS.md omits routed implementation detail: $marker"
    }
  }
}

foreach ($skill in $skillFiles) {
  if (-not (Test-Path -LiteralPath $skill -PathType Leaf)) { continue }
  $content = Get-Content -LiteralPath $skill -Raw
  if ($content -match '(?m)^## Capability dependencies\s*$') {
    Add-Pass "skill declares capability dependencies: $skill"
  } else {
    Add-Fail "skill missing capability dependency section: $skill"
  }
  if ($content -match '\.\./\.\./capabilities/[A-Za-z0-9._-]+\.md') {
    Add-Pass "skill links a capability: $skill"
  } else {
    Add-Fail "skill does not link a capability: $skill"
  }
}

$allSkillText = ($skillFiles | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"
foreach ($capability in $capabilityFiles | Where-Object { $_ -ne '.claude/capabilities/README.md' }) {
  $relative = [System.IO.Path]::GetFileName($capability)
  if ($allSkillText.IndexOf($relative, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
    Add-Pass "capability is composed by at least one skill: $capability"
  } else {
    Add-Fail "orphan capability is not referenced by a skill: $capability"
  }
}

$combinedHarnessText = ''
foreach ($file in $harnessDocs) {
  if (Test-Path -LiteralPath $file -PathType Leaf) {
    $combinedHarnessText += "`n" + (Get-Content -LiteralPath $file -Raw)
  }
}

foreach ($phrase in $requiredSafetyPhrases) {
  if ($combinedHarnessText.IndexOf($phrase, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
    Add-Pass "required safety phrase present: $phrase"
  } else {
    Add-Fail "required safety phrase missing: $phrase"
  }
}

foreach ($term in $unsafeTerms) {
  if ($combinedHarnessText.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
    Add-Fail "unsafe wording found in harness docs: $term"
  } else {
    Add-Pass "unsafe wording absent from harness docs: $term"
  }
}

foreach ($phrase in $forbiddenInstructionPhrases) {
  if ($combinedHarnessText.IndexOf($phrase, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
    Add-Fail "contradictory instruction found: $phrase"
  } else {
    Add-Pass "contradictory instruction absent: $phrase"
  }
}

if (Test-Path -LiteralPath '.claudeignore' -PathType Leaf) {
  $ignoreText = Get-Content -LiteralPath '.claudeignore' -Raw
  foreach ($entry in $requiredIgnoreEntries) {
    if ($ignoreText -match [regex]::Escape($entry)) {
      Add-Pass ".claudeignore includes: $entry"
    } else {
      Add-Fail ".claudeignore missing: $entry"
    }
  }
}

if ($failures.Count -gt 0) {
  Write-Host "Result: $passes passed, $($failures.Count) failed"
  exit 1
}

Write-Host "Result: $passes passed, 0 failed"
exit 0
