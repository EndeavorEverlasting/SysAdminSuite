"""Prepare once, then exercise portable CMD without a target SDK or checkout."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SDK = Path(os.environ.get('ProgramFiles(x86)', 'missing')) / 'Windows Kits/10/UnionMetadata'


@unittest.skipUnless(os.name == 'nt' and SDK.exists(), 'Windows SDK preparation host required')
class PortableBluetoothCliTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='SAS portable fixture ')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.folder = Path(cls.temp.name)
        cls.bundle = cls.folder / 'prepared runtime'
        result = cls.invoke(ROOT / 'SasBluetooth.cmd', 'prepare', '-Destination', str(cls.bundle))
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)

    @classmethod
    def invoke(cls, entry, *args, env=None):
        return subprocess.run([os.environ.get('ComSpec', 'cmd.exe'), '/d', '/c', 'call',
            str(entry), *args], cwd=cls.folder, env=env, capture_output=True, text=True, timeout=35)

    def test_prepared_cmd_lists_mappings_without_target_sdk(self):
        env = dict(os.environ)
        env['ProgramFiles(x86)'] = str(self.folder / 'no SDK here')
        result = self.invoke(self.bundle / 'SasBluetooth.cmd', 'capabilities', env=env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(json.loads(result.stdout)['PreparedRuntimePresent'])
        result = self.invoke(self.bundle / 'SasBluetooth.cmd', 'list', env=env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        mappings = json.loads(result.stdout)
        self.assertIsInstance(mappings, list)
        for mapping in mappings:
            self.assertTrue(mapping['Paired'])
            self.assertIn(mapping['State'], ('PAIRED_CONNECTED', 'PAIRED_DISCONNECTED', 'PAIRED_CONNECTION_UNKNOWN'))

    def test_bundle_drift_is_rejected_before_runtime_use(self):
        copy = self.folder / 'drifted runtime'
        shutil.copytree(self.bundle, copy)
        with (copy / 'runtime/SasBluetoothPairing.dll').open('ab') as stream:
            stream.write(b'synthetic drift')
        result = self.invoke(copy / 'SasBluetooth.cmd', 'capabilities')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('BUNDLE_HASH_MISMATCH', json.loads(result.stdout)['Error'])


if __name__ == '__main__':
    unittest.main()
