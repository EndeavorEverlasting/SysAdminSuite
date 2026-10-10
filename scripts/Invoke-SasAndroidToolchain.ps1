<# Windows-native, preservation-first Android development lifecycle. Raw receipts remain private. #>
[CmdletBinding()]
param(
 [ValidateSet('Inventory','Plan','Apply','Verify','Repair')][string]$Operation='Inventory',
 [string]$NodeRole='ptop_lab', [string]$SdkRoot, [string]$JavaHome,
 [string]$OutputRoot, [string]$FixturePath, [switch]$MutationAuthorized,
 [switch]$LicenseAccepted, [switch]$LaunchStudio, [switch]$BuildSmoke,
 [switch]$BootEmulator, [string]$AvdName, [string]$ExpectedCommit,
 [switch]$TcpPipeFallback,
 [int]$TimeoutSeconds=1800
)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$profile=Get-Content (Join-Path $repo 'Config/android-toolchain-profile.json') -Raw | ConvertFrom-Json
if(-not $OutputRoot){$OutputRoot=Join-Path $repo 'survey/output/android-toolchain'}
$result=[ordered]@{schema_version='sas-android-toolchain-result/v1';operation=$Operation;node_role=$NodeRole;result='BLOCK';reason_codes=@();proof=@();actions=@();inventory=$null;checks=@();source=$null}
$fixture=$null
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
 $priorModulePath=$env:PSModulePath
 try {
  # Provider admission uses Windows PowerShell; pwsh's inherited module path is incompatible.
  $env:PSModulePath=($env:ProgramFiles+'\WindowsPowerShell\Modules;'+$env:SystemRoot+'\System32\WindowsPowerShell\v1.0\Modules')
  $commandLine=$quoted -join ' '
  if($Exe -eq $env:ComSpec){
   if($Arguments[0] -ne '/d' -or $Arguments[1] -ne '/c'){throw 'UNSAFE_CMD_INVOCATION'}
   foreach($arg in $Arguments[2..($Arguments.Count-1)]){if($arg -match '[&|<>^%\r\n]'){throw 'UNSAFE_CMD_ARGUMENT'}}
   $commandLine='/d /s /c "'+(($quoted[2..($quoted.Count-1)]) -join ' ')+'"'
  }
  $process=Start-Process -FilePath $Exe -ArgumentList $commandLine -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
 } finally {$env:PSModulePath=$priorModulePath}
 if(-not $process.WaitForExit($Seconds*1000)){
  # The returned PID owns this process tree; never terminate by executable name.
  & "$env:SystemRoot/System32/taskkill.exe" /PID $process.Id /T /F | Out-Null
  $result.checks+=@(@{executable=$Exe;arguments=$Arguments;exit_code=$null;stdout=$stdout;stderr=$stderr;timed_out=$true})
  throw 'SUBPROCESS_TIMEOUT'
 }
 $process.Refresh();$text=(Get-Content $stdout -Raw -ErrorAction SilentlyContinue)+(Get-Content $stderr -Raw -ErrorAction SilentlyContinue)
 $check=[ordered]@{executable=$Exe;arguments=$Arguments;exit_code=$process.ExitCode;stdout=$stdout;stderr=$stderr}
 $result.checks+=@($check)
 if($process.ExitCode -ne 0){
  if($text -match '(?i)license|accept.*terms'){throw 'LICENSE_ACCEPTANCE_REQUIRED'}
  if($text -match '(?i)access.*denied|administrator|elevation'){throw 'ADMIN_APPROVAL_REQUIRED'}
  if($text -match '(?i)no space|disk.*full'){throw 'INSUFFICIENT_DISK_SPACE'}
  if($text -match '(?i)network|resolve host|connection|download.*failed'){throw 'NETWORK_DOWNLOAD_FAILED'}
  throw 'COMMAND_FAILED'
 };return $text
}
function Read-Inventory {
 if($fixture){return $fixture.inventory}
 if(-not $script:SdkRoot){$script:SdkRoot=if($env:ANDROID_HOME){$env:ANDROID_HOME}else{Join-Path $env:LOCALAPPDATA 'Android/Sdk'}}
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
 if($NodeRole -ne 'ptop_lab'){throw 'NODE_ROLE_MISMATCH'}
 if($FixturePath){$fixture=Get-Content -LiteralPath $FixturePath -Raw | ConvertFrom-Json;if($fixture.synthetic -ne $true){throw 'SYNTHETIC_FIXTURE_REQUIRED'}}
 if($fixture -and $Operation -in @('Apply','Repair')){throw 'FIXTURE_MUTATION_FORBIDDEN'}
 if(-not $fixture -and ($Operation -in @('Apply','Repair','Verify'))){
  if($repo -eq 'C:\SASAL'){
   $state=Get-Content (Join-Path $env:LOCALAPPDATA 'SysAdminSuite/autologon-short-runtime.json') -Raw|ConvertFrom-Json
   $sealed=@($state.tracked_file_hashes|ForEach-Object {$_.path.Replace('\','/')})
   foreach($required in @('scripts/Invoke-SasAndroidToolchain.ps1','Config/android-toolchain-profile.json','Manage-AndroidToolchain.cmd')){if($required -notin $sealed){throw 'ANDROID_TOOLCHAIN_CAPABILITY_NOT_SEALED'}}
  }
  $python=Find-Tool python.exe @();if(-not $python){throw 'PYTHON_REQUIRED'}
  # Reuse AndroidProvider M2 source admission; never weaken canonical/sealed currentness.
  $admission='import sys,json;sys.path.insert(0,sys.argv[1]);from harness.api.android_provider_cli import admit_source;print(json.dumps(admit_source(sys.argv[2] or None)))'
  $result.source=Invoke-Bounded $python @('-c',$admission,$repo,$ExpectedCommit) 120
 }
 $inventory=Read-Inventory;$result.inventory=$inventory
 if($fixture -and $fixture.PSObject.Properties['reason_codes']){$result.reason_codes+=@($fixture.reason_codes)}
 $missing=@($profile.required_packages|Where-Object {$_ -notin @($inventory.packages)})
 foreach($package in $profile.native_packages){if($package -notin @($inventory.packages)){$missing+=@($package)}}
 if(-not @($inventory.packages|Where-Object {$_.StartsWith('system-images/') -and $_ -match 'x86_64$'}).Count){$missing+=@($profile.system_image_prefix)}
 $result.actions=@($missing|ForEach-Object {@{action='INSTALL_MISSING';package=$_}})
 if(-not $inventory.java -or -not $inventory.javac){$result.reason_codes+=@('MISSING_STANDALONE_JDK')}
 if(-not $inventory.android_cli){$result.reason_codes+=@('MISSING_ANDROID_CLI')}
 if(-not $inventory.studio){$result.reason_codes+=@('MISSING_ANDROID_STUDIO')}
 if($inventory.android_home -and $inventory.android_home.TrimEnd('\','/') -ne $inventory.sdk_root.TrimEnd('\','/')){$result.reason_codes+=@('SDK_ROOT_MISMATCH')}
 if($inventory.studio_sdk_root -and $inventory.studio_sdk_root.TrimEnd('\','/').Replace('\','/') -ne $inventory.sdk_root.TrimEnd('\','/').Replace('\','/')){$result.reason_codes+=@('SDK_STUDIO_MISMATCH')}
 if($Operation -eq 'Verify' -and $missing.Count){$result.reason_codes+=@('SDK_PACKAGES_MISSING')}
 if($Operation -eq 'Verify' -and -not $inventory.sdkmanager){$result.reason_codes+=@('MISSING_SDK_COMMANDLINE_TOOLS')}
 if($Operation -eq 'Verify' -and $inventory.free_gib -lt $profile.minimum_free_gib){$result.reason_codes+=@('INSUFFICIENT_DISK_SPACE')}
 if($Operation -in @('Apply','Repair')){
  if(-not $MutationAuthorized){throw 'MUTATION_AUTHORIZATION_REQUIRED'}
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
  [Environment]::SetEnvironmentVariable('ANDROID_HOME',$SdkRoot,'User');$env:ANDROID_HOME=$SdkRoot
  [Environment]::SetEnvironmentVariable('JAVA_HOME',$jdkRoot,'User');$env:JAVA_HOME=$jdkRoot
  $entries=@((Join-Path $jdkRoot 'bin'))+@($before.PATH -split ';'|Where-Object {$_ -and $_ -ne (Join-Path $jdkRoot 'bin')})
  foreach($entry in @((Join-Path $jdkRoot 'bin'),(Join-Path $SdkRoot 'cmdline-tools/latest/bin'),(Join-Path $SdkRoot 'platform-tools'),(Split-Path $inventory.android_cli -Parent))){if($entry -notin $entries){$entries+=@($entry)}}
  [Environment]::SetEnvironmentVariable('PATH',($entries -join ';'),'User');$env:PATH=((Join-Path $jdkRoot 'bin')+';'+$env:PATH+';'+($entries -join ';'))
  $result.inventory=Read-Inventory
  if(@(($profile.required_packages+$profile.native_packages)|Where-Object {$_ -notin @($result.inventory.packages)}).Count){throw 'INSTALL_READBACK_INCOMPLETE'}
  if(-not @($result.inventory.packages|Where-Object {$_.StartsWith('system-images/') -and $_ -match 'x86_64$'}).Count){throw 'SYSTEM_IMAGE_READBACK_INCOMPLETE'}
  $result.proof+=@('WINDOWS_INSTALLED')
  # Acquisition is separate from independent SAS qualification; own hash is never approval.
  $staging=Join-Path $OutputRoot 'sas-platform-tools-staging';New-Item -ItemType Directory -Force $staging|Out-Null
  $map=Join-Path $staging 'fetch-map.csv'
  @([pscustomobject]@{Name='Android Platform Tools';Url='https://dl.google.com/android/repository/platform-tools-latest-windows.zip';FileName='platform-tools-windows.zip';Type='zip';Version='latest';SilentArgs='';AllowDomains='dl.google.com'})|Export-Csv -NoTypeInformation $map
  if(-not (Test-Path (Join-Path $staging 'installers/platform-tools-windows.zip'))){
   $pwsh=Find-Tool pwsh.exe @('C:/Program Files/PowerShell/7/pwsh.exe');if(-not $pwsh){throw 'POWERSHELL7_FETCHER_REQUIRED'}
   Invoke-Bounded $pwsh @('-NoProfile','-File',(Join-Path $repo 'Config/Fetch-Installers.ps1'),'-RepoRoot',$staging,'-FetchMap',$map)|Out-Null
  }
  try{Invoke-Bounded $python @((Join-Path $repo 'harness/api/android_provider_cli.py'),'verify','--role','ptop_lab') 120|Out-Null;$result.proof+=@('SAS_HOST_READY')}catch{$result.reason_codes+=@('QUALIFICATION_AUTHORITY_REQUIRED')}
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
  if($LaunchStudio){$p=Start-Process $inventory.studio -PassThru -WindowStyle Hidden;Start-Sleep -Seconds 8;$studioProcesses=@(Get-Process studio64 -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $inventory.studio});if(-not $studioProcesses.Count){throw 'STUDIO_LAUNCH_FAILED'};$result.proof+=@('GUI_PROCESS_OBSERVED');if(@($studioProcesses|Where-Object {$_.MainWindowHandle -ne 0 -and $_.MainWindowTitle}).Count){$result.proof+=@('GUI_WINDOW_OBSERVED')}}
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
   $emu=$null
   try{
    # ADB's tcp:PORT syntax binds loopback; hostname syntax is unsupported in 37.0.1.
    Invoke-Bounded $adb @('-L','tcp:5589','--one-device','emulator-5580','start-server') 30|Out-Null
    $listener=@(Get-NetTCPConnection -LocalPort 5589 -State Listen -ErrorAction SilentlyContinue)
    if(-not $listener.Count -or @($listener|Where-Object {$_.LocalAddress -notin @('127.0.0.1','::1')}).Count){throw 'ADB_LOOPBACK_BIND_UNPROVEN'}
    $emu=Start-Process $emulator -ArgumentList @('-avd',$AvdName,'-no-window','-no-audio','-no-snapshot-save','-gpu','swiftshader','-cores','4','-port','5580') -WindowStyle Hidden -PassThru
    $deadline=[datetime]::UtcNow.AddSeconds(300);$booted=$false
    while([datetime]::UtcNow -lt $deadline -and -not $emu.HasExited){try{$boot=Invoke-Bounded $adb @('-P','5589','-s','emulator-5580','shell','getprop','sys.boot_completed') 15;if($boot.Trim() -eq '1'){$booted=$true;break}}catch{if($_.Exception.Message -ne 'COMMAND_FAILED'){throw}};Start-Sleep -Seconds 5}
    if(-not $booted){throw 'EMULATOR_BOOT_FAILED'};$result.proof+=@('EMULATOR_BOOT_VERIFIED')
   }finally{if($emu -and -not $emu.HasExited){try{Invoke-Bounded $adb @('-P','5589','-s','emulator-5580','emu','kill') 15|Out-Null}catch{$result.reason_codes+=@('EMULATOR_CLEANUP_COMMAND_FAILED')};if(-not $emu.WaitForExit(15000)){& "$env:SystemRoot/System32/taskkill.exe" /PID $emu.Id /T /F|Out-Null}};try{Invoke-Bounded $adb @('-P','5589','kill-server') 30|Out-Null}catch{$result.reason_codes+=@('ADB_CLEANUP_FAILED')}finally{$env:ANDROID_ADB_SERVER_PORT=$priorAdbPort;$env:ADB_MDNS_AUTO_CONNECT=$priorMdns;$env:ADB_USB=$priorUsb;$env:ADB_MDNS=$priorMdnsEnabled};if(Get-NetTCPConnection -State Listen -LocalPort 5580,5581,5589 -ErrorAction SilentlyContinue){$result.reason_codes+=@('OWNED_PORT_CLEANUP_INCOMPLETE')}}
  }
  foreach($op in @('status','doctor','verify')){try{Invoke-Bounded $python @((Join-Path $repo 'harness/api/android_provider_cli.py'),$op,'--role','ptop_lab') 120|Out-Null}catch{$result.reason_codes+=@('SAS_PROVIDER_NOT_READY')}}
 }
 if($fixture){$result.proof=@('FIXTURE_ONLY')}
 if($Operation -in @('Inventory','Plan')){$result.result='SUCCESS'}elseif(-not $result.reason_codes.Count){$result.result='SUCCESS'}
}catch{$result.reason_codes+=@($_.Exception.Message);$result.result='BLOCK'}
$result.reason_codes=@($result.reason_codes|Select-Object -Unique)
$receipt=Join-Path $OutputRoot ('receipt-'+[datetime]::UtcNow.ToString('yyyyMMddTHHmmssfffffff')+'.json')
$result|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $receipt -Encoding UTF8
Write-Output ($result|ConvertTo-Json -Depth 12)
if($result.result -ne 'SUCCESS'){exit 2}
