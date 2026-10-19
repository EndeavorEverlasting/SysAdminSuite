"""Static safety/compatibility contract for Northwell printer fallback.

This suite NEVER reaches a printer, registry, SMB share, Task Scheduler or Startup.
Successful tests only prove static implementation contracts, NOT field readiness.
"""
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
ENDPOINT = ROOT / "mapping/SessionFallback/Invoke-NorthwellPrinterSession.ps1"
STAGER = ROOT / "mapping/SessionFallback/Stage-NorthwellPrinterSession.ps1"
CMD = ROOT / "Recover-NorthwellPrinter-Session.cmd"
MODES = ROOT / "harness/api/northwell-printer-session-fallback-modes.v1.json"
DOWNLOAD = ROOT / "docs/field/NORTHWELL-PRINTER-DOWNLOAD.html"


class SessionFallbackContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.endpoint = ENDPOINT.read_text(encoding="utf-8")
        cls.stager = STAGER.read_text(encoding="utf-8")
        cls.cmd = CMD.read_text(encoding="utf-8")
        cls.modes = json.loads(MODES.read_text(encoding="utf-8"))

    def test_closed_organization_mode_contract(self):
        self.assertEqual(self.modes["use_case_id"], "northwell.shared-printer.organization-default")
        by_id = {x["id"]: x for x in self.modes["modes"]}
        self.assertEqual(set(by_id), {f"M{i}" for i in range(1, 7)})
        self.assertEqual(by_id["M4"]["status"], "implemented_uncertified")
        self.assertEqual(by_id["M5"]["status"], "implemented_uncertified")
        self.assertEqual(by_id["M6"]["status"], "implemented_uncertified_policy_gated")
        self.assertTrue(self.modes["mandatory_registration"]["proof"])

    def test_proven_machine_registration_is_first_authority(self):
        self.assertIn("Assert-SasNorthwellPrinterStatusProof", self.stager)
        self.assertIn("Assert-SasMachineProof", self.endpoint)
        self.assertIn("MachineWideUNC", (ROOT / "mapping/Modules/NorthwellPrinterMapping.Core.psm1").read_text(encoding="utf-8"))
        self.assertIn("Registry::HKEY_LOCAL_MACHINE", self.endpoint)
        self.assertIn("Print\\Connections", self.endpoint)

    def test_actual_user_connection_and_receipts_gate_success(self):
        self.assertIn("Registry::HKEY_CURRENT_USER\\Printers\\Connections", self.endpoint)
        self.assertIn("Test-SasSessionProof", self.endpoint)
        self.assertIn("ReceiptToken", self.endpoint)
        self.assertIn("USER_SESSION_VERIFIED", self.endpoint)
        self.assertIn("HKU", self.endpoint)
        self.assertIn("Get-FileHash", self.endpoint)
        self.assertLess(self.endpoint.index("if (-not $verified) { throw 'Printer session"), self.endpoint.index("$receiptKey ="))
        self.assertLess(self.endpoint.index("if ($null -eq $successSid)"), self.endpoint.index("Remove-Item -LiteralPath $startupPath"))

    def test_runner_refuses_system_user_and_cleanup_refuses_standard_user(self):
        self.assertIn("if ($identity.IsSystem)", self.endpoint)
        self.assertIn("CleanupOnce requires SYSTEM", self.endpoint)
        self.assertIn("Startup helper is retained", self.endpoint)

    def test_deferred_is_group_logon_and_cleanup_is_system_logon(self):
        self.assertIn("S-1-5-32-545", self.stager)
        self.assertIn("New-SasSharelessLogonTask", self.stager)
        self.assertIn("NorthwellPrinterBatch", self.stager)
        self.assertIn("Exactly one canonical Status.json", self.stager)
        self.assertIn("TASK_LOGON_GROUP", self.stager)
        self.assertIn("TASK_LOGON_SERVICE_ACCOUNT", self.stager)
        self.assertIn("TASK_TRIGGER_LOGON", self.stager)
        self.assertIn("Get-SasKnownCommonStartup", self.stager)
        self.assertIn("StartupSha256", self.stager)
        self.assertIn("RegisterTaskDefinition", self.stager)
        self.assertIn("DeleteTask", self.endpoint)
        self.assertIn("ApprovalTicket", self.stager)
        self.assertIn("Persistent fallback requires a client-approved", self.stager)
        self.assertIn("Remove-Item -LiteralPath $startupPath", self.endpoint)

    def test_user_must_explicitly_authorize_staging_and_removal(self):
        self.assertIn("-Plan", self.cmd)
        self.assertIn('Type APPLY', self.cmd)
        self.assertIn('Type RETIRE', self.cmd)
        self.assertIn("if (-not $Apply)", self.stager)
        self.assertIn("if ($Plan)", self.stager)
        self.assertIn("Existing fallback staged", self.stager)

    def test_no_policy_weakening_or_direct_ip_password_fallback(self):
        source = self.endpoint + self.stager
        for forbidden in (
            r"\bAdd-Printer\s+-ConnectionName",
            r"\bPrintTestPage\b",
            r"Set-ExecutionPolicy",
            r"RestrictDriverInstallationToAdministrators\s*=",
            r"\bGet-Credential\b",
            r"\bNew-LocalUser\b",
            r"\bSet-Printer\b",
            r"\bnet\s+user\b",
        ):
            self.assertIsNone(re.search(forbidden, source, re.I), forbidden)

    def test_field_page_is_a_download_not_unapproved_autoexecution(self):
        page = DOWNLOAD.read_text(encoding="utf-8")
        self.assertIn("github.com/EndeavorEverlasting/SysAdminSuite", page)
        self.assertIn("Recover-NorthwellPrinter-Session.cmd", page)
        self.assertIn("Map-NorthwellPrinter.cmd", page)
        self.assertNotIn("powershell -enc", page.lower())
        self.assertIn("not yet field-certified", page.lower())


if __name__ == "__main__":
    unittest.main()
