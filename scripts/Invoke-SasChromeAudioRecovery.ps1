# Windows 10/11 interactive-user audio inspection. No elevation, services, browser restart or policy writes.
[CmdletBinding()]
param(
    [ValidateSet('Inspect', 'Repair')][string]$Action = 'Inspect',
    [ValidateRange(1, 50)][int]$ZeroVolumeRecoveryPercent = 25,
    [string]$EvidenceDirectory
)
$ErrorActionPreference = 'Stop'
$schema = 'sas.chrome-audio-recovery/v1'
$receipt = [ordered]@{
    schema_version = $schema
    created_utc = [DateTime]::UtcNow.ToString('o')
    action = $Action
    host_platform = 'windows'
    execution_context = 'interactive-user'
    classification = 'NOT_EVALUATED'
    chrome_running = $false
    before = @()
    repair_attempt = @()
    after = @()
    changed_session_count = 0
    live_playback_confirmed = $false
    user_acceptance_confirmed = $false
    service_restart = $false
    other_apps_modified = $false
    next_action = ''
}
try {
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::UserInteractive) {
        throw 'WINDOWS_INTERACTIVE_USER_SESSION_REQUIRED'
    }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA_REQUIRED'
    }
    $source = Join-Path $PSScriptRoot 'SasChromeAudioCore.cs'
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw 'CORE_AUDIO_SOURCE_MISSING'
    }
    Add-Type -TypeDefinition ([IO.File]::ReadAllText($source)) -Language CSharp -ErrorAction Stop

    $receipt.chrome_running = @(Get-Process -Name chrome -ErrorAction SilentlyContinue).Count -gt 0
    $receipt.before = @([SasChromeAudio.CoreAudio]::Scan($false, $ZeroVolumeRecoveryPercent))
    if ($Action -eq 'Repair') {
        # Only existing ACTIVE chrome.exe audio sessions may be changed.
        $receipt.repair_attempt = @([SasChromeAudio.CoreAudio]::Scan($true, $ZeroVolumeRecoveryPercent))
        $receipt.changed_session_count = @($receipt.repair_attempt | Where-Object { $_.RepairApplied }).Count
    }
    $receipt.after = @([SasChromeAudio.CoreAudio]::Scan($false, $ZeroVolumeRecoveryPercent))
    $active = @($receipt.after | Where-Object { $_.SessionState -eq 'ACTIVE' })
    $mutedOrZero = @($active | Where-Object { $_.Muted -or $_.VolumePercent -eq 0 })
    if (-not $receipt.chrome_running) {
        $receipt.classification = 'CHROME_NOT_RUNNING'
        $receipt.next_action = 'Start Chrome, start audible playback, and inspect again.'
    }
    elseif ($receipt.after.Count -eq 0) {
        $receipt.classification = 'NO_CHROME_SESSION_OBSERVED'
        $receipt.next_action = 'Unmute the website/player, start playback, then inspect again. Absence alone does not prove Windows lost Chrome identity.'
    }
    elseif ($active.Count -eq 0) {
        $receipt.classification = 'CHROME_SESSIONS_INACTIVE'
        $receipt.next_action = 'Start audible playback in Chrome and inspect again.'
    }
    elseif (@($active | Where-Object { $_.IsDefaultDevice }).Count -eq 0) {
        $receipt.classification = 'CHROME_ON_NONDEFAULT_ENDPOINT'
        $receipt.next_action = 'Check Chrome application Output device and the intended default playback endpoint in Windows Volume mixer.'
    }
    elseif ($mutedOrZero.Count -gt 0) {
        $receipt.classification = 'ACTIVE_CHROME_MUTED_OR_ZERO'
        $receipt.next_action = 'Use the explicit Repair action if appropriate, or adjust Chrome in Windows Volume mixer.'
    }
    else {
        $receipt.classification = 'ACTIVE_CHROME_SESSION_HEALTHY'
        $receipt.next_action = 'Verify site/player mute, Chrome site audio permissions, and actual audible playback. Core Audio volume alone is not hearing proof.'
    }
    if ($receipt.changed_session_count -gt 0) {
        $receipt.next_action += ' Chrome session volume/mute was updated; independently verify playback.'
    }
}
catch {
    $receipt.classification = 'DIAGNOSTIC_UNAVAILABLE'
    $receipt.error_type = $_.Exception.GetType().FullName
    $receipt.error = $_.Exception.Message
    $receipt.next_action = 'No automatic system-wide reset. Review local error and Windows audio endpoint availability.'
}
$path = $null
try {
    if (-not $EvidenceDirectory) {
        $EvidenceDirectory = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\Evidence\ChromeAudio'
    }
    if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
        throw 'EVIDENCE_DIRECTORY_UNAVAILABLE'
    }
    New-Item -Path $EvidenceDirectory -ItemType Directory -Force | Out-Null
    $path = Join-Path $EvidenceDirectory ('chrome-audio-' + (Get-Date -Format 'yyyyMMddTHHmmssfff') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
    $receipt.evidence_path = $path
    $json = ConvertTo-Json -InputObject $receipt -Depth 8
    [IO.File]::WriteAllText($path, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Write-Output $json
}
catch {
    $receipt.evidence_error = $_.Exception.Message
    Write-Output (ConvertTo-Json -InputObject $receipt -Depth 8)
    exit 2
}
if ($receipt.classification -eq 'DIAGNOSTIC_UNAVAILABLE') { exit 2 }
exit 0
