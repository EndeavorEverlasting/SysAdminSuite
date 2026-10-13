<# Windows-native, preservation-first Android development lifecycle. Raw receipts remain private. #>
[CmdletBinding()]
param(
 [ValidateSet('Inventory','Plan','Apply','Verify','Repair','Bootstrap','Next')][string]$Operation='Inventory',
 [string]$NodeRole='ptop_lab', [string]$SdkRoot, [string]$JavaHome,
 [string]$OutputRoot, [string]$FixturePath, [switch]$MutationAuthorized,
 [switch]$LicenseAccepted, [switch]$LaunchStudio, [switch]$BuildSmoke,
 [switch]$BootEmulator, [string]$AvdName, [string]$ExpectedCommit,
 [switch]$TcpPipeFallback,
 [string]$HostProfile,
 [ValidateRange(0,1)][int]$SourceRestartCount=0,
 [int]$TimeoutSeconds=1800
)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$profilePath=Join-Path $repo 'Config/android-toolchain-profile.json'
if($NodeRole -eq 'adminbox_reference'){$profilePath=Join-Path $repo 'Config/android-adminbox-toolchain-profile.json'}
$profile=Get-Content $profilePath -Raw | ConvertFrom-Json
if(-not $OutputRoot){$OutputRoot=Join-Path $repo 'survey/output/android-toolchain'}
$result=[ordered]@{schema_version='sas-android-toolchain-result/v1';operation=$Operation;node_role=$NodeRole;result='BLOCK';reason_codes=@();proof=@();actions=@();inventory=$null;checks=@();source=$null;capability=$null}
$fixture=$null
function Assert-PTopProfile($Authority,$Equipment,[string]$RequestedOperation){
 if($Authority.schema_version -ne 'sas-android-toolchain-host-authority/v1' -or $Authority.status -ne 'RESOLVED' -or $Authority.node_role -ne 'ptop_lab' -or -not $Authority.evidence_ref -or $RequestedOperation -notin @($Authority.allowed_operations)){throw 'PTOP_PROFILE_AUTHORITY_INVALID'}
 if(-not $Authority.manufacturer -or -not $Authority.model -or $Authority.manufacturer -ne $Equipment.Manufacturer -or $Authority.model -ne $Equipment.Model){throw 'PTOP_EQUIPMENT_PROFILE_MISMATCH'}
}
function Assert-HostProfileForRole([string]$Role,$Authority,$Equipment,[string]$RequestedOperation,$DesiredState){
 # Role routing never weakens the preserved ptop_lab authority contract.
 if($Role -eq 'ptop_lab'){Assert-PTopProfile $Authority $Equipment $RequestedOperation;return}
 if($Role -ne 'adminbox_reference'){throw 'NODE_ROLE_MISMATCH'}
 if($Authority.schema_version -ne 'sas-android-toolchain-host-authority/v1' -or $Authority.status -ne 'RESOLVED' -or $Authority.node_role -ne 'adminbox_reference' -or -not $Authority.evidence_ref){throw 'ADMINBOX_PROFILE_AUTHORITY_INVALID'}
 # The sanitized desired-state profile is the operation ceiling; private authority may only narrow it.
 $approved=@($DesiredState.allowed_operations)
 if(-not $approved.Count -or $RequestedOperation -notin @($Authority.allowed_operations) -or @(@($Authority.allowed_operations)|Where-Object {$_ -notin $approved}).Count){throw 'ADMINBOX_PROFILE_AUTHORITY_INVALID'}
 if(-not $Authority.manufacturer -or -not $Authority.model -or $Authority.manufacturer -ne $Equipment.Manufacturer -or $Authority.model -ne $Equipment.Model){throw 'ADMINBOX_EQUIPMENT_PROFILE_MISMATCH'}
}
function Get-HostProfilePresence([string]$Path,[string]$Role,$DesiredState){
 # Read-only presence/shape classification for Next; never synthesizes RESOLVED authority.
 if(-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)){return [ordered]@{state='ABSENT';reason='ADMINBOX_PROFILE_AUTHORITY_REQUIRED'}}
 try{
  $authority=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json
  $equipment=if($fixture){[pscustomobject]@{Manufacturer=$authority.manufacturer;Model=$authority.model}}else{Get-CimInstance Win32_ComputerSystem}
  Assert-HostProfileForRole -Role $Role -Authority $authority -Equipment $equipment -RequestedOperation 'Inventory' -DesiredState $DesiredState
  return [ordered]@{state='RESOLVED';reason=$null;authority=$authority}
 }catch{
  $code=$_.Exception.Message
  if($code -notmatch '^(ADMINBOX_|PTOP_|NODE_ROLE)'){$code='ADMINBOX_PROFILE_AUTHORITY_INVALID'}
  return [ordered]@{state='INVALID';reason=$code}
 }
}
function Resolve-PlatformToolsPinStatus([string]$Role,[string]$PythonExe,[string]$RepoRoot,[string]$OutRoot){
 # Local catalog resolve only; never downloads or auto-promotes digests.
 $pinScript=@'
import json,sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from harness.api.android_platform_tools_pin import PinResolutionError, resolve
try:
    print(json.dumps(resolve(sys.argv[2])))
except PinResolutionError as exc:
    print(str(exc), file=sys.stderr)
    raise SystemExit(3)
'@
 $pinStdout=Join-Path $OutRoot ('next-pin-'+[guid]::NewGuid().ToString('N')+'.stdout.log')
 $pinStderr=Join-Path $OutRoot ('next-pin-'+[guid]::NewGuid().ToString('N')+'.stderr.log')
 $pinRun=Invoke-SasNativeProcess -FilePath $PythonExe -Arguments @('-c',$pinScript,$RepoRoot,$Role) -TimeoutSeconds 60 -StandardOutputPath $pinStdout -StandardErrorPath $pinStderr -Environment @{PSModulePath=($env:ProgramFiles+'\WindowsPowerShell\Modules;'+$env:SystemRoot+'\System32\WindowsPowerShell\v1.0\Modules')}
 if($pinRun.exit_code -ne 0){
  $code=((Get-Content -LiteralPath $pinStderr -Raw -ErrorAction SilentlyContinue)+'').Trim()
  if($code -notin @('QUALIFICATION_AUTHORITY_REQUIRED','INDEPENDENT_APPROVAL_REQUIRED','SOURCE_POLICY_DENIED')){$code='QUALIFICATION_AUTHORITY_REQUIRED'}
  return [ordered]@{state='NEEDS_APPROVAL';reason=$code;pin=$null}
 }
 $pin=Get-Content -LiteralPath $pinStdout -Raw|ConvertFrom-Json
 return [ordered]@{state='APPROVED';reason=$null;pin=$pin}
}
function Write-NextApprovalPackets([string]$OutRoot,$ProfileGate,$PinGate,$PinCatalogRow,$Equipment){
 $packetRoot=Join-Path $OutRoot 'approval-packets'
 New-Item -ItemType Directory -Force -Path $packetRoot|Out-Null
 $written=@()
 if($ProfileGate.state -ne 'RESOLVED'){
  $observedManufacturer=$null;$observedModel=$null
  if($Equipment){$observedManufacturer=$Equipment.Manufacturer;$observedModel=$Equipment.Model}
  $packetB=[ordered]@{
   schema_version='sas-android-host-profile-authorization-request/v1'
   packet_kind='REQUEST_FOR_APPROVAL'
   status='DRAFT_UNAPPROVED'
   requested_node_role=$NodeRole
   requested_allowed_operations=@($profile.allowed_operations)
   current_host_profile_state=$ProfileGate.state
   observed_manufacturer=$observedManufacturer
   observed_model=$observedModel
   required_approver='host_equipment_authority'
   missing_approvals=@('RESOLVED host-profile.json','matching manufacturer/model','evidence_ref','allowed_operations including Apply/Bootstrap')
   forbidden=@('synthesize_RESOLVED_from_CIM','infer_authority_from_hostname','commit_profile_to_git')
   why_blocked=$ProfileGate.reason
  }
  $pathB=Join-Path $packetRoot 'host-profile-authorization-draft.json'
  $packetB|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $pathB -Encoding UTF8
  $written+=@([ordered]@{packet='host_profile';path=$pathB;blocker=$ProfileGate.reason})
 }
 if($PinGate.state -ne 'APPROVED'){
  $artifactId='android-platform-tools-windows';$pinVersion=$null;$pinUrl=$null;$pinPromo=$null;$pinApproval=$null
  if($PinCatalogRow){
   $artifactId=$PinCatalogRow.artifact_id;$pinVersion=$PinCatalogRow.version;$pinUrl=$PinCatalogRow.acquisition_url
   $pinPromo=$PinCatalogRow.promotion_status;$pinApproval=$PinCatalogRow.approval_reference
  }
  $packetA=[ordered]@{
   schema_version='sas-android-pin-approval-review-packet/v1'
   packet_kind='REQUEST_FOR_APPROVAL'
   status='DRAFT_UNAPPROVED'
   artifact_id=$artifactId
   version=$pinVersion
   official_immutable_url=$pinUrl
   catalog_promotion_status=$pinPromo
   catalog_approval_reference=$pinApproval
   independently_approved_digest_status='ABSENT'
   decision_needed='Replace expected_archive_sha256 with independently reviewed organizational digest; set non-PENDING approval_reference; set promotion_status=approved_for_provider_prepare.'
   required_approver='package_security_authority'
   forbidden=@('auto_hash_of_download','treat_winget_as_approval','mutable_latest_url')
   why_blocked=$PinGate.reason
  }
  $pathA=Join-Path $packetRoot 'platform-tools-approval-draft.json'
  $packetA|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $pathA -Encoding UTF8
  $written+=@([ordered]@{packet='platform_tools_pin';path=$pathA;blocker=$PinGate.reason})
 }
 return $written
}
function Build-NextActions($DeveloperStack,[string]$DeveloperBlocker,$SasState,[string]$SasBlocker,$ProfileGate,$PinGate){
 # Deterministic dependency order: authority drafts before gated mutations.
 $actions=@()
 if($ProfileGate.state -ne 'RESOLVED'){
  $actions+=@([ordered]@{action_id='PREPARE_HOST_PROFILE_APPROVAL_PACKET';allowed_now=$true;requires_authority=$false;preconditions=@('read_only_next');proof_ref='approval-packets/host-profile-authorization-draft.json';command_owner='Manage-AdminBoxAndroidToolchain.cmd Next';why_blocked=$null})
 }
 if($PinGate.state -ne 'APPROVED'){
  $actions+=@([ordered]@{action_id='PREPARE_ARCHIVE_PIN_APPROVAL_PACKET';allowed_now=$true;requires_authority=$false;preconditions=@('read_only_next');proof_ref='approval-packets/platform-tools-approval-draft.json';command_owner='Manage-AdminBoxAndroidToolchain.cmd Next';why_blocked=$null})
 }
 $applyBlocked=if($ProfileGate.state -ne 'RESOLVED'){$DeveloperBlocker}elseif($DeveloperStack -eq 'VERIFIED'){$null}else{$null}
 if($DeveloperStack -in @('NEEDS_INSTALL','VERIFY_REQUIRED','UNKNOWN') -or $ProfileGate.state -ne 'RESOLVED'){
  $why=if($ProfileGate.state -ne 'RESOLVED'){$ProfileGate.reason}elseif($DeveloperStack -eq 'POLICY_BLOCKED'){'POLICY_BLOCKED'}else{'MUTATION_AUTHORIZATION_REQUIRED'}
  $actions+=@([ordered]@{action_id='APPLY_DEVELOPER_TOOLCHAIN';allowed_now=$false;requires_authority=$true;preconditions=@('RESOLVED host-profile','MutationAuthorized');proof_ref='Manage-AdminBoxAndroidToolchain.cmd Apply -MutationAuthorized';command_owner='Manage-AdminBoxAndroidToolchain.cmd Apply';why_blocked=$why})
 }
 if($SasState -in @('NEEDS_APPROVAL','NEEDS_PREPARE','VERIFY_REQUIRED','UNKNOWN') -or $PinGate.state -ne 'APPROVED' -or $ProfileGate.state -ne 'RESOLVED'){
  $why=if($PinGate.state -ne 'APPROVED'){$PinGate.reason}elseif($ProfileGate.state -ne 'RESOLVED'){$ProfileGate.reason}else{'MUTATION_AUTHORIZATION_REQUIRED'}
  $actions+=@([ordered]@{action_id='BOOTSTRAP_SAS_PLATFORM_TOOLS';allowed_now=$false;requires_authority=$true;preconditions=@('approved pin','RESOLVED host-profile','MutationAuthorized');proof_ref='Manage-AdminBoxAndroidToolchain.cmd Bootstrap -MutationAuthorized';command_owner='Manage-AdminBoxAndroidToolchain.cmd Bootstrap';why_blocked=$why})
 }
 return $actions
}
function Find-Tool([string]$Name,[string[]]$Candidates){
 foreach($candidate in $Candidates){if($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)){return (Resolve-Path -LiteralPath $candidate).Path}}
 $command=Get-Command $Name -ErrorAction SilentlyContinue
 if($command){return $command.Source};return $null
}
function Invoke-Bounded([string]$Exe,[string[]]$Arguments,[int]$Seconds=$TimeoutSeconds){
 if($fixture){throw 'FIXTURE_EXECUTION_FORBIDDEN'}
 $id=[guid]::NewGuid().ToString('N');$stdout=Join-Path $OutputRoot "$id.stdout.log";$stderr=Join-Path $OutputRoot "$id.stderr.log"
 # Windows command-line quoting preserves paths with spaces; reject embedded quotes.
 $quoted=@($Arguments|ForEach-Object {if($_ -match '"'){throw 'UNSAFE_ARGUMENT'};'"'+$_+'"'})
 $invoke=@{FilePath=$Exe;Arguments=$Arguments;TimeoutSeconds=$Seconds}
 if($Exe -eq $env:ComSpec){
  if($Arguments.Count -lt 3 -or $Arguments[0] -ne '/d' -or $Arguments[1] -ne '/c'){throw 'UNSAFE_CMD_INVOCATION'}
  foreach($arg in $Arguments[2..($Arguments.Count-1)]){if($arg -match '[&|<>^%\r\n]'){throw 'UNSAFE_CMD_ARGUMENT'}}
  # CMD owns its command-string grammar; native argv quoting is not interchangeable.
  $invoke.Remove('Arguments')
  $invoke.CommandLine='/d /s /c "'+(($quoted[2..($quoted.Count-1)]) -join ' ')+'"'
 }
 $childEnvironment=@{PSModulePath=($env:ProgramFiles+'\WindowsPowerShell\Modules;'+$env:SystemRoot+'\System32\WindowsPowerShell\v1.0\Modules')}
 $run=Invoke-SasNativeProcess @invoke -Environment $childEnvironment -StandardOutputPath $stdout -StandardErrorPath $stderr
 $check=[ordered]@{executable=$Exe;arguments=$Arguments;exit_code=$run.exit_code;stdout=$stdout;stderr=$stderr}
 if($run.timed_out){$check.timed_out=$true}
 $result.checks+=@($check)
 if($run.timed_out){throw 'SUBPROCESS_TIMEOUT'}
 if(-not $run.output_complete){throw 'SUBPROCESS_OUTPUT_INCOMPLETE'}
 if($run.output_truncated -or $run.error_truncated){throw 'SUBPROCESS_CAPTURE_LIMIT'}
 $text=[string]$run.output+[string]$run.error
 if($run.exit_code -ne 0){
  if($null -eq $run.exit_code){throw 'SUBPROCESS_EXIT_UNPROVEN'}
  if($text -match '(?i)license|accept.*terms'){throw 'LICENSE_ACCEPTANCE_REQUIRED'}
  if($text -match '(?i)access.*denied|administrator|elevation'){throw 'ADMIN_APPROVAL_REQUIRED'}
  if($text -match '(?i)no space|disk.*full'){throw 'INSUFFICIENT_DISK_SPACE'}
  if($text -match '(?i)network|resolve host|connection|download.*failed'){throw 'NETWORK_DOWNLOAD_FAILED'}
  throw 'COMMAND_FAILED'
 };return [string]::Concat('',[string]$run.output)
}
function Read-Inventory {
 if($fixture){return $fixture.inventory}
 if(-not $script:SdkRoot){$script:SdkRoot=if($env:ANDROID_HOME){$env:ANDROID_HOME}elseif($env:ANDROID_SDK_ROOT){$env:ANDROID_SDK_ROOT}else{Join-Path $env:LOCALAPPDATA 'Android/Sdk'}}
 if($env:ANDROID_SDK_ROOT -and $env:ANDROID_SDK_ROOT.TrimEnd('\','/').Replace('\','/') -ne $script:SdkRoot.TrimEnd('\','/').Replace('\','/')){throw 'SDK_ROOT_MISMATCH'}
 $jdkCandidates=@($JavaHome,$env:JAVA_HOME,'C:/Program Files/Java/jdk-21')
 $java=Find-Tool java.exe @($jdkCandidates|Where-Object {$_}|ForEach-Object {Join-Path $_ 'bin/java.exe'})
 $javac=Find-Tool javac.exe @($jdkCandidates|Where-Object {$_}|ForEach-Object {Join-Path $_ 'bin/javac.exe'})
 $studio=Find-Tool studio64.exe @('C:/Program Files/Android/Android Studio/bin/studio64.exe',(Join-Path $env:LOCALAPPDATA 'Programs/Android Studio/bin/studio64.exe'))
 $cli=Find-Tool android.exe @((Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Links/android.exe'))
 $sdkmanager=Find-Tool sdkmanager.bat @((Join-Path $SdkRoot 'cmdline-tools/latest/bin/sdkmanager.bat'))
 $studioSdk=$null
 if($studio){
  $studioRoot=Split-Path (Split-Path $studio -Parent) -Parent
  $productPath=Join-Path $studioRoot 'product-info.json'
  if(Test-Path -LiteralPath $productPath){
   $product=Get-Content -LiteralPath $productPath -Raw|ConvertFrom-Json
   $sdkOption=Join-Path $env:APPDATA ('Google/'+$product.dataDirectoryName+'/options/android.sdk.path.xml')
   if(Test-Path -LiteralPath $sdkOption){
    [xml]$sdkXml=Get-Content -LiteralPath $sdkOption -Raw
    $sdkNode=$sdkXml.SelectSingleNode('//option[@name="androidSdkAbsolutePath"]')
    if($sdkNode){$studioSdk=$sdkNode.GetAttribute('value')}
   }
  }
 }
 $packages=@();if(Test-Path $SdkRoot){$packages=@(Get-ChildItem $SdkRoot -Filter source.properties -Recurse -File -ErrorAction SilentlyContinue|ForEach-Object { $relative=$_.DirectoryName.Substring($SdkRoot.TrimEnd('\','/').Length).TrimStart('\','/');$relative.Replace('\','/')})}
 $drive=Get-PSDrive -PSProvider FileSystem | Where-Object {$SdkRoot.StartsWith($_.Root,[StringComparison]::OrdinalIgnoreCase)} | Select-Object -First 1
 return [pscustomobject]@{sdk_root=$SdkRoot;android_cli=$cli;studio=$studio;studio_sdk_root=$studioSdk;java=$java;javac=$javac;sdkmanager=$sdkmanager;packages=$packages;free_gib=if($drive){[math]::Round($drive.Free/1GB,2)}else{0};scope='CURRENT_USER';platform='windows-native';android_home=$env:ANDROID_HOME;avds=@(Get-ChildItem (Join-Path $env:USERPROFILE '.android/avd') -Filter '*.ini' -ErrorAction SilentlyContinue|ForEach-Object {$_.BaseName})}
}
try {
 New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
 if($NodeRole -notin @('ptop_lab','adminbox_reference')){throw 'NODE_ROLE_MISMATCH'}
 if($profile.node_role -ne $NodeRole){throw 'NODE_ROLE_MISMATCH'}
 if($FixturePath){$fixture=Get-Content -LiteralPath $FixturePath -Raw | ConvertFrom-Json;if($fixture.synthetic -ne $true){throw 'SYNTHETIC_FIXTURE_REQUIRED'}}
 if($fixture -and $Operation -in @('Apply','Repair','Bootstrap')){throw 'FIXTURE_MUTATION_FORBIDDEN'}
 if(-not $fixture){
  if($repo -eq 'C:\SASAL'){
   $state=Get-Content (Join-Path $env:LOCALAPPDATA 'SysAdminSuite/autologon-short-runtime.json') -Raw|ConvertFrom-Json
   $sealed=@($state.tracked_file_hashes|ForEach-Object {$_.path.Replace('\','/')})
   $sealedRequired=@('scripts/Invoke-SasAndroidToolchain.ps1','scripts/SasBoundedNative.psm1','Config/android-toolchain-profile.json','Manage-AndroidToolchain.cmd')
   if($NodeRole -eq 'adminbox_reference'){$sealedRequired=@('scripts/Invoke-SasAndroidToolchain.ps1','scripts/SasBoundedNative.psm1','Config/android-adminbox-toolchain-profile.json','Manage-AdminBoxAndroidToolchain.cmd','scripts/Start-SasAdminBoxAndroidToolchain.ps1')}
   foreach($required in $sealedRequired){if($required -notin $sealed -or -not (Test-Path -LiteralPath (Join-Path $repo $required) -PathType Leaf)){throw 'ANDROID_TOOLCHAIN_CAPABILITY_NOT_SEALED'}}
  }
  $nativeModule=Join-Path $PSScriptRoot 'SasBoundedNative.psm1'
  if(-not (Test-Path -LiteralPath $nativeModule -PathType Leaf)){throw 'NATIVE_PROCESS_MODULE_REQUIRED'}
  Import-Module $nativeModule -Force -ErrorAction Stop
  $python=Find-Tool python.exe @();if(-not $python){throw 'PYTHON_REQUIRED'}
  # Reuse AndroidProvider M2 source admission; never weaken canonical/sealed currentness.
  $admission='import sys,json;sys.path.insert(0,sys.argv[1]);from harness.api.android_provider_cli import admit_source;print(json.dumps(admit_source(sys.argv[2] or None)))'
  $result.source=Invoke-Bounded $python @('-c',$admission,$repo,$ExpectedCommit) 120
  $sourceState=$result.source|ConvertFrom-Json
  if($sourceState.source_updated){
   if($SourceRestartCount -ge 1){throw 'SOURCE_RESTART_LIMIT_REACHED'}
   $restart=@{};foreach($key in $PSBoundParameters.Keys){$restart[$key]=$PSBoundParameters[$key]};$restart.SourceRestartCount=1
   & $PSCommandPath @restart
   exit $LASTEXITCODE
  }
 }
 $inventory=Read-Inventory;$result.inventory=$inventory
 if($fixture -and $fixture.PSObject.Properties['reason_codes']){$result.reason_codes+=@($fixture.reason_codes)}
 $missing=@($profile.required_packages|Where-Object {$_ -notin @($inventory.packages)})
 foreach($package in $profile.native_packages){if($package -notin @($inventory.packages)){$missing+=@($package)}}
 if(-not @($inventory.packages|Where-Object {$_ -in @($profile.accepted_system_images)}).Count){$missing+=@($profile.system_image_prefix)}
 $result.actions=@($missing|ForEach-Object {@{action='INSTALL_MISSING';package=$_}})
 if(-not $inventory.java -or -not $inventory.javac){$result.reason_codes+=@('MISSING_STANDALONE_JDK')}
 if(-not $inventory.android_cli){$result.reason_codes+=@('MISSING_ANDROID_CLI')}
 if(-not $inventory.studio){$result.reason_codes+=@('MISSING_ANDROID_STUDIO')}
 if($inventory.android_home -and $inventory.android_home.TrimEnd('\','/') -ne $inventory.sdk_root.TrimEnd('\','/')){$result.reason_codes+=@('SDK_ROOT_MISMATCH')}
 if($inventory.studio_sdk_root -and $inventory.studio_sdk_root.TrimEnd('\','/').Replace('\','/') -ne $inventory.sdk_root.TrimEnd('\','/').Replace('\','/')){$result.reason_codes+=@('SDK_STUDIO_MISMATCH')}
 if($Operation -eq 'Verify' -and $missing.Count){$result.reason_codes+=@('SDK_PACKAGES_MISSING')}
 if($Operation -eq 'Verify' -and -not $inventory.sdkmanager){$result.reason_codes+=@('MISSING_SDK_COMMANDLINE_TOOLS')}
 if($Operation -eq 'Verify' -and $inventory.free_gib -lt $profile.minimum_free_gib){$result.reason_codes+=@('INSUFFICIENT_DISK_SPACE')}
 if($Operation -eq 'Next'){
  # Read-only readiness projection. Never calls Apply/Bootstrap or installs packages.
  $installGaps=@($result.reason_codes|Where-Object {$_ -in @('MISSING_STANDALONE_JDK','MISSING_ANDROID_CLI','MISSING_ANDROID_STUDIO')})
  if($missing.Count){$installGaps+=@('SDK_PACKAGES_MISSING')}
  $policyGaps=@($result.reason_codes|Where-Object {$_ -in @('PROTECTED_NETWORK_DENIED','SOURCE_POLICY_DENIED')})
  if($policyGaps.Count){$developerStack='POLICY_BLOCKED'}
  elseif($installGaps.Count){$developerStack='NEEDS_INSTALL'}
  elseif($Operation -eq 'Next' -and $result.reason_codes -contains 'SDK_PACKAGES_MISSING'){$developerStack='VERIFY_REQUIRED'}
  elseif(-not $inventory.java -or -not $inventory.javac -or -not $inventory.android_cli -or -not $inventory.studio){$developerStack='UNKNOWN'}
  elseif($missing.Count){$developerStack='VERIFY_REQUIRED'}
  else{$developerStack='VERIFIED'}

  if(-not $HostProfile){$HostProfile=Join-Path $env:LOCALAPPDATA 'SysAdminSuite/android-toolchain/host-profile.json'}
  $equipment=$null
  if($fixture -and $fixture.PSObject.Properties['next_projection']){
   $proj=$fixture.next_projection
   $profileGate=[ordered]@{state=[string]$proj.host_profile_state;reason=[string]$proj.host_profile_reason}
   if(-not $profileGate.reason -and $profileGate.state -ne 'RESOLVED'){$profileGate.reason=if($NodeRole -eq 'adminbox_reference'){'ADMINBOX_PROFILE_AUTHORITY_REQUIRED'}else{'PTOP_PROFILE_AUTHORITY_REQUIRED'}}
   $pinGate=[ordered]@{state=[string]$proj.pin_state;reason=[string]$proj.pin_reason;pin=$null}
   if(-not $pinGate.reason -and $pinGate.state -ne 'APPROVED'){$pinGate.reason='QUALIFICATION_AUTHORITY_REQUIRED'}
   $pinRow=$null
   if($proj.PSObject.Properties['pin_catalog_row']){$pinRow=$proj.pin_catalog_row}
  }else{
   if(-not (Get-Module SasBoundedNative -ErrorAction SilentlyContinue)){
    $nativeModule=Join-Path $PSScriptRoot 'SasBoundedNative.psm1'
    if(-not (Test-Path -LiteralPath $nativeModule -PathType Leaf)){throw 'NATIVE_PROCESS_MODULE_REQUIRED'}
    Import-Module $nativeModule -Force -ErrorAction Stop
   }
   $pythonExe=Find-Tool python.exe @();if(-not $pythonExe){throw 'PYTHON_REQUIRED'}
   $profileGate=Get-HostProfilePresence -Path $HostProfile -Role $NodeRole -DesiredState $profile
   if($profileGate.state -eq 'ABSENT' -and $NodeRole -eq 'ptop_lab'){$profileGate.reason='PTOP_PROFILE_AUTHORITY_REQUIRED'}
   $pinGate=Resolve-PlatformToolsPinStatus -Role $NodeRole -PythonExe $pythonExe -RepoRoot $repo -OutRoot $OutputRoot
   $pinCatalogPath=Join-Path $repo 'configs/android-provider/sas-platform-tools-archive-pins.json'
   $pinRow=$null
   if(Test-Path -LiteralPath $pinCatalogPath){$pinRow=@((Get-Content -LiteralPath $pinCatalogPath -Raw|ConvertFrom-Json).pins)|Select-Object -First 1}
   if(-not $fixture){$equipment=Get-CimInstance Win32_ComputerSystem}
  }

  if($profileGate.state -ne 'RESOLVED' -and $profileGate.reason){$result.reason_codes+=@($profileGate.reason)}
  if($pinGate.state -ne 'APPROVED' -and $pinGate.reason){$result.reason_codes+=@($pinGate.reason)}

  if($pinGate.state -eq 'APPROVED'){$sasState='NEEDS_PREPARE'}else{$sasState='NEEDS_APPROVAL'}
  if($pinGate.state -eq 'APPROVED' -and $result.proof -contains 'VERIFIED'){$sasState='QUALIFIED'}
  if($developerStack -eq 'POLICY_BLOCKED' -and $pinGate.reason -eq 'SOURCE_POLICY_DENIED'){$sasState='UNKNOWN'}

  $developerBlocker=if($profileGate.state -ne 'RESOLVED'){$profileGate.reason}elseif($developerStack -eq 'POLICY_BLOCKED'){$policyGaps[0]}elseif($installGaps.Count){$installGaps[0]}else{$null}
  $sasBlocker=if($pinGate.state -ne 'APPROVED'){$pinGate.reason}elseif($profileGate.state -ne 'RESOLVED'){$profileGate.reason}else{$null}

  $packets=Write-NextApprovalPackets -OutRoot $OutputRoot -ProfileGate $profileGate -PinGate $pinGate -PinCatalogRow $pinRow -Equipment $equipment
  $result.actions=@(Build-NextActions -DeveloperStack $developerStack -DeveloperBlocker $developerBlocker -SasState $sasState -SasBlocker $sasBlocker -ProfileGate $profileGate -PinGate $pinGate)
  $result.capability=[ordered]@{
   developer_stack=$developerStack
   sas_adb=$sasState
   inspection='COMPLETE'
   operational_readiness='NOT_YET_PROVEN'
  }
  if($developerStack -eq 'VERIFIED' -and $sasState -eq 'QUALIFIED' -and $profileGate.state -eq 'RESOLVED'){
   $result.capability.operational_readiness='PROVEN'
  }
  $result.proof+=@('INSPECTION_COMPLETE')
  if($packets.Count){$result.proof+=@('APPROVAL_PACKETS_DRAFTED')}
  # Inventory SUCCESS is not operational readiness; keep tracks independent in terminal form.
  Write-Host ("Developer toolchain: {0}" -f $developerStack)
  if($developerBlocker){Write-Host ("Current blocker: {0}" -f $developerBlocker)}
  $devAction=@($result.actions|Where-Object {$_.action_id -in @('PREPARE_HOST_PROFILE_APPROVAL_PACKET','APPLY_DEVELOPER_TOOLCHAIN')}|Select-Object -First 1)
  if($devAction){Write-Host ("Safe next action: {0}" -f $devAction.action_id)}
  Write-Host ("SAS-qualified ADB: {0}" -f $sasState)
  if($sasBlocker){Write-Host ("Current blocker: {0}" -f $sasBlocker)}
  $sasAction=@($result.actions|Where-Object {$_.action_id -in @('PREPARE_ARCHIVE_PIN_APPROVAL_PACKET','BOOTSTRAP_SAS_PLATFORM_TOOLS')}|Select-Object -First 1)
  if($sasAction){Write-Host ("Safe next action: {0}" -f $sasAction.action_id)}
  Write-Host ("Inspection: {0}" -f $result.capability.inspection)
  Write-Host ("Operational readiness: {0}" -f $result.capability.operational_readiness)
 }
 if($Operation -eq 'Bootstrap'){
  if(-not $MutationAuthorized){throw 'MUTATION_AUTHORIZATION_REQUIRED'}
  if(-not $HostProfile){$HostProfile=Join-Path $env:LOCALAPPDATA 'SysAdminSuite/android-toolchain/host-profile.json'}
  if(-not (Test-Path -LiteralPath $HostProfile)){if($NodeRole -eq 'adminbox_reference'){throw 'ADMINBOX_PROFILE_AUTHORITY_REQUIRED'};throw 'PTOP_PROFILE_AUTHORITY_REQUIRED'}
  $authority=Get-Content -LiteralPath $HostProfile -Raw|ConvertFrom-Json
  $hostEquipment=Get-CimInstance Win32_ComputerSystem
  Assert-HostProfileForRole -Role $NodeRole -Authority $authority -Equipment $hostEquipment -RequestedOperation $Operation -DesiredState $profile
  # Independently reviewed pin catalog is the only prepare authority; never hash-of-download.
  $pinScript=@'
import json,sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from harness.api.android_platform_tools_pin import PinResolutionError, resolve
try:
    print(json.dumps(resolve(sys.argv[2])))
except PinResolutionError as exc:
    print(str(exc), file=sys.stderr)
    raise SystemExit(3)
'@
  $pinStdout=Join-Path $OutputRoot ('pin-resolve-'+[guid]::NewGuid().ToString('N')+'.stdout.log')
  $pinStderr=Join-Path $OutputRoot ('pin-resolve-'+[guid]::NewGuid().ToString('N')+'.stderr.log')
  $pinRun=Invoke-SasNativeProcess -FilePath $python -Arguments @('-c',$pinScript,$repo,$NodeRole) -TimeoutSeconds 60 -StandardOutputPath $pinStdout -StandardErrorPath $pinStderr -Environment @{PSModulePath=($env:ProgramFiles+'\WindowsPowerShell\Modules;'+$env:SystemRoot+'\System32\WindowsPowerShell\v1.0\Modules')}
  if($pinRun.exit_code -ne 0){
   $code=((Get-Content -LiteralPath $pinStderr -Raw -ErrorAction SilentlyContinue)+'').Trim()
   if($code -notin @('QUALIFICATION_AUTHORITY_REQUIRED','INDEPENDENT_APPROVAL_REQUIRED','SOURCE_POLICY_DENIED')){$code='QUALIFICATION_AUTHORITY_REQUIRED'}
   throw $code
  }
  $pin=Get-Content -LiteralPath $pinStdout -Raw|ConvertFrom-Json
  $staging=Join-Path $OutputRoot 'sas-platform-tools-staging';New-Item -ItemType Directory -Force $staging|Out-Null
  $fileName=[IO.Path]::GetFileName([uri]$pin.acquisition_url)
  if($fileName -match 'latest'){throw 'SOURCE_POLICY_DENIED'}
  $map=Join-Path $staging 'fetch-map.csv'
  @([pscustomobject]@{Name='Android Platform Tools';Url=$pin.acquisition_url;FileName=$fileName;Type='zip';Version=$pin.version;SilentArgs='';AllowDomains='dl.google.com'})|Export-Csv -NoTypeInformation $map
  $archive=Join-Path $staging ('installers/'+$fileName)
  if(-not (Test-Path -LiteralPath $archive)){
   $pwsh=Find-Tool pwsh.exe @('C:/Program Files/PowerShell/7/pwsh.exe');if(-not $pwsh){throw 'POWERSHELL7_FETCHER_REQUIRED'}
   Invoke-Bounded $pwsh @('-NoProfile','-File',(Join-Path $repo 'Config/Fetch-Installers.ps1'),'-RepoRoot',$staging,'-FetchMap',$map)|Out-Null
  }
  if(-not (Test-Path -LiteralPath $archive)){throw 'MISSING_ASSET'}
  $actual=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
  if($actual -ne ([string]$pin.expected_archive_sha256).ToLowerInvariant()){throw 'HASH_MISMATCH'}
  $prepareArgs=@((Join-Path $repo 'harness/api/android_provider_cli.py'),'prepare','--role',$NodeRole,'--archive',$archive,'--archive-sha256',$pin.expected_archive_sha256,'--archive-source',$pin.acquisition_url)
  if($ExpectedCommit){$prepareArgs+=@('--expected-commit',$ExpectedCommit)}
  Invoke-Bounded $python $prepareArgs 180|Out-Null
  $result.proof+=@('PREPARED')
  foreach($op in @('status','doctor','verify')){
   $verifyArgs=@((Join-Path $repo 'harness/api/android_provider_cli.py'),$op,'--role',$NodeRole)
   if($ExpectedCommit){$verifyArgs+=@('--expected-commit',$ExpectedCommit)}
   Invoke-Bounded $python $verifyArgs 120|Out-Null
  }
  $result.proof+=@('VERIFIED')
  # Bootstrap qualifies SAS-owned Platform-Tools only; developer CLI/Studio gaps stay separate.
  $result.reason_codes=@($result.reason_codes|Where-Object {$_ -notin @('MISSING_ANDROID_CLI','MISSING_ANDROID_STUDIO','MISSING_STANDALONE_JDK')})
 }
 if($Operation -in @('Apply','Repair')){
  if(-not $MutationAuthorized){throw 'MUTATION_AUTHORIZATION_REQUIRED'}
  # Caller-supplied role is routing, not approved equipment-profile authority.
  if(-not $HostProfile){$HostProfile=Join-Path $env:LOCALAPPDATA 'SysAdminSuite/android-toolchain/host-profile.json'}
  if(-not (Test-Path -LiteralPath $HostProfile)){if($NodeRole -eq 'adminbox_reference'){throw 'ADMINBOX_PROFILE_AUTHORITY_REQUIRED'};throw 'PTOP_PROFILE_AUTHORITY_REQUIRED'}
  $authority=Get-Content -LiteralPath $HostProfile -Raw|ConvertFrom-Json
  $hostEquipment=Get-CimInstance Win32_ComputerSystem
  Assert-HostProfileForRole -Role $NodeRole -Authority $authority -Equipment $hostEquipment -RequestedOperation $Operation -DesiredState $profile
  if($inventory.free_gib -lt $profile.minimum_free_gib){throw 'INSUFFICIENT_DISK_SPACE'}
  # WinGet exact vendor identities are acquisition only; no license acceptance flags.
  # Existing executables win over package-manager metadata and are never reinstalled.
  $installIds=@{}
  if(-not $inventory.java -or -not $inventory.javac){$installIds['MISSING_STANDALONE_JDK']='EclipseAdoptium.Temurin.21.JDK'}
  if(-not $inventory.android_cli){$installIds['MISSING_ANDROID_CLI']='Google.AndroidCLI'}
  if(-not $inventory.studio){$installIds['MISSING_ANDROID_STUDIO']='Google.AndroidStudio'}
  if($installIds.Count){
   $winget=Find-Tool winget.exe @();if(-not $winget){throw 'PACKAGE_MANAGER_REQUIRED'}
   foreach($reason in @($installIds.Keys)){
    Invoke-Bounded $winget @('install','--id',$installIds[$reason],'--exact','--source','winget','--disable-interactivity')|Out-Null
   }
   # Resolve newly acquired tools from their user/system install roots, independent of old PATH.
   $temurin=Get-ChildItem 'C:/Program Files/Eclipse Adoptium' -Directory -Filter 'jdk-21*' -ErrorAction SilentlyContinue|Select-Object -First 1
   if($temurin){$script:JavaHome=$temurin.FullName}
   $inventory=Read-Inventory;$result.inventory=$inventory
   $result.reason_codes=@($result.reason_codes|Where-Object {$_ -notin @($installIds.Keys)})
   if(-not $inventory.java -or -not $inventory.javac){throw 'JDK_INSTALL_NOT_VERIFIED'}
   if(-not $inventory.android_cli){throw 'ANDROID_CLI_INSTALL_NOT_VERIFIED'}
   if(-not $inventory.studio){throw 'STUDIO_INSTALL_NOT_VERIFIED'}
  }
  if($result.reason_codes.Count){throw $result.reason_codes[0]}
  # The first-party CLI owns package download integrity and installer provenance.
  $available=Invoke-Bounded $inventory.android_cli @("--sdk=$SdkRoot",'sdk','list','--all')
  foreach($package in $missing){
   if($package.EndsWith('LATEST_SUPPORTED')){
    $prefix=$package.Replace('LATEST_SUPPORTED','');$matches=[regex]::Matches($available,[regex]::Escape($prefix)+'[0-9][0-9.]*')|ForEach-Object {$_.Value}|Sort-Object -Unique
    $package=$matches|Sort-Object {[version]($_.Substring($prefix.Length))} -Descending|Select-Object -First 1
   }
   if(-not $package -or $available -notmatch [regex]::Escape($package)){throw 'SDK_PACKAGE_UNSUPPORTED'}
   # No stdin yes pipeline, license hashes, or automatic acceptance flag.
   Invoke-Bounded $inventory.android_cli @("--sdk=$SdkRoot",'sdk','install',$package,'--no-downgrade') | Out-Null
  }
  $jdkRoot=Split-Path (Split-Path $inventory.javac -Parent) -Parent
  $before=@{ANDROID_HOME=[Environment]::GetEnvironmentVariable('ANDROID_HOME','User');JAVA_HOME=[Environment]::GetEnvironmentVariable('JAVA_HOME','User');PATH=[Environment]::GetEnvironmentVariable('PATH','User')}
  $before|ConvertTo-Json|Set-Content (Join-Path $OutputRoot ('user-environment-before-'+[guid]::NewGuid().ToString('N')+'.json')) -Encoding UTF8
  if($before.ANDROID_HOME -and $before.ANDROID_HOME.TrimEnd('\','/') -ne $SdkRoot.TrimEnd('\','/')){throw 'ANDROID_HOME_MISMATCH'}
  if($before.JAVA_HOME -and $before.JAVA_HOME.TrimEnd('\','/') -ne $jdkRoot.TrimEnd('\','/')){throw 'JAVA_HOME_MISMATCH'}
  try{
  [Environment]::SetEnvironmentVariable('ANDROID_HOME',$SdkRoot,'User');$env:ANDROID_HOME=$SdkRoot
  [Environment]::SetEnvironmentVariable('JAVA_HOME',$jdkRoot,'User');$env:JAVA_HOME=$jdkRoot
  $entries=@((Join-Path $jdkRoot 'bin'))+@($before.PATH -split ';'|Where-Object {$_ -and $_ -ne (Join-Path $jdkRoot 'bin')})
  foreach($entry in @((Join-Path $jdkRoot 'bin'),(Join-Path $SdkRoot 'cmdline-tools/latest/bin'),(Join-Path $SdkRoot 'platform-tools'),(Split-Path $inventory.android_cli -Parent))){if($entry -notin $entries){$entries+=@($entry)}}
  [Environment]::SetEnvironmentVariable('PATH',($entries -join ';'),'User');$env:PATH=((Join-Path $jdkRoot 'bin')+';'+$env:PATH+';'+($entries -join ';'))
  }catch{foreach($name in @('ANDROID_HOME','JAVA_HOME','PATH')){[Environment]::SetEnvironmentVariable($name,$before[$name],'User')};throw}
  $result.inventory=Read-Inventory
  if(@(($profile.required_packages+$profile.native_packages)|Where-Object {$_ -notin @($result.inventory.packages)}).Count){throw 'INSTALL_READBACK_INCOMPLETE'}
  if(-not @($result.inventory.packages|Where-Object {$_ -in @($profile.accepted_system_images)}).Count){throw 'SYSTEM_IMAGE_READBACK_INCOMPLETE'}
  $result.proof+=@('WINDOWS_INSTALLED')
  # Developer Apply never self-approves SAS qualification. Use Bootstrap with a reviewed pin.
  try{Invoke-Bounded $python @((Join-Path $repo 'harness/api/android_provider_cli.py'),'verify','--role',$NodeRole) 120|Out-Null;$result.proof+=@('SAS_HOST_READY')}catch{$result.reason_codes+=@('QUALIFICATION_AUTHORITY_REQUIRED')}
 }
 if($Operation -eq 'Verify' -and -not $fixture){
  if($result.reason_codes.Count){throw $result.reason_codes[0]}
  Invoke-Bounded $inventory.java @('-version')|Out-Null;Invoke-Bounded $inventory.javac @('-version')|Out-Null
  Invoke-Bounded $inventory.android_cli @('-V')|Out-Null;Invoke-Bounded $inventory.android_cli @("--sdk=$SdkRoot",'info')|Out-Null
  Invoke-Bounded $inventory.android_cli @("--sdk=$SdkRoot",'sdk','list')|Out-Null;$result.proof+=@('CLI_VERIFIED')
  $env:JAVA_HOME=Split-Path (Split-Path $inventory.javac -Parent) -Parent
  Invoke-Bounded $env:ComSpec @('/d','/c',$inventory.sdkmanager,'--list_installed')|Out-Null
  Invoke-Bounded (Join-Path $SdkRoot 'cmake/3.22.1/bin/cmake.exe') @('--version')|Out-Null
  Invoke-Bounded (Join-Path $SdkRoot 'ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin/clang.exe') @('--version')|Out-Null
  if($LaunchStudio){$studioProcesses=@(Get-Process studio64 -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $inventory.studio -and $_.MainWindowHandle -ne 0});if($studioProcesses.Count){$result.actions+=@(@{action='REUSE_EXISTING_STUDIO'})}else{$p=Start-Process $inventory.studio -PassThru -WindowStyle Hidden;Start-Sleep -Seconds 8};$studioProcesses=@(Get-Process studio64 -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $inventory.studio});if(-not $studioProcesses.Count){throw 'STUDIO_LAUNCH_FAILED'};$result.proof+=@('GUI_PROCESS_OBSERVED');if(@($studioProcesses|Where-Object {$_.MainWindowHandle -ne 0 -and $_.MainWindowTitle}).Count){$result.proof+=@('GUI_WINDOW_OBSERVED')}}
  if($BuildSmoke){
   $project=Join-Path $OutputRoot ('kotlin-smoke-'+[guid]::NewGuid().ToString('N'))
   Invoke-Bounded $inventory.android_cli @("--sdk=$SdkRoot",'create','--name','SasSmoke','--namespace','org.example.sassmoke','--application-id','org.example.sassmoke','--output',$project,'empty-activity')|Out-Null
   $wrapper=Join-Path $project 'gradlew.bat';if(-not (Test-Path $wrapper)){throw 'GRADLE_WRAPPER_MISSING'}
   $env:JAVA_HOME=Split-Path (Split-Path $inventory.javac -Parent) -Parent
   if(-not (Get-ChildItem $project -Recurse -Filter '*.kt')){throw 'KOTLIN_SOURCE_MISSING'}
   $previousJavaOptions=$env:JAVA_TOOL_OPTIONS
   try {
    if($TcpPipeFallback){
     # JDK's documented Unix socket temp property forces its built-in TCP pipe fallback.
     # Scoped to this build; no firewall, host security, or global JVM changes.
     $noUnix=Join-Path $OutputRoot ('tcp-pipe-unavailable-'+[guid]::NewGuid().ToString('N'))
     $env:JAVA_TOOL_OPTIONS=($previousJavaOptions+' "-Djdk.net.unixdomain.tmpdir='+$noUnix+'"').Trim()
     $result.actions+=@(@{action='SCOPED_JDK_TCP_PIPE_FALLBACK'})
    }
    Invoke-Bounded $env:ComSpec @('/d','/c',$wrapper,'-p',$project,'--no-daemon','assembleDebug')|Out-Null
   }finally{$env:JAVA_TOOL_OPTIONS=$previousJavaOptions}
   if(-not (Get-ChildItem (Join-Path $project 'app/build/outputs/apk/debug') -Filter '*.apk' -ErrorAction SilentlyContinue)){throw 'BUILD_APK_MISSING'};$result.proof+=@('BUILD_VERIFIED')
  }
  if($BootEmulator){
   $emulator=Join-Path $SdkRoot 'emulator/emulator.exe';$adb=Join-Path $SdkRoot 'platform-tools/adb.exe'
   $avds=Invoke-Bounded $emulator @('-list-avds');if(-not $AvdName){$AvdName=@($inventory.avds)[0]};if(-not $AvdName -or $AvdName -notin @($avds -split '\r?\n'|ForEach-Object {$_.Trim()})){throw 'AVD_REQUIRED'}
   foreach($port in @(5580,5581,5589)){if(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue){throw 'EMULATOR_PORT_IN_USE'}}
   $priorAdbPort=$env:ANDROID_ADB_SERVER_PORT;$priorMdns=$env:ADB_MDNS_AUTO_CONNECT;$priorUsb=$env:ADB_USB;$priorMdnsEnabled=$env:ADB_MDNS
   $env:ANDROID_ADB_SERVER_PORT='5589';$env:ADB_MDNS_AUTO_CONNECT='0';$env:ADB_USB='0';$env:ADB_MDNS='0'
   $emu=$null;$adbServer=$null
   try{
    # ADB's tcp:PORT syntax binds loopback; hostname syntax is unsupported in 37.0.1.
    $adbServer=Start-Process $adb -ArgumentList @('-L','tcp:5589','--one-device','emulator-5580','nodaemon','server') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $OutputRoot 'owned-adb.stdout.log') -RedirectStandardError (Join-Path $OutputRoot 'owned-adb.stderr.log')
    Start-Sleep -Seconds 2
    if($adbServer.HasExited){throw 'OWNED_ADB_START_FAILED'}
    $listener=@(Get-NetTCPConnection -LocalPort 5589 -State Listen -ErrorAction SilentlyContinue)
    if(-not $listener.Count -or @($listener|Where-Object {$_.OwningProcess -ne $adbServer.Id -or $_.LocalAddress -notin @('127.0.0.1','::1')}).Count){throw 'ADB_LOOPBACK_BIND_UNPROVEN'}
    $emu=Start-Process $emulator -ArgumentList @('-avd',$AvdName,'-no-window','-no-audio','-no-snapshot-save','-gpu','swiftshader','-cores','4','-port','5580') -WindowStyle Hidden -PassThru
    $deadline=[datetime]::UtcNow.AddSeconds(300);$booted=$false
    while([datetime]::UtcNow -lt $deadline -and -not $emu.HasExited){try{$boot=Invoke-Bounded $adb @('-P','5589','-s','emulator-5580','shell','getprop','sys.boot_completed') 15;if($boot.Trim() -eq '1'){$booted=$true;break}}catch{if($_.Exception.Message -ne 'COMMAND_FAILED'){throw}};Start-Sleep -Seconds 5}
    if(-not $booted){throw 'EMULATOR_BOOT_FAILED'};$result.proof+=@('EMULATOR_BOOT_VERIFIED')
   }finally{if($emu -and -not $emu.HasExited){try{Invoke-Bounded $adb @('-P','5589','-s','emulator-5580','emu','kill') 15|Out-Null}catch{$result.reason_codes+=@('EMULATOR_CLEANUP_COMMAND_FAILED')};if(-not $emu.WaitForExit(15000)){& "$env:SystemRoot/System32/taskkill.exe" /PID $emu.Id /T /F|Out-Null}};try{if($adbServer -and -not $adbServer.HasExited){Stop-Process -Id $adbServer.Id -ErrorAction Stop;$adbServer.WaitForExit(15000)|Out-Null}}catch{$result.reason_codes+=@('ADB_CLEANUP_FAILED')}finally{$env:ANDROID_ADB_SERVER_PORT=$priorAdbPort;$env:ADB_MDNS_AUTO_CONNECT=$priorMdns;$env:ADB_USB=$priorUsb;$env:ADB_MDNS=$priorMdnsEnabled};if(Get-NetTCPConnection -State Listen -LocalPort 5580,5581,5589 -ErrorAction SilentlyContinue){$result.reason_codes+=@('OWNED_PORT_CLEANUP_INCOMPLETE')}}
  }
  foreach($op in @('status','doctor','verify')){try{Invoke-Bounded $python @((Join-Path $repo 'harness/api/android_provider_cli.py'),$op,'--role',$NodeRole) 120|Out-Null}catch{$result.reason_codes+=@('SAS_PROVIDER_NOT_READY')}}
 }
 if($fixture){$result.proof=@('FIXTURE_ONLY')}
 if($Operation -in @('Inventory','Plan','Next')){$result.result='SUCCESS'}elseif(-not $result.reason_codes.Count){$result.result='SUCCESS'}
}catch{$result.reason_codes+=@($_.Exception.Message);$result.result='BLOCK'}
$result.reason_codes=@($result.reason_codes|Select-Object -Unique)
if($null -eq $result.capability){$result.capability=$null}
$receipt=Join-Path $OutputRoot ('receipt-'+[datetime]::UtcNow.ToString('yyyyMMddTHHmmssfffffff')+'.json')
$result|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $receipt -Encoding UTF8
Write-Output ($result|ConvertTo-Json -Depth 12)
if($result.result -ne 'SUCCESS'){exit 2}
