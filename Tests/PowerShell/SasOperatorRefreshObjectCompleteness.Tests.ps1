#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:GIT_TERMINAL_PROMPT = '0'
$env:GIT_CONFIG_NOSYSTEM = '1'
$env:TZ = 'UTC'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$refreshPath = Join-Path $repoRoot 'scripts\Refresh-SasOperatorCommand.ps1'
if (-not (Test-Path -LiteralPath $refreshPath -PathType Leaf)) {
    throw "Refresh script not found: $refreshPath"
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $refreshPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if (@($parseErrors).Count -gt 0) {
    $parseErrors | Format-List * | Out-Host
    throw 'Refresh script failed Windows PowerShell 5.1 parsing.'
}

foreach ($functionName in @(
    'Invoke-SasRefreshGit',
    'Get-SasRefreshGitScalar',
    'Test-SasRefreshCommitObjectCompleteness',
    'Repair-SasRefreshCommitObjectCompleteness'
)) {
    $functionAst = $ast.Find(
        {
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $functionName
        },
        $true
    )
    if ($null -eq $functionAst) {
        throw "SAS_REFRESH_OBJECT_CANARY_MISSING_PRODUCTION_HELPER: $functionName"
    }
    . ([scriptblock]::Create($functionAst.Extent.Text))
}

$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $gitCommand) {
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
}
if (-not $gitCommand -or [string]::IsNullOrWhiteSpace([string]$gitCommand.Source)) {
    throw 'Git executable was not found for the refresh object-completeness fixture.'
}
$script:SasGitExe = [IO.Path]::GetFullPath([string]$gitCommand.Source)

function Invoke-FixtureGit {
    param(
        [AllowNull()][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$GitArguments,
        [switch]$AllowFailure
    )
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        if ([string]::IsNullOrWhiteSpace($Root)) {
            $output = @(& $script:SasGitExe @GitArguments 2>&1 | ForEach-Object { [string]$_ })
        } else {
            $output = @(& $script:SasGitExe -C $Root @GitArguments 2>&1 | ForEach-Object { [string]$_ })
        }
        $exitCode = [int]$global:LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "Fixture Git failed (exit $exitCode): git $($GitArguments -join ' ')`n$($output -join [Environment]::NewLine)"
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = @($output) }
}

$fixtureRoot = Join-Path $env:TEMP ('sas-refresh-object-floor-' + [guid]::NewGuid().ToString('N'))
$origin = Join-Path $fixtureRoot 'origin'
$cache = Join-Path $fixtureRoot 'sync-cache'
$fieldReady = Join-Path $fixtureRoot 'field-ready'

try {
    New-Item -ItemType Directory -Path $origin -Force | Out-Null
    [void](Invoke-FixtureGit -Root $origin -GitArguments @('init'))
    [void](Invoke-FixtureGit -Root $origin -GitArguments @('symbolic-ref','HEAD','refs/heads/main'))
    [void](Invoke-FixtureGit -Root $origin -GitArguments @('config','user.name','SysAdminSuite CI'))
    [void](Invoke-FixtureGit -Root $origin -GitArguments @('config','user.email','ci@example.invalid'))
    [void](Invoke-FixtureGit -Root $origin -GitArguments @('config','core.autocrlf','false'))
    [void](Invoke-FixtureGit -Root $origin -GitArguments @('config','gc.auto','0'))

    Set-Content -LiteralPath (Join-Path $origin 'payload.txt') -Value 'deterministic refresh object fixture' -Encoding ASCII
    [void](Invoke-FixtureGit -Root $origin -GitArguments @('add','payload.txt'))
    [void](Invoke-FixtureGit -Root $origin -GitArguments @('commit','-m','fixture commit'))

    [void](Invoke-FixtureGit -GitArguments @('clone','--no-hardlinks','--no-tags','--branch','main',$origin,$cache))
    [void](Invoke-FixtureGit -Root $cache -GitArguments @('config','gc.auto','0'))

    $commit = Get-SasRefreshGitScalar -Root $cache -Arguments @('rev-parse','HEAD') -FailureMessage 'Fixture commit could not be resolved.'
    $tree = Get-SasRefreshGitScalar -Root $cache -Arguments @('rev-parse',"${commit}^{tree}") -FailureMessage 'Fixture tree could not be resolved.'
    $treeObjectPath = Join-Path $cache ('.git\objects\{0}\{1}' -f $tree.Substring(0,2),$tree.Substring(2))
    if (-not (Test-Path -LiteralPath $treeObjectPath -PathType Leaf)) {
        throw "Fixture expected a loose root-tree object for deterministic defect injection: $treeObjectPath"
    }

    if (-not (Test-SasRefreshCommitObjectCompleteness -Root $cache -Commit $commit)) {
        throw 'Healthy fixture unexpectedly failed object-completeness proof before defect injection.'
    }

    Remove-Item -LiteralPath $treeObjectPath -Force
    if (Test-SasRefreshCommitObjectCompleteness -Root $cache -Commit $commit) {
        throw 'Negative canary failed: deleting the reachable root tree was not detected.'
    }

    $negative = Invoke-FixtureGit -Root $cache -GitArguments @('ls-tree','-r',$commit) -AllowFailure
    if ($negative.ExitCode -eq 0) {
        throw 'Negative canary failed: Git could still traverse the deliberately incomplete commit tree.'
    }
    Write-Host "EXPECTED NEGATIVE CANARY: incomplete commit tree rejected (git exit $($negative.ExitCode))." -ForegroundColor Yellow

    Repair-SasRefreshCommitObjectCompleteness `
        -Root $cache `
        -RefreshBranch 'main' `
        -RemoteTrackingRef 'refs/remotes/origin/main' `
        -ExpectedCommit $commit

    if (-not (Test-SasRefreshCommitObjectCompleteness -Root $cache -Commit $commit)) {
        throw 'Repair returned without restoring complete reachable Git objects.'
    }

    [void](Invoke-SasRefreshGit `
        -Root $cache `
        -Arguments @('worktree','add','--detach',$fieldReady,$commit) `
        -FailureMessage 'Repaired fixture could not create a field-ready worktree.')
    $fieldHead = Get-SasRefreshGitScalar -Root $fieldReady -Arguments @('rev-parse','HEAD') -FailureMessage 'Repaired field-ready HEAD could not be resolved.'
    if ($fieldHead -ne $commit) {
        throw "Repaired field-ready HEAD mismatch. Expected $commit; got $fieldHead"
    }

    Write-Host 'PASS: sas refresh detects an incomplete fetched commit graph, performs a full refetch repair, and creates the exact field-ready worktree.' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit 0
