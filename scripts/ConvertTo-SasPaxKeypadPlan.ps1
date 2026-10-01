#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [AllowEmptyString()]
    [string]$Text
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$groups = [ordered]@{
    '1' = 'QZ'
    '2' = 'ABC'
    '3' = 'DEF'
    '4' = 'GHI'
    '5' = 'JKL'
    '6' = 'MNO'
    '7' = 'PRS'
    '8' = 'TUV'
    '9' = 'WXY'
}

Write-Host 'PAX_FAMILY_KEYPAD_PLAN'
Write-Host 'Rule: press the number key containing the letter, then press ALPHA until the desired character appears.'
Write-Host 'Case-cycle order is prompt/firmware dependent; confirm the visible character instead of assuming a fixed number of ALPHA presses.'
Write-Host 'Special-character mappings are not treated as proven for the A80 Android Settings prompt.'
Write-Host ''

$unsupported = 0
for ($i = 0; $i -lt $Text.Length; $i++) {
    $char = [string]$Text[$i]
    $upper = $char.ToUpperInvariant()
    $position = $i + 1

    if ($char -match '^[0-9]$') {
        Write-Host ("{0,2}. '{1}' -> PRESS {1}" -f $position,$char)
        continue
    }

    $found = $false
    foreach ($key in $groups.Keys) {
        if ($groups[$key].Contains($upper)) {
            Write-Host ("{0,2}. '{1}' -> PRESS {2}, then ALPHA until '{1}' appears" -f $position,$char,$key)
            $found = $true
            break
        }
    }
    if ($found) { continue }

    if ($char -eq ' ') {
        Write-Host ("{0,2}. SPACE -> PAX-family legacy mapping may use 0 + ALPHA; VERIFY VISUALLY before relying on it" -f $position)
        continue
    }

    $unsupported++
    $codePoint = [int][char]$char
    Write-Host ("{0,2}. U+{1:X4} -> SPECIAL_CHARACTER_UNPROVEN; prefer an on-screen symbol keyboard if the prompt exposes one; do not invent a physical-key mapping" -f $position,$codePoint) -ForegroundColor Yellow
}

Write-Host ''
if ($unsupported -gt 0) {
    Write-Host ("CLASSIFICATION=KEYPAD_PLAN_PARTIAL_SPECIAL_CHAR_UNPROVEN; unresolved={0}" -f $unsupported) -ForegroundColor Yellow
    exit 3
}
Write-Host 'CLASSIFICATION=KEYPAD_PLAN_COMPLETE_FOR_ALNUM'
exit 0
