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
$fakeSealedRuntime = Join-Path $tempRoot 'sealed-runtime-C-SASAL'
$fakeScripts = Join-Path $fakeRepo 'scripts'
$fakeHarnessApi = Join-Path $fakeRepo 'harness\api'
$fakeHarnessScripts = Join-Path $fakeRepo 'harness\scripts'
$fakeBin = Join-Path $tempRoot 'bin'
$fakeLocalAppData = Join-Path $tempRoot 'localappdata'
$marker = Join-Path $tempRoot 'launcher-target.txt'
$unsafeMarker = Join-Path $tempRoot 'unsafe-sas-autologon.txt'
$originalPath = $env:PATH
$originalLocalAppData = $env:LOCALAPPDATA

New-Item -ItemType Directory -Path $fakeScripts,$fakeHarnessApi,$fakeHarnessScripts,$fakeBin,$fakeLocalAppData,$fakeSealedRuntime -Force | Out-Null
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

    $sealedBootstrapPath = Join-Path $fakeSealedRuntime 'Bootstrap-SysAdminSuiteAutoLogon.cmd'
    @(
        '@echo off',
        ('>"{0}" echo %~1' -f $marker),
        'exit /b 23'
    ) | Set-Content -LiteralPath $sealedBootstrapPath -Encoding ASCII

    $sasPath = Join-Path $fakeBin 'sas.cmd'
    @(
        '@echo off',
        'if /I "%~1"=="repo" (',
        ('  echo {0}' -f $fakeSealedRuntime),
        '  exit /b 0',
        ')',
        'if /I "%~1"=="autologon" (',
        ('  >"{0}" echo UNSAFE_DIRECT_SAS_AUTOLOGON' -f $unsafeMarker),
        '  exit /b 91',
        ')',
        'exit /b 2'
    ) | Set-Content -LiteralPath $sasPath -Encoding ASCII

    # Case 1: installed sas is used only to resolve the sealed runtime. That runtime intentionally
    # contains no harness registry, but it does contain the crash-safe AutoLogon bootstrap. The route
    # must invoke that bootstrap directly and never trust a potentially stale `sas autologon` dispatcher.
    $env:PATH = "$fakeBin;$originalPath"
    $env:LOCALAPPDATA = $fakeLocalAppData
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $fakeSealedRuntime 'harness\api\operator-execution-route-registry.json'))) 'Fixture sealed runtime unexpectedly contains a harness registry.'
    $first = Invoke-RouteTemplate -Route $route -Target $target
    Assert-True ([int]$first.exit_code -eq 23) "sealed bootstrap route did not preserve exit 23; got $($first.exit_code)."
    Assert-True ($null -ne $first.caught) 'Nonzero sealed bootstrap exit did not surface a parent-shell error.'
    Assert-True (Test-Path -LiteralPath $marker -PathType Leaf) 'installed sas route did not reach the sealed crash-safe bootstrap.'
    Assert-True ((Get-Content -LiteralPath $marker -Raw).Trim() -eq $target) 'sealed bootstrap route changed the decoded target.'
    Assert-True (-not (Test-Path -LiteralPath $unsafeMarker)) 'route incorrectly invoked sas autologon instead of the sealed crash-safe bootstrap.'
    Assert-True ((@($first.output) -join "`n") -notmatch 'Operator execution route registry missing') 'sealed runtime was incorrectly treated as a full repository.'

    # Case 2: installed sas with a resolved runtime but no crash-safe bootstrap fails at that exact
    # boundary; it must not silently fall through to a weaker or stale product dispatcher.
    Remove-Item -LiteralPath $marker -Force
    Remove-Item -LiteralPath $sealedBootstrapPath -Force
    $second = Invoke-RouteTemplate -Route $route -Target $target
    Assert-True ($null -ne $second.caught) 'Missing sealed bootstrap did not surface a route error.'
    Assert-True ((@($second.output) -join "`n") -match 'Crash-safe AutoLogon bootstrap missing from resolved SAS runtime') 'Missing sealed bootstrap was not classified at the sealed-runtime boundary.'
    Assert-True (-not (Test-Path -LiteralPath $unsafeMarker)) 'missing sealed bootstrap fell through to sas autologon.'

    # Case 3: without an installed sas command, the bounded LOCALAPPDATA cache resolves a full
    # repository and uses the tracked helper/crash-safe launcher fallback.
    Remove-Item -LiteralPath $sasPath -Force
    $cacheDirectory = Join-Path $fakeLocalAppData 'SysAdminSuite'
    New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $cacheDirectory 'repo-root.txt') -Value $fakeRepo -Encoding ASCII
    $env:PATH = $originalPath
    $third = Invoke-RouteTemplate -Route $route -Target $target
    Assert-True ([int]$third.exit_code -eq 23) "cached-root fallback did not preserve launcher exit 23; got $($third.exit_code)."
    Assert-True (Test-Path -LiteralPath $marker -PathType Leaf) 'cached-root fallback did not reach the crash-safe launcher.'
    Assert-True ((Get-Content -LiteralPath $marker -Raw).Trim() -eq $target) 'cached-root fallback changed the decoded target passed to the launcher.'

    # Case 4: every registered full-repository fallback dependency must still be proved before helper execution.
    Remove-Item -LiteralPath $marker -Force
    $missingDependency = Join-Path $fakeRepo 'scripts\Invoke-SasAutoLogonFieldDeployment.ps1'
    Remove-Item -LiteralPath $missingDependency -Force
    $fourth = Invoke-RouteTemplate -Route $route -Target $target
    Assert-True ([int]$fourth.exit_code -ne 0 -or $null -ne $fourth.caught) 'Missing registered dependency unexpectedly returned success.'
    Assert-True (-not (Test-Path -LiteralPath $marker)) 'Missing registered dependency still launched the crash-safe front door.'
    Assert-True ((@($fourth.output) -join "`n") -match 'Required operator route file missing') 'Missing dependency did not report the route-proof failure.'

    # Case 5: hostile target text is decoded only as argument data and rejected before either the
    # sealed-bootstrap path or repository helper path can execute it as PowerShell source.
    Set-Content -LiteralPath $missingDependency -Value '# fixture' -Encoding ASCII
    $hostileTarget = "server01'; Write-Output INJECTED; '"
    $fifth = Invoke-RouteTemplate -Route $route -Target $hostileTarget
    Assert-True ([int]$fifth.exit_code -eq 3) "Invalid hostile target did not preserve route exit 3; got $($fifth.exit_code)."
    Assert-True ($null -ne $fifth.caught) 'Invalid hostile target did not surface a parent-shell route error.'
    Assert-True (-not (Test-Path -LiteralPath $marker)) 'Invalid hostile target reached an execution front door.'
    $hostileOutput = @($fifth.output) -join "`n"
    Assert-True ($hostileOutput -match 'SAS_OPERATOR_ROUTE_TARGET_INVALID') 'Invalid target did not emit its stable rejection classification.'
    Assert-True ($hostileOutput -notmatch '(^|\r?\n)INJECTED(\r?\n|$)') 'Hostile target executed as PowerShell source.'

    Write-Host 'PASS: Windows PowerShell installed-sas sealed crash-safe bootstrap, full-repository fallback, target transport, dependency proof, shell preservation, and exit propagation'
    $global:LASTEXITCODE = 0
}
finally {
    $env:PATH = $originalPath
    $env:LOCALAPPDATA = $originalLocalAppData
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
