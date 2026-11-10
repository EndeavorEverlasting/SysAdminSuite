"""Execute the read-only recovery path against synthetic Windows cmdlet doubles."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import shutil

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(os.name == 'nt', 'Windows PowerShell fixture')
class BluetoothRecoveryTests(unittest.TestCase):
    def run_fixture(self, preference, drift=False, action='Inspect', service_mode='Stopped', service_count=1, service_name=''):
        with tempfile.TemporaryDirectory() as folder:
            temp = Path(folder)
            wrapper = temp / 'fixture.ps1'
            source = ROOT / 'scripts/Invoke-BluetoothPeripheralRecovery.ps1'
            if action == 'PairFlow':
                scripts = temp / 'scripts'
                scripts.mkdir()
                for name in ('SasBluetooth.ps1', 'Invoke-BluetoothPeripheralRecovery.ps1'):
                    shutil.copyfile(ROOT / 'scripts' / name, scripts / name)
                (scripts / 'SasBluetoothRuntime.psm1').write_text('# Synthetic dispatcher fixture\n')
                (scripts / 'Add-BluetoothMouse.ps1').write_text(
                    "param($ExactName,$DeviceId)\nSet-Content (Join-Path $PSScriptRoot '..\\pair-called.txt') $ExactName\nexit 0\n")
                source = scripts / 'SasBluetooth.ps1'
            wrapper.write_text(r'''
param($Source,$OutputRoot,$Preference,[int]$Drift,$Action,$ServiceMode,[int]$ServiceCount,$ServiceName)
$global:reads=0
$global:fixtureDrift=$Drift
$global:fixturePreference=$Preference
$global:starts=0
$global:serviceMode=$ServiceMode
$global:fixtureServices=@(for($n=1;$n -le $ServiceCount;$n++) {
    $service=[pscustomobject]@{Name=('BluetoothUserService_0'+$n);Status=if($ServiceMode -eq 'Running'){'Running'}else{'Stopped'};StartType=if($ServiceMode -eq 'Disabled'){'Disabled'}else{'Manual'}}
    $service|Add-Member ScriptMethod WaitForStatus {param($state,$timeout) $this.Status=[string]$state}
    $service
})
function Get-Item {
    param($LiteralPath)
    if($LiteralPath -ne 'HKCU:\Control Panel\Keyboard'){throw 'Unexpected registry read'}
    $global:reads++
    $value=if($global:fixtureDrift -and $global:reads -ge 3){'1'}else{$global:fixturePreference}
    $item=[pscustomobject]@{FixtureValue=$value}
    $item | Add-Member ScriptMethod GetValueNames {if($this.FixtureValue -ne 'absent'){'PrintScreenKeyForSnippingEnabled'}}
    $item | Add-Member ScriptMethod GetValue {param($name) [int]$this.FixtureValue}
    return $item
}
function Get-PnpDevice {
    param([switch]$PresentOnly,$Class)
    [pscustomobject]@{Class='Bluetooth';Status='OK';FriendlyName='Synthetic radio';InstanceId='USB\SYNTHETIC'}
}
function Get-Service {
    param($Name)
    if(@($Name).Count -gt 1){[pscustomobject]@{Name='bthserv';Status='Running';StartType='Manual'}; $global:fixtureServices}
    elseif($Name -eq 'bthserv'){[pscustomobject]@{Name='bthserv';Status='Running';StartType='Manual'}}
    else {$global:fixtureServices}
}
function Start-Service {
    param($Name)
    if($global:serviceMode -eq 'Denied'){throw [UnauthorizedAccessException]::new('Synthetic delegated-rights denial')}
    $global:starts++
    ($global:fixtureServices|Where-Object {$_.Name -eq $Name}).Status='Running'
}
function Set-ItemProperty {throw 'Recovery must not rewrite screenshot preferences'}
function Remove-ItemProperty {throw 'Recovery must not delete screenshot preferences'}
if($Action -eq 'PairFlow') {
    $env:LOCALAPPDATA=Split-Path $OutputRoot -Parent
    & $Source pair -ExactName 'Synthetic Mouse'
} else { & $Source -OutputRoot $OutputRoot -Action $Action -ServiceName $ServiceName }
$code=$LASTEXITCODE
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$global:starts | Set-Content (Join-Path $OutputRoot 'fixture-starts.txt')
exit $code
''', encoding='utf-8')
            result = subprocess.run(
                ['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(wrapper),
                 '-Source', str(source),
                 '-OutputRoot', str(temp / 'evidence'), '-Preference', preference,
                 '-Drift', str(int(drift)), '-Action', action, '-ServiceMode', service_mode,
                 '-ServiceCount', str(service_count), '-ServiceName', service_name], capture_output=True, text=True, timeout=25)
            receipts = list(temp.rglob('result.json'))
            self.assertEqual(len(receipts), 1, result.stdout + result.stderr)
            receipt = json.loads(receipts[0].read_text(encoding='utf-8-sig'))
            receipt['_starts'] = int((temp / 'evidence/fixture-starts.txt').read_text(encoding='utf-8-sig'))
            receipt['_pair_called'] = (temp / 'pair-called.txt').exists()
            return result, receipt

    def test_inspect_preserves_absence_and_both_preference_values(self):
        for preference in ('absent', '0', '1'):
            with self.subTest(preference=preference):
                result, receipt = self.run_fixture(preference)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse(receipt['MouseVerified'])
                self.assertIsNone(receipt['Error'])
                self.assertEqual(receipt['_starts'], 0)

    def test_preference_drift_fails_without_rewriting_it(self):
        result, receipt = self.run_fixture('0', drift=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(receipt['Status'], 'FAILED')
        self.assertIn('REGRESSION', receipt['Error'])

    def test_service_start_uses_existing_rights_and_is_idempotent(self):
        result, receipt = self.run_fixture('absent', action='StartUserService')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(receipt['_starts'], 1)
        result, receipt = self.run_fixture('absent', action='StartUserService', service_mode='Running')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(receipt['_starts'], 0)

    def test_denied_start_reports_elevation_without_changing_policy(self):
        result, receipt = self.run_fixture('absent', action='StartUserService', service_mode='Denied')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(receipt['Status'], 'REQUIRES_ELEVATION')
        self.assertEqual(receipt['_starts'], 0)

    def test_multiple_sessions_require_exact_selection(self):
        result, receipt = self.run_fixture('0', action='StartUserService', service_count=2)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(receipt['_starts'], 0)
        result, receipt = self.run_fixture('0', action='StartUserService', service_count=2,
                                           service_name='BluetoothUserService_02')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(receipt['_starts'], 1)

    def test_disabled_service_does_not_get_reconfigured(self):
        result, receipt = self.run_fixture('0', action='StartUserService', service_mode='Disabled')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(receipt['_starts'], 0)

    def test_fresh_dispatcher_pairs_after_successful_service_recovery(self):
        result, receipt = self.run_fixture('absent', action='PairFlow')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(receipt['_pair_called'])
        self.assertEqual(receipt['_starts'], 1)


if __name__ == '__main__':
    unittest.main()
