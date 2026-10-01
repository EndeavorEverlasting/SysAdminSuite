#Requires -Version 5.1
[CmdletBinding()]
param(
    [AllowEmptyString()]
    [string]$Text = '',

    [switch]$Prompt
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$groups = [ordered]@{
    '2' = 'ABC'
    '3' = 'DEF'
    '4' = 'GHI'
    '5' = 'JKL'
    '6' = 'MNO'
    '7' = 'PQRS'
    '8' = 'TUV'
    '9' = 'WXYZ'
}

$plainText = $Text
if ($Prompt) {
    $secure = Read-Host 'Enter authorized text to plan (input hidden)' -AsSecureString
    $bstr = [IntPtr]::Zero
    try {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        $plainText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}
if ([string]::IsNullOrEmpty($plainText)) {
    throw 'No text was supplied for keypad planning.'
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$outputRoot = Join-Path $repoRoot 'survey\output\hh-cc-reader'
[void](New-Item -ItemType Directory -Force -Path $outputRoot)
$stamp = [DateTimeOffset]::Now.ToString('yyyyMMdd-HHmmss-fff')
$suffix = [Guid]::NewGuid().ToString('N').Substring(0,8)

$alphaCount = 0
$digitCount = 0
$spaceCount = 0
$unsupported = 0

Write-Host 'PAX_FAMILY_KEYPAD_PLAN'
Write-Host 'Rule: press the number key containing the letter, then press ALPHA until the desired character appears.'
Write-Host 'Case-cycle order is prompt/firmware dependent; confirm the visible character instead of assuming a fixed number of ALPHA presses.'
Write-Host 'Observed A80 letter groups: 2=ABC 3=DEF 4=GHI 5=JKL 6=MNO 7=PQRS 8=TUV 9=WXYZ.'
Write-Host 'Special-character mappings are not treated as proven for the A80 Android Settings prompt.'
Write-Host 'Some documented PAX-family terminals expose special characters through a visible on-screen Up-arrow/symbol control followed by ALPHA; use that only if this prompt visibly offers it and verify each character.'
Write-Host ''

for ($i = 0; $i -lt $plainText.Length; $i++) {
    $char = [string]$plainText[$i]
    $upper = $char.ToUpperInvariant()
    $position = $i + 1

    if ($char -match '^[0-9]$') {
        $digitCount++
        Write-Host ("{0,2}. digit -> PRESS {1}" -f $position,$char)
        continue
    }

    $found = $false
    foreach ($key in $groups.Keys) {
        if ($groups[$key].Contains($upper)) {
            $alphaCount++
            Write-Host ("{0,2}. letter -> PRESS {1}, then ALPHA until the intended letter appears" -f $position,$key)
            $found = $true
            break
        }
    }
    if ($found) { continue }

    if ($char -eq ' ') {
        $spaceCount++
        Write-Host ("{0,2}. SPACE -> legacy PAX-family behavior may use 0 + ALPHA; verify visually before relying on it" -f $position)
        continue
    }

    $unsupported++
    $codePoint = [int][char]$char
    Write-Host ("{0,2}. U+{1:X4} -> SPECIAL_CHARACTER_UNPROVEN; if a visible on-screen Up-arrow/symbol control exists, try that documented PAX-family special-character mode + ALPHA and verify the rendered character; otherwise stop rather than invent a key mapping" -f $position,$codePoint) -ForegroundColor Yellow
}

$classification = if ($unsupported -gt 0) {
    'KEYPAD_PLAN_PARTIAL_SPECIAL_CHAR_UNPROVEN'
} else {
    'KEYPAD_PLAN_COMPLETE_FOR_ALNUM'
}

$receipt = [ordered]@{
    schema_version = 'sas-hh-cc-reader-alpha-input-plan/v1'
    timestamp = [DateTimeOffset]::Now.ToString('o')
    input_length = $plainText.Length
    alpha_count = $alphaCount
    digit_count = $digitCount
    space_count = $spaceCount
    unsupported_count = $unsupported
    classification = $classification
    supplied_text_persisted = $false
    mutation = 'NONE'
}
$receiptPath = Join-Path $outputRoot ("hh-cc-reader-alpha-input-plan-{0}-{1}.json" -f $stamp,$suffix)
$receipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $receiptPath -Encoding UTF8

$plainText = $null
$Text = $null

Write-Host ''
Write-Host ("CLASSIFICATION={0}" -f $classification)
Write-Host ("EVIDENCE={0}" -f $receiptPath)
exit 0
