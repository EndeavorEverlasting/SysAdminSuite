"""Execute the read-only recovery path against synthetic Windows cmdlet doubles."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(os.name == 'nt', 'Windows PowerShell fixture')
class BluetoothRecoveryTests(unittest.TestCase):
    def run_fixture(self, preference, drift=False):
        with tempfile.TemporaryDirectory() as folder:
            temp = Path(folder)
            wrapper = temp / 'fixture.ps1'
            wrapper.write_text(r'''
param($Source,$OutputRoot,$Preference,[int]$Drift)
$global:reads=0
$global:fixtureDrift=$Drift
$global:fixturePreference=$Preference
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
    [pscustomobject]@{Name='BluetoothUserService_fixture';Status='Stopped';StartType='Manual'}
}
function Start-Service {throw 'Inspect must not start services'}
function Set-ItemProperty {throw 'Recovery must not rewrite screenshot preferences'}
function Remove-ItemProperty {throw 'Recovery must not delete screenshot preferences'}
& $Source -OutputRoot $OutputRoot
exit $LASTEXITCODE
''', encoding='utf-8')
            result = subprocess.run(
                ['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(wrapper),
                 '-Source', str(ROOT / 'scripts/Invoke-BluetoothPeripheralRecovery.ps1'),
                 '-OutputRoot', str(temp / 'evidence'), '-Preference', preference,
                 '-Drift', str(int(drift))], capture_output=True, text=True, timeout=25)
            receipts = list((temp / 'evidence').glob('*/result.json'))
            self.assertEqual(len(receipts), 1, result.stdout + result.stderr)
            receipt = json.loads(receipts[0].read_text(encoding='utf-8-sig'))
            return result, receipt

    def test_inspect_preserves_absence_and_both_preference_values(self):
        for preference in ('absent', '0', '1'):
            with self.subTest(preference=preference):
                result, receipt = self.run_fixture(preference)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse(receipt['MouseVerified'])
                self.assertIsNone(receipt['Error'])

    def test_preference_drift_fails_without_rewriting_it(self):
        result, receipt = self.run_fixture('0', drift=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(receipt['Status'], 'FAILED')
        self.assertIn('REGRESSION', receipt['Error'])


if __name__ == '__main__':
    unittest.main()
