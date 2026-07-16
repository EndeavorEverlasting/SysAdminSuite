[CmdletBinding()]
param(
    [string]$JourneyId,
    [switch]$All,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [ValidateSet('all','windows','linux')][string]$PlatformFilter='all'
)
$ErrorActionPreference='Stop'
$python=Get-Command python -ErrorAction SilentlyContinue|Select-Object -First 1
if(-not $python){$python=Get-Command python3 -ErrorAction Stop|Select-Object -First 1}
$arguments=@((Join-Path $PSScriptRoot 'Invoke-SasWorkstationE2E.py'),'--output-root',$OutputRoot,'--platform-filter',$PlatformFilter)
if($All){$arguments+='--all'}elseif($JourneyId){$arguments+=@('--journey-id',$JourneyId)}else{throw 'Specify -JourneyId or -All.'}
& $python.Source @arguments
exit $LASTEXITCODE
