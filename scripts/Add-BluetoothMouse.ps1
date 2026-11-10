[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ExactName)
$ErrorActionPreference='Stop'
# Use Windows PowerShell/.NET Framework and an installed Windows SDK only.
# Preparation compiles locally; no software is downloaded or installed.
$run=Join-Path $env:LOCALAPPDATA ('SysAdminSuite\Evidence\Bluetooth\pair-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $run -Force | Out-Null
try {
    $winmd=@(Get-ChildItem -Path "${env:ProgramFiles(x86)}\Windows Kits\10\UnionMetadata\*\Windows.winmd" -ErrorAction SilentlyContinue | Where-Object {$_.Directory.Name -match '^\d+\.\d+\.\d+\.\d+$'} | Sort-Object @{e={[version]$_.Directory.Name}} -Descending | Select-Object -First 1)
    if($winmd.Count -ne 1){throw 'Installed Windows SDK Windows.winmd required for native pairing. Use Windows Add a device if unavailable.'}
    $framework=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319'
    $gac=Join-Path $env:SystemRoot 'Microsoft.NET\assembly\GAC_MSIL'
    $dll=Join-Path $run 'SasBluetoothPairing.dll'
    $references=@(
        $winmd[0].FullName,
        (Join-Path $framework 'System.Runtime.WindowsRuntime.dll'),
        (Join-Path $gac 'System.Runtime\v4.0_4.0.0.0__b03f5f7f11d50a3a\System.Runtime.dll'),
        (Join-Path $gac 'System.Runtime.InteropServices.WindowsRuntime\v4.0_4.0.0.0__b03f5f7f11d50a3a\System.Runtime.InteropServices.WindowsRuntime.dll')
    )
    foreach($reference in $references){if(-not (Test-Path -LiteralPath $reference)){throw 'Native pairing prerequisite missing.'}}
    $compilerArgs=@('/nologo','/target:library',('/out:'+$dll))+@($references | ForEach-Object {'/r:'+$_})+@(Join-Path $PSScriptRoot 'SasBluetoothPairing.cs')
    $compile=& (Join-Path $framework 'csc.exe') @compilerArgs 2>&1
    $compile | Set-Content -LiteralPath (Join-Path $run 'compile.txt')
    if($LASTEXITCODE -ne 0){throw 'Native pairing helper compilation failed; inspect private compile.txt.'}
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    Add-Type -Path $dll
    $result=[SasBluetoothPairing]::Run($ExactName).GetAwaiter().GetResult()
    [ordered]@{Target=$ExactName;Result=$result;MouseMovementConfirmed=$false;Evidence=$run} | ConvertTo-Json | Tee-Object -FilePath (Join-Path $run 'result.json')
    if($result -notin 'PAIRING_RESULT=Paired','ALREADY_PAIRED'){exit 1}
} catch {
    @{Target=$ExactName;Result='FAILED';Error=$_.Exception.Message} | ConvertTo-Json | Tee-Object -FilePath (Join-Path $run 'result.json')
    exit 1
}
