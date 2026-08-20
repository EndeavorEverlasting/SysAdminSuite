#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$registryPath = Join-Path $repoRoot 'harness\api\operator-execution-route-registry.json'
$helperPath = Join-Path $repoRoot 'harness\scripts\Invoke-SasOperatorExecutionRoute.ps1'
foreach ($required in @($registryPath,$helperPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing operator execution route dependency: $required"
    }
}

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-RouteTemplate {
    param(
        [Parameter(Mandatory = $true)]$Route,
        [Parameter(Mandatory = $true)][string]$Target
    )
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Target))
    $placeholder = [string]$Route.target_placeholder
    $template = [string]$Route.operator_command_template
    Assert-True (-not [string]::IsNullOrWhiteSpace($placeholder)) 'Route target placeholder is empty.'
    Assert-True ($template.Contains($placeholder)) 'Route template does not contain its target placeholder.'
    $command = $template.Replace($placeholder, $encoded)
    Assert-True (-not $command.Contains($Target)) 'Route command contains the raw target instead of encoded argument data.'

    $previousPreference = $ErrorActionPreference
    $output = New-Object System.Collections.Generic.List[string]
    $caught = $null
    try {
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        try {
            foreach ($line in @(Invoke-Expression $command 2>&1)) {
                $output.Add([string]$line)
            }
        }
        catch {
            $caught = $_
            $output.Add([string]$_.Exception.Message)
        }
        $exitCode = [int]$LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    [pscustomobject][ordered]@{
        exit_code = $exitCode
        output = @($output)
        caught = $caught
    }
}

$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$routes = @($registry.routes | Where-Object { [string]$_.command_id -eq 'autologon-remote' })
Assert-True ($routes.Count -eq 1) "Expected one autologon-remote route, found $($routes.Count)."
$route = $routes[0]
Assert-True ([string]$route.target_encoding -eq 'utf8-base64') 'Route target encoding is not utf8-base64.'
$target = 'wpj075opr046.nslijhs.net'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('sas-operator-route-' + [guid]::NewGuid().ToString('N'))
$fakeRepo = Join-Path $tempRoot 'repo with spaces'
$fakeScripts = Join-Path $fakeRepo 'scripts'
$fakeHarnessApi = Join-Path $fakeRepo 'harness\api'
$fakeHarnessScripts = Join-Path $fakeRepo 'harness\scripts'
$fakeBin = Join-Path $tempRoot 'bin'
$fakeLocalAppData = Join-Path $tempRoot 'localappdata'
$marker = Join-Path $tempRoot 'launcher-target.txt'
$originalPath = $env:PATH
$originalLocalAppData = $env:LOCALAPPDATA

New-Item -ItemType Directory -Path $fakeScripts,$fakeHarnessApi,$fakeHarnessScripts,$fakeBin,$fakeLocalAppData -Force | Out-Null
try {
    Copy-Item -LiteralPath $registryPath -Destination (Join-Path $fakeHarnessApi 'operator-execution-route-registry.json') -Force
    Copy-Item -LiteralPath $helperPath -Destination (Join-Path $fakeHarnessScripts 'Invoke-SasOperatorExecutionRoute.ps1') -Force
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

    # Case 1: the installed `sas repo` route resolves a path with spaces, carries the target as an
    # encoded -File argument, reaches the crash-safe launcher, and preserves exit 23 without exiting
    # this parent PowerShell process.
    $env:PATH = "$fakeBin;$originalPath"
    $env:LOCALAPPDATA = $fakeLocalAppData
    $first = Invoke-RouteTemplate -Route $route -Target $target
    Assert-True ([int]$first.exit_code -eq 23) "sas repo route did not preserve launcher exit 23; got $($first.exit_code)."
    Assert-True ($null -ne $first.caught) 'Nonzero launcher exit did not surface a parent-shell error.'
    Assert-True (Test-Path -LiteralPath $marker -PathType Leaf) 'sas repo route did not reach the crash-safe launcher.'
    Assert-True ((Get-Content -LiteralPath $marker -Raw).Trim() -eq $target) 'sas repo route changed the decoded target passed to the launcher.'

    # Case 2: without an installed sas command, the bounded LOCALAPPDATA cache resolves the same root.
    Remove-Item -LiteralPath $marker -Force
    Remove-Item -LiteralPath $sasPath -Force
    $cacheDirectory = Join-Path $fakeLocalAppData 'SysAdminSuite'
    New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $cacheDirectory 'repo-root.txt') -Value $fakeRepo -Encoding ASCII
    $env:PATH = $originalPath
    $second = Invoke-RouteTemplate -Route $route -Target $target
    Assert-True ([int]$second.exit_code -eq 23) "cached-root route did not preserve launcher exit 23; got $($second.exit_code)."
    Assert-True (Test-Path -LiteralPath $marker -PathType Leaf) 'cached-root route did not reach the crash-safe launcher.'
    Assert-True ((Get-Content -LiteralPath $marker -Raw).Trim() -eq $target) 'cached-root route changed the decoded target passed to the launcher.'

    # Case 3: every registered dependency must be proved before helper/front-door execution.
    Remove-Item -LiteralPath $marker -Force
    $missingDependency = Join-Path $fakeRepo 'scripts\Invoke-SasAutoLogonFieldDeployment.ps1'
    Remove-Item -LiteralPath $missingDependency -Force
    $third = Invoke-RouteTemplate -Route $route -Target $target
    Assert-True ([int]$third.exit_code -ne 0 -or $null -ne $third.caught) 'Missing registered dependency unexpectedly returned success.'
    Assert-True (-not (Test-Path -LiteralPath $marker)) 'Missing registered dependency still launched the crash-safe front door.'
    Assert-True ((@($third.output) -join "`n") -match 'Required operator route file missing') 'Missing dependency did not report the route-proof failure.'

    # Case 4: hostile target text is encoded as argument data and rejected by the helper's hostname
    # policy. It must never become executable PowerShell source and must never reach the launcher.
    Set-Content -LiteralPath $missingDependency -Value '# fixture' -Encoding ASCII
    $hostileTarget = "server01'; Write-Output INJECTED; '"
    $fourth = Invoke-RouteTemplate -Route $route -Target $hostileTarget
    Assert-True ([int]$fourth.exit_code -eq 3) "Invalid hostile target did not preserve helper exit 3; got $($fourth.exit_code)."
    Assert-True ($null -ne $fourth.caught) 'Invalid hostile target did not surface a parent-shell route error.'
    Assert-True (-not (Test-Path -LiteralPath $marker)) 'Invalid hostile target reached the crash-safe launcher.'
    $hostileOutput = @($fourth.output) -join "`n"
    Assert-True ($hostileOutput -match 'SAS_OPERATOR_ROUTE_TARGET_INVALID') 'Invalid target did not emit its stable rejection classification.'
    Assert-True ($hostileOutput -notmatch '(^|\r?\n)INJECTED(\r?\n|$)') 'Hostile target executed as PowerShell source.'

    Write-Host 'PASS: Windows PowerShell route resolution, encoded target transport, dependency proof, shell preservation, and exit propagation'
}
finally {
    $env:PATH = $originalPath
    $env:LOCALAPPDATA = $originalLocalAppData
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
