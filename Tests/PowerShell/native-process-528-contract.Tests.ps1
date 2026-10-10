#Requires -Version 5.1
[CmdletBinding()]
param([string]$ModulePath)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if(-not $ModulePath){$ModulePath=Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'scripts/SasBoundedNative.psm1'}
Import-Module $ModulePath -Force
if(-not (Get-Command Invoke-SasNativeProcess -ErrorAction SilentlyContinue)){throw 'BASELINE_MISSING_NATIVE_PROCESS_SEAM'}
$python=(Get-Command python.exe -ErrorAction Stop).Source
$temp=Join-Path $env:TEMP ('sas native 528 '+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temp | Out-Null
$child=Join-Path $temp 'child fixture.py'
$descendants=@()
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Check-Shape($Run){
 foreach($name in @('process_id','exit_code','timed_out','timeout_seconds','output','error','started_utc','completed_utc','child_tree_termination_attempted','child_tree_terminated','output_complete')){Assert ($null -ne $Run.PSObject.Properties[$name]) ('MISSING_RESULT_FIELD_'+$name)}
 Assert ($Run.output -is [string] -and $Run.error -is [string]) 'OUTPUT_NOT_PLAIN_STRINGS'
}
@'
import os,sys,json,time,subprocess
mode=sys.argv[1]
if mode=='silent': sys.exit(0)
if mode=='stderr': sys.stderr.write('stderr-success');sys.exit(0)
if mode=='nonzero': print('stdout-failure');sys.stderr.write('stderr-failure');sys.exit(7)
if mode=='argv': print(json.dumps(sys.argv[2:],ensure_ascii=True))
if mode=='env': print(json.dumps({'value':os.environ.get('SAS_NATIVE_528_PROBE'),'removed':os.environ.get('SAS_NATIVE_528_REMOVE')}))
if mode in ('timeout','drain'):
    p=subprocess.Popen([sys.executable,'-c','import time;time.sleep(30)'])
    with open(sys.argv[2],'w') as f: f.write(str(p.pid))
    print('parent-started',flush=True)
    if mode=='timeout': time.sleep(30)
'@ | Set-Content $child -Encoding UTF8
try{
 $global:LASTEXITCODE=73
 $silent=Invoke-SasNativeProcess -FilePath $python -Arguments @($child,'silent') -TimeoutSeconds 5
 Check-Shape $silent
 Assert ($silent.exit_code -eq 0 -and -not $silent.timed_out -and $silent.output -eq '' -and $silent.error -eq '' -and $silent.output_complete) 'SILENT_SUCCESS_LOST'
 Assert ($global:LASTEXITCODE -eq 73) 'CALLER_LASTEXITCODE_MUTATED'
 $stderr=Invoke-SasNativeProcess -FilePath $python -Arguments @($child,'stderr') -TimeoutSeconds 5
 Check-Shape $stderr
 Assert ($stderr.exit_code -eq 0 -and $stderr.output -eq '' -and $stderr.error -eq 'stderr-success') 'STDERR_ZERO_EXIT_NOT_PRESERVED'
 $bad=Invoke-SasNativeProcess -FilePath $python -Arguments @($child,'nonzero') -TimeoutSeconds 5
 Assert ($bad.exit_code -eq 7 -and $bad.output.Trim() -eq 'stdout-failure' -and $bad.error -eq 'stderr-failure') 'NONZERO_DATA_LOST'
 $unicode=[string][char]0x03bb+[string][char]0x96ea
 $expected=@('','with spaces',$unicode,'embedded"quote','C:\trailing slash\','backslash\"quote','plain')
 $argv=Invoke-SasNativeProcess -FilePath $python -Arguments (@($child,'argv')+$expected) -TimeoutSeconds 5
 Assert ($argv.exit_code -eq 0 -and $argv.error -eq '') 'ARGV_CHILD_FAILED'
 $actual=ConvertFrom-Json -InputObject $argv.output
 Assert ($actual.Count -eq $expected.Count) ('ARGV_COUNT_CHANGED actual='+$argv.output+' count='+$actual.Count+' expected='+$expected.Count)
 for($i=0;$i -lt $expected.Count;$i++){Assert ($actual[$i] -ceq $expected[$i]) ('ARGV_CHANGED_'+$i)}
 Assert (($argv|ConvertTo-Json -Depth 12) -notmatch 'PSProvider|PSPath|PSDrive') 'TEXT_METADATA_LEAK'
 $batch=Join-Path $temp 'tiny wrapper.cmd'
 Set-Content $batch "@echo off`r`necho wrapper-success`r`nexit /b 0" -Encoding ASCII
 $cmdRun=Invoke-SasNativeProcess -FilePath $env:ComSpec -CommandLine ('/d /s /c ""'+$batch+'""') -TimeoutSeconds 5
 Assert ($cmdRun.exit_code -eq 0 -and $cmdRun.output.Trim() -eq 'wrapper-success') 'EXPLICIT_CMD_SPACES_FAILED'
 $prior=$env:SAS_NATIVE_528_PROBE;$priorRemove=$env:SAS_NATIVE_528_REMOVE
 try{
  $env:SAS_NATIVE_528_PROBE='parent';$env:SAS_NATIVE_528_REMOVE='remove-child-only'
  $envRun=Invoke-SasNativeProcess -FilePath $python -Arguments @($child,'env') -Environment @{SAS_NATIVE_528_PROBE='child';SAS_NATIVE_528_REMOVE=$null} -TimeoutSeconds 5
  $seen=$envRun.output|ConvertFrom-Json
  Assert ($seen.value -eq 'child' -and $null -eq $seen.removed) 'CHILD_ENVIRONMENT_OVERRIDE_FAILED'
  Assert ($env:SAS_NATIVE_528_PROBE -eq 'parent' -and $env:SAS_NATIVE_528_REMOVE -eq 'remove-child-only') 'PARENT_ENVIRONMENT_MUTATED'
 }finally{$env:SAS_NATIVE_528_PROBE=$prior;$env:SAS_NATIVE_528_REMOVE=$priorRemove}
 foreach($mode in @('timeout','drain')){
  $pidFile=Join-Path $temp ($mode+'.pid');$clock=[Diagnostics.Stopwatch]::StartNew()
  $run=Invoke-SasNativeProcess -FilePath $python -Arguments @($child,$mode,$pidFile) -TimeoutSeconds 2
  $clock.Stop();Check-Shape $run
  Assert ($clock.Elapsed.TotalSeconds -lt 15) ('UNBOUNDED_'+$mode)
  Assert (Test-Path $pidFile) ('DESCENDANT_NOT_STARTED_'+$mode)
  $ownedDescendant=[int](Get-Content $pidFile -Raw);$descendants+=@($ownedDescendant)
  if($mode -eq 'timeout'){
   Assert ($run.timed_out -and $run.child_tree_termination_attempted -and $run.exit_code -ne 0) 'TIMEOUT_BECAME_SUCCESS'
   Start-Sleep -Milliseconds 300
   Assert (-not (Get-Process -Id $ownedDescendant -ErrorAction SilentlyContinue)) 'TIMEOUT_DESCENDANT_SURVIVED'
  }else{Assert (-not $run.output_complete) 'PIPE_DESCENDANT_DRAIN_NOT_REPORTED'}
 }
 $failed=$false
 try{Invoke-SasNativeProcess -FilePath (Join-Path $temp 'missing.exe') -Arguments @() -TimeoutSeconds 2|Out-Null}catch{$failed=$true}
 Assert $failed 'START_FAILURE_ACCEPTED'
 Write-Host ('PASS: native-process-528 real-child contract; parent PowerShell '+$PSVersionTable.PSVersion)
}finally{
 foreach($ownedDescendant in $descendants){if(Get-Process -Id $ownedDescendant -ErrorAction SilentlyContinue){Stop-Process -Id $ownedDescendant -Force -ErrorAction SilentlyContinue}}
 Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
