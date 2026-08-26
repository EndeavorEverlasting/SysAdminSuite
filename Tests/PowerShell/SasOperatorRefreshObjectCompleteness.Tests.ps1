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

function Get-FixtureLooseObjectPath {
    param(
        [Parameter(Mandatory = $true)][string]$Cache,
        [Parameter(Mandatory = $true)][string]$ObjectId
    )
    $path = Join-Path $Cache ('.git\objects\{0}\{1}' -f $ObjectId.Substring(0,2),$ObjectId.Substring(2))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Fixture expected a loose object for deterministic defect injection: $ObjectId -> $path"
    }
    return $path
}

$fixtureRoot = Join-Path $env:TEMP ('sas-refresh-object-floor-' + [guid]::NewGuid().ToString('N'))
$origin = Join-Path $fixtureRoot 'origin'

try {
    New-Item -ItemType Directory -Path $origin -Force | Out-Null
    [void](Invoke-FixtureGit -Root $origin -GitArguments @('init'))
    [void](Invoke-FixtureGit -Root $origin -GitArguments @('symbolic-ref','HEAD','refs/heads/main'))
    [void](Invoke-FixtureGit -Root $origin -GitArguments @('config','user.name','SysAdminSuite CI'))
    [void](Invoke-FixtureGit -Root $origin -GitArguments @('config','user.email','ci@example.invalid'))
    [void](Invoke-FixtureGit -Root $origin -GitArguments @('config','core.autocrlf','false'))
    [void](Invoke-FixtureGit -Root $origin -GitArguments @('config','gc.auto','0'))

    New-Item -ItemType Directory -Path (Join-Path $origin 'nested\deeper') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $origin 'root.txt') -Value 'deterministic root payload' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $origin 'nested\child.txt') -Value 'deterministic nested payload' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $origin 'nested\deeper\leaf.txt') -Value 'deterministic deep payload' -Encoding ASCII
    [void](Invoke-FixtureGit -Root $origin -GitArguments @('add','root.txt','nested/child.txt','nested/deeper/leaf.txt'))
    [void](Invoke-FixtureGit -Root $origin -GitArguments @('commit','-m','fixture commit'))

    $commit = Get-SasRefreshGitScalar -Root $origin -Arguments @('rev-parse','HEAD') -FailureMessage 'Fixture commit could not be resolved.'
    $rootTree = Get-SasRefreshGitScalar -Root $origin -Arguments @('rev-parse',"${commit}^{tree}") -FailureMessage 'Fixture root tree could not be resolved.'
    $nestedTree = Get-SasRefreshGitScalar -Root $origin -Arguments @('rev-parse',"${commit}:nested") -FailureMessage 'Fixture nested tree could not be resolved.'
    $nestedBlob = Get-SasRefreshGitScalar -Root $origin -Arguments @('rev-parse',"${commit}:nested/child.txt") -FailureMessage 'Fixture nested blob could not be resolved.'

    $cases = @(
        [pscustomobject]@{ Name='root-tree'; ObjectId=$rootTree },
        [pscustomobject]@{ Name='nested-tree'; ObjectId=$nestedTree },
        [pscustomobject]@{ Name='nested-blob'; ObjectId=$nestedBlob }
    )

    foreach ($case in $cases) {
        $cache = Join-Path $fixtureRoot ("sync-cache-$($case.Name)")
        $fieldReady = Join-Path $fixtureRoot ("field-ready-$($case.Name)")
        [void](Invoke-FixtureGit -GitArguments @('clone','--no-hardlinks','--no-tags','--branch','main',$origin,$cache))
        [void](Invoke-FixtureGit -Root $cache -GitArguments @('config','gc.auto','0'))

        $cloneHead = Get-SasRefreshGitScalar -Root $cache -Arguments @('rev-parse','HEAD') -FailureMessage "Fixture clone HEAD could not be resolved for $($case.Name)."
        if ($cloneHead -ne $commit) { throw "Fixture clone head mismatch for $($case.Name): expected $commit; got $cloneHead" }
        if (-not (Test-SasRefreshCommitObjectCompleteness -Root $cache -Commit $commit)) {
            throw "Healthy fixture unexpectedly failed object-completeness proof before $($case.Name) defect injection."
        }

        $objectPath = Get-FixtureLooseObjectPath -Cache $cache -ObjectId ([string]$case.ObjectId)
        Remove-Item -LiteralPath $objectPath -Force
        if (Test-SasRefreshCommitObjectCompleteness -Root $cache -Commit $commit) {
            throw "Negative canary failed: deleting $($case.Name) object $($case.ObjectId) was not detected."
        }

        $missing = Invoke-FixtureGit -Root $cache -GitArguments @('cat-file','-e',[string]$case.ObjectId) -AllowFailure
        if ($missing.ExitCode -eq 0) {
            throw "Negative canary failed: deliberately removed $($case.Name) object remained readable."
        }
        Write-Host "EXPECTED NEGATIVE CANARY [$($case.Name)]: reachable object rejected (git exit $($missing.ExitCode))." -ForegroundColor Yellow

        Repair-SasRefreshCommitObjectCompleteness `
            -Root $cache `
            -RefreshBranch 'main' `
            -RemoteTrackingRef 'refs/remotes/origin/main' `
            -ExpectedCommit $commit

        if (-not (Test-SasRefreshCommitObjectCompleteness -Root $cache -Commit $commit)) {
            throw "Repair returned without restoring complete reachable Git objects for $($case.Name)."
        }
        $trackingHead = Get-SasRefreshGitScalar -Root $cache -Arguments @('rev-parse','origin/main') -FailureMessage "Remote tracking ref could not be resolved after $($case.Name) repair."
        if ($trackingHead -ne $commit) {
            throw "Repaired tracking ref mismatch for $($case.Name). Expected $commit; got $trackingHead"
        }
        $restored = Invoke-FixtureGit -Root $cache -GitArguments @('cat-file','-e',[string]$case.ObjectId) -AllowFailure
        if ($restored.ExitCode -ne 0) {
            throw "Repair did not restore removed $($case.Name) object $($case.ObjectId)."
        }

        [void](Invoke-SasRefreshGit `
            -Root $cache `
            -Arguments @('worktree','add','--detach',$fieldReady,$commit) `
            -FailureMessage "Repaired $($case.Name) fixture could not create a field-ready worktree.")
        $fieldHead = Get-SasRefreshGitScalar -Root $fieldReady -Arguments @('rev-parse','HEAD') -FailureMessage "Repaired field-ready HEAD could not be resolved for $($case.Name)."
        if ($fieldHead -ne $commit) {
            throw "Repaired field-ready HEAD mismatch for $($case.Name). Expected $commit; got $fieldHead"
        }
    }

    Write-Host 'PASS: sas refresh repairs missing root trees, nested trees, and reachable blobs while preserving the exact remote-tracking commit before field-ready checkout.' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit 0
