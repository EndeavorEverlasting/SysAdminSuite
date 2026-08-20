#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$registryPath = Join-Path $repoRoot 'harness\api\operator-execution-route-registry.json'
if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
    throw "Missing operator execution route registry: $registryPath"
}

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-RouteTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$Template,
        [Parameter(Mandatory = $true)][string]$Target
    )
    $command = $Template.Replace('HOST', $Target)
    $previousPreference = $ErrorActionPreference
    $output = @()
    try {
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        $output = @(Invoke-Expression $command 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = [int]$LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    [pscustomobject][ordered]@{
        exit_code = $exitCode
        output = @($output)
    }
}

$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$routes = @($registry.routes | Where-Object { [string]$_.command_id -eq 'autologon-remote' })
Assert-True ($routes.Count -eq 1) "Expected one autologon-remote route, found $($routes.Count)."
$route = $routes[0]
$template = [string]$route.operator_command_template
$target = 'wpj075opr046.nslijhs.net'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('sas-operator-route-' + [guid]::NewGuid().ToString('N'))
$fakeRepo = Join-Path $tempRoot 'repo with spaces'
$fakeScripts = Join-Path $fakeRepo 'scripts'
$fakeBin = Join-Path $tempRoot 'bin'
$fakeLocalAppData = Join-Path $tempRoot 'localappdata'
$marker = Join-Path $tempRoot 'launcher-target.txt'
$originalPath = $env:PATH
$originalLocalAppData = $env:LOCALAPPDATA

New-Item -ItemType Directory -Path $fakeScripts,$fakeBin,$fakeLocalAppData -Force | Out-Null
try {
    foreach ($relative in @(
        'scripts\Invoke-SasAutoLogonCrashSafeFieldRun.ps1',
        'scripts\Invoke-SasAutoLogonFieldDeployment.ps1'
    )) {
        Set-Content -LiteralPath (Join-Path $fakeRepo $relative) -Value '# fixture' -Encoding ASCII
    }

    $launcherPath = Join-Path $fakeRepo 'Run-AutoLogonCrashSafe.cmd'
    @(
        '@echo off',
        ('>"{0}" echo %~1' -f $marker),
        'exit /b 23'
    ) | Set-Content -LiteralPath $launcherPath -Encoding ASCII

    $sasPath = Join-Path $fakeBin 'sas.cmd'
    @(
        '@echo off',
        'if /I "%~1"=="repo" (',
        ('  echo {0}' -f $fakeRepo),
        '  exit /b 0',
        ')',
        'exit /b 2'
    ) | Set-Content -LiteralPath $sasPath -Encoding ASCII

    # Case 1: parent Windows PowerShell must not expand child variables. The installed `sas repo`
    # route resolves a path with spaces, verifies all dependencies, launches, and propagates 23.
    $env:PATH = "$fakeBin;$originalPath"
    $env:LOCALAPPDATA = $fakeLocalAppData
    $first = Invoke-RouteTemplate -Template $template -Target $target
    Assert-True ([int]$first.exit_code -eq 23) "sas repo route did not propagate launcher exit 23; got $($first.exit_code)."
    Assert-True (Test-Path -LiteralPath $marker -PathType Leaf) 'sas repo route did not reach the crash-safe launcher.'
    Assert-True ((Get-Content -LiteralPath $marker -Raw).Trim() -eq $target) 'sas repo route changed the target passed to the launcher.'

    # Case 2: without an installed sas command, the bounded LOCALAPPDATA cache resolves the same root.
    Remove-Item -LiteralPath $marker -Force
    Remove-Item -LiteralPath $sasPath -Force
    $cacheDirectory = Join-Path $fakeLocalAppData 'SysAdminSuite'
    New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $cacheDirectory 'repo-root.txt') -Value $fakeRepo -Encoding ASCII
    $env:PATH = $originalPath
    $second = Invoke-RouteTemplate -Template $template -Target $target
    Assert-True ([int]$second.exit_code -eq 23) "cached-root route did not propagate launcher exit 23; got $($second.exit_code)."
    Assert-True (Test-Path -LiteralPath $marker -PathType Leaf) 'cached-root route did not reach the crash-safe launcher.'
    Assert-True ((Get-Content -LiteralPath $marker -Raw).Trim() -eq $target) 'cached-root route changed the target passed to the launcher.'

    # Case 3: every registered dependency must be proved before launch. Remove one and verify the
    # launcher is never called even though the front-door CMD itself still exists.
    Remove-Item -LiteralPath $marker -Force
    Remove-Item -LiteralPath (Join-Path $fakeRepo 'scripts\Invoke-SasAutoLogonFieldDeployment.ps1') -Force
    $third = Invoke-RouteTemplate -Template $template -Target $target
    Assert-True ([int]$third.exit_code -ne 0) 'Missing registered dependency unexpectedly returned success.'
    Assert-True (-not (Test-Path -LiteralPath $marker)) 'Missing registered dependency still launched the crash-safe front door.'
    Assert-True ((@($third.output) -join "`n") -match 'Required operator route file missing') 'Missing dependency did not report the route-proof failure.'

    Write-Host 'PASS: Windows PowerShell operator execution route, cache fallback, dependency proof, and exit propagation'
}
finally {
    $env:PATH = $originalPath
    $env:LOCALAPPDATA = $originalLocalAppData
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
