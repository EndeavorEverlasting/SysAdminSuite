[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $repoRoot

$requiredFiles = @(
  'CLAUDE.md',
  'CODEBASE_MAP.md',
  '.claudeignore',
  '.claude/skills/scoped-validation/SKILL.md',
  '.claude/skills/live-data-guard/SKILL.md',
  '.claude/skills/survey-low-noise/SKILL.md',
  '.claude/agents/explorer.md',
  '.archon/workflows/sas-survey-change.yaml',
  '.archon/workflows/sas-docs-only.yaml',
  '.archon/workflows/sas-validate-pr.yaml',
  'docs/AI_LAYER.md',
  'tools/validate-ai-layer.ps1'
)

$workflowFiles = @(
  '.archon/workflows/sas-survey-change.yaml',
  '.archon/workflows/sas-docs-only.yaml',
  '.archon/workflows/sas-validate-pr.yaml'
)

$harnessDocs = @(
  'CLAUDE.md',
  'CODEBASE_MAP.md',
  '.claude/skills/scoped-validation/SKILL.md',
  '.claude/skills/live-data-guard/SKILL.md',
  '.claude/skills/survey-low-noise/SKILL.md',
  '.claude/agents/explorer.md',
  '.archon/workflows/sas-survey-change.yaml',
  '.archon/workflows/sas-docs-only.yaml',
  '.archon/workflows/sas-validate-pr.yaml',
  'docs/AI_LAYER.md'
)

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
