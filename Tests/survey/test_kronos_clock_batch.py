"""Exercise the Kronos batch entry point with isolated, synthetic CSVs."""
import csv
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
COLLECTOR = ROOT / "GetInfo" / "Get-KronosClockInfo.ps1"
POWERSHELL = shutil.which("pwsh") or shutil.which("powershell.exe")


@unittest.skipUnless(POWERSHELL, "PowerShell is required for the Kronos fixture")
class KronosClockBatchTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="sas kronos fixture ")
        self.addCleanup(temporary.cleanup)
        self.folder = Path(temporary.name)
        self.output = self.folder / "reports"

    def csv(self, name, headers, records):
        path = self.folder / (name + ".csv")
        with path.open("w", newline="", encoding="utf-8-sig") as stream:
            writer = csv.writer(stream)
            writer.writerow(headers)
            writer.writerows(records)
        return path

    def powershell(self, *arguments, script=COLLECTOR, input_text=None, env=None):
        flags = ["-NoLogo", "-NoProfile"]
        if input_text is None:
            flags.append("-NonInteractive")
        return subprocess.run(
            [POWERSHELL, *flags, "-File", str(script), *map(str, arguments)],
            cwd=self.folder,
            input=input_text,
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )

    def run_batch(self, request, *arguments):
        result = self.powershell(
            "-RequestPath", request, "-BatchOutputDirectory", self.output, *arguments
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        reports = list(self.output.glob("*/KronosClockBatch.csv"))
        self.assertEqual(len(reports), 1, result.stdout)
        csv_path = reports[0]
        with csv_path.open(newline="", encoding="utf-8-sig") as stream:
            rows = list(csv.DictReader(stream))
        return rows, csv_path.with_suffix(".html").read_text("utf-8-sig")

    def test_sparse_assignments_join_inventory_and_dhcp_without_inventing_live_state(self):
        request = self.csv("assignments", ("HostName", "MACAddress", "SerialNumber"), [
            ("clock-a", "02-00-00-00-00-11", "CASE-A"),
            ("", "", "CASE-B"),
            ("", "020000000013", ""),
        ])
        inventory = self.csv("inventory", ("HostName", "IPAddress", "MACAddress",
                                           "SerialNumber", "DeviceName", "Reachable"), [
            ("clock-a.example.test", "192.0.2.11", "02:00:00:00:00:11", "CASE-A",
             "<script>synthetic</script>", "True"),
            ("clock-b.example.test", "192.0.2.12", "02:00:00:00:00:12", "CASE-B",
             "Clock B", "True"),
            ("clock-c.example.test", "192.0.2.13", "", "CASE-C", "Clock C", "True"),
        ])
        lease = self.csv("leases", ("HostName", "IPAddress", "ClientId", "ScopeId", "AddressState"), [
            ("clock-a.example.test", "192.0.2.11", "02-00-00-00-00-11", "192.0.2.0",
             "ActiveReservation"),
            ("clock-b.example.test", "192.0.2.12", "02-00-00-00-00-12", "192.0.2.0", "Active"),
            ("clock-c.example.test", "192.0.2.13", "02-00-00-00-00-13", "192.0.2.0", "Active"),
        ])
        scope = self.csv("scopes", ("ScopeId", "SubnetMask", "DefaultGateway"), [
            ("192.0.2.0", "255.255.255.0", "192.0.2.1"),
            ("198.51.100.0", "255.255.255.0", "198.51.100.1"),
        ])
        reservation = self.csv("reservations", ("IPAddress", "ClientId", "ScopeId"), [
            ("192.0.2.11", "02-00-00-00-00-11", "192.0.2.0"),
        ])
        rows, html = self.run_batch(
            request, "-ClockInventoryPath", inventory, "-LeasePath", lease,
            "-ScopePath", scope, "-ReservationPath", reservation,
        )

        self.assertEqual([row["Row"] for row in rows], ["1", "2", "3"])
        self.assertEqual([row["Status"] for row in rows], ["Complete"] * 3)
        self.assertEqual([row["IPAddress"] for row in rows],
                         ["192.0.2.11", "192.0.2.12", "192.0.2.13"])
        self.assertEqual([row["SerialNumber"] for row in rows], ["CASE-A", "CASE-B", "CASE-C"])
        self.assertEqual({row["SubnetMask"] for row in rows}, {"255.255.255.0"})
        self.assertEqual({row["DefaultGateway"] for row in rows}, {"192.0.2.1"})
        self.assertEqual({row["Reachability"] for row in rows}, {"Not checked"})
        self.assertIn("IPAddress = Clock inventory", rows[0]["Sources"])
        self.assertIn("SubnetMask = DHCP scope export", rows[0]["Sources"])
        self.assertEqual(rows[0]["Reservation"], "Reported by export")
        self.assertEqual(rows[1]["Reservation"], "Unknown")
        self.assertEqual(rows[1]["DHCPState"], "Active")
        self.assertIn("3 Complete", html)
        self.assertIn("&lt;script&gt;synthetic&lt;/script&gt;", html)
        self.assertNotIn("<script>synthetic</script>", html)

    def test_reports_ambiguity_conflict_and_invalid_inputs_without_picking_a_clock(self):
        request = self.csv("assignments", ("HostName", "MACAddress", "SerialNumber", "IPAddress",
                                           "SubnetMask"), [
            ("clock", "", "", "", ""),
            ("clock", "", "CASE-A", "", ""),
            ("", "", "CASE-B", "192.0.2.11", ""),
            ("", "01:02:00:00:00:00:11", "", "", ""),
            ("", "", "", "", "255.255.255.0"),
        ])
        inventory = self.csv("inventory", ("HostName", "IPAddress", "MACAddress", "SerialNumber",
                                           "SubnetMask"), [
            ("clock.first.example.test", "192.0.2.11", "02:00:00:00:00:11", "CASE-A", "255.255.255.0"),
            ("clock.second.example.test", "192.0.2.12", "02:00:00:00:00:12", "CASE-B", "255.255.255.0"),
        ])
        rows, html = self.run_batch(request, "-ClockInventoryPath", inventory)

        self.assertEqual([row["Status"] for row in rows],
                         ["Review evidence", "Complete", "Review evidence",
                          "Invalid input", "Review evidence"])
        self.assertIn("Ambiguous", rows[0]["Notes"])
        self.assertFalse(rows[0]["IPAddress"])
        self.assertEqual(rows[1]["IPAddress"], "192.0.2.11")
        self.assertIn("Conflict", rows[2]["Notes"])
        self.assertFalse(rows[2]["MACAddress"])
        self.assertIn("MACAddress", rows[3]["Notes"])
        self.assertFalse(rows[3]["MACAddress"])
        self.assertIn("Ambiguous", rows[4]["Notes"])
        self.assertFalse(rows[4]["IPAddress"])
        self.assertIn("3 Review evidence", html)

    def test_mismatched_dhcp_reservation_does_not_confirm_either_clock(self):
        request = self.csv("assignments", ("IPAddress", "MACAddress"), [
            ("192.0.2.11", "02:00:00:00:00:11"),
        ])
        reservations = self.csv("reservations", ("IPAddress", "ClientId", "ScopeId"), [
            ("192.0.2.11", "02:00:00:00:00:22", "192.0.2.0"),
        ])
        rows, _ = self.run_batch(request, "-ReservationPath", reservations)

        self.assertEqual(rows[0]["Status"], "Review evidence")
        self.assertEqual(rows[0]["Reservation"], "Unknown")
        self.assertIn("Conflict", rows[0]["Notes"])

    def test_csv_neutralizes_formula_cells_while_html_preserves_labels(self):
        request = self.csv("assignments", ("SerialNumber",), [("CASE-A",)])
        formula = '=HYPERLINK("https://example.invalid","synthetic")'
        inventory = self.csv(
            "inventory", ("SerialNumber", "DeviceName", "Model", "DeviceID"),
            [("CASE-A", formula, "+Model", "@Terminal")],
        )

        rows, html = self.run_batch(request, "-ClockInventoryPath", inventory)

        self.assertEqual(rows[0]["DeviceName"], "'" + formula)
        self.assertEqual(rows[0]["Model"], "'+Model")
        self.assertEqual(rows[0]["DeviceID"], "'@Terminal")
        self.assertIn('>=HYPERLINK(&quot;https://example.invalid&quot;,&quot;synthetic&quot;)</td>', html)
        self.assertIn(">+Model</td>", html)
        self.assertIn(">@Terminal</td>", html)

    def test_ip_only_reservation_without_client_identity_is_ignored(self):
        request = self.csv("assignments", ("IPAddress",), [("192.0.2.11",)])
        reservations = self.csv("reservations", ("IPAddress", "ClientId", "ScopeId"), [
            ("192.0.2.11", "", "192.0.2.0"),
        ])

        rows, _ = self.run_batch(request, "-ReservationPath", reservations)

        self.assertEqual(rows[0]["Status"], "Incomplete")
        self.assertEqual(rows[0]["Reservation"], "Unknown")
        self.assertFalse(rows[0]["ScopeId"])
        self.assertNotIn("DHCP reservation export", rows[0]["Sources"])

    def test_unique_lease_cannot_overrule_conflicting_clock_hostnames(self):
        request = self.csv("assignments", ("HostName",), [("clock",)])
        inventory = self.csv("inventory", ("HostName", "IPAddress", "SerialNumber"), [
            ("clock.first.example.test", "192.0.2.11", "CASE-A"),
            ("clock.second.example.test", "192.0.2.12", "CASE-B"),
        ])
        leases = self.csv("leases", ("HostName", "IPAddress", "ClientId", "ScopeId"), [
            ("clock.first.example.test", "192.0.2.11", "02-00-00-00-00-11", "192.0.2.0"),
        ])

        rows, _ = self.run_batch(request, "-ClockInventoryPath", inventory, "-LeasePath", leases)

        self.assertEqual(rows[0]["Status"], "Review evidence")
        self.assertIn("Ambiguous", rows[0]["Notes"])
        self.assertFalse(rows[0]["IPAddress"])
        self.assertFalse(rows[0]["SerialNumber"])

    def test_missing_inventory_mask_cannot_make_a_shared_subnet_unique(self):
        request = self.csv("assignments", ("SubnetMask",), [("255.255.255.0",)])
        inventory = self.csv("inventory", ("IPAddress", "SerialNumber", "SubnetMask"), [
            ("192.0.2.11", "CASE-A", "255.255.255.0"),
            ("192.0.2.12", "CASE-B", ""),
        ])
        scopes = self.csv("scopes", ("ScopeId", "SubnetMask"), [
            ("192.0.2.0", "255.255.255.0"),
        ])

        rows, _ = self.run_batch(request, "-ClockInventoryPath", inventory, "-ScopePath", scopes)

        self.assertIn(rows[0]["Status"], ("Review evidence", "Incomplete"))
        self.assertFalse(rows[0]["IPAddress"])
        self.assertFalse(rows[0]["SerialNumber"])

    def test_live_mode_requires_approved_scope_input_before_any_report(self):
        request = self.csv("assignments", ("IPAddress",), [("192.0.2.11",)])
        result = self.powershell(
            "-RequestPath", request, "-BatchOutputDirectory", self.output, "-Live",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("site DHCP scope CSV", result.stdout + result.stderr)
        self.assertFalse(self.output.exists())

    def test_live_scope_gate_and_probe_cache_with_network_adapters_replaced(self):
        request = self.csv("assignments", ("IPAddress", "HostName"), [
            ("192.0.2.11", ""),
            ("192.0.2.11", ""),
            ("198.51.100.11", ""),
            ("192.0.2.255", ""),
            ("", "unverified"),
            ("", "known"),
            ("", "known"),
            ("", "offdomain.example.invalid"),
        ])
        scopes = self.csv("scopes", ("ScopeId", "SubnetMask"), [
            ("192.0.2.0", "255.255.255.0"),
        ])
        inventory = self.csv("inventory", ("HostName", "IPAddress", "SerialNumber"), [
            ("known.example.test", "192.0.2.12", "CASE-A"),
        ])
        fixture = self.folder / "network-doubles.ps1"
        fixture.write_text(r'''
param($ModulePath, $Request, $Scopes, $Inventory)
$ErrorActionPreference = 'Stop'
$module = Import-Module $ModulePath -PassThru
& $module {
    param($Request, $Scopes, $Inventory)
    $script:SyntheticDns = @()
    $script:SyntheticPings = @()
    function script:Resolve-KronosIPv4 {
        param($HostName)
        $script:SyntheticDns += $HostName
        switch ($HostName) {
            'known.example.test' { '192.0.2.12' }
            'unverified.example.test' { '192.0.2.13' }
            default { throw "Unexpected DNS lookup: $HostName" }
        }
    }
    function script:Test-KronosResponse {
        param($IPAddress)
        $script:SyntheticPings += $IPAddress
        switch ($IPAddress) {
            '192.0.2.11' { 'Responded to ICMP' }
            '192.0.2.12' { 'No ICMP reply' }
            default { throw "Unexpected ICMP probe: $IPAddress" }
        }
    }
    $rows = @(Get-KronosBatchReport -RequestPath $Request -InventoryPath $Inventory `
        -ScopePath $Scopes -DnsDomain 'example.test' -Live)
    @{
        Rows = $rows
        Dns = $script:SyntheticDns
        Pings = $script:SyntheticPings
    } | ConvertTo-Json -Depth 8 -Compress
} $Request $Scopes $Inventory
''', encoding="utf-8")
        result = self.powershell(
            COLLECTOR.with_name("KronosClockBatch.psm1"), request, scopes, inventory, script=fixture,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        receipt = json.loads(result.stdout)
        self.assertEqual(receipt["Pings"], ["192.0.2.11", "192.0.2.12"])
        self.assertEqual(receipt["Dns"], ["unverified.example.test", "known.example.test"])
        rows = receipt["Rows"]
        self.assertEqual([row["Reachability"] for row in rows], [
            "Responded to ICMP", "Responded to ICMP", "Not checked", "Not checked",
            "Not checked", "No ICMP reply", "No ICMP reply", "Not checked",
        ])
        self.assertIn("site scopes", rows[2]["Notes"])
        self.assertIn("usable host", rows[3]["Notes"])
        self.assertIn("inventory match", rows[4]["Notes"])
        self.assertIn("approved DNS suffix", rows[7]["Notes"])

    def test_technician_prompt_runs_from_outside_checkout(self):
        self.csv("ClockInventory", ("SerialNumber", "IPAddress", "HostName", "MACAddress"), [
            ("CASE-A", "192.0.2.11", "clock-a.example.test", "02:00:00:00:00:11"),
        ])
        self.csv("DhcpScopes", ("ScopeId", "SubnetMask"), [
            ("192.0.2.0", "255.255.255.0"),
        ])
        profile = self.folder / "profile"
        environment = os.environ.copy()
        environment["LOCALAPPDATA"] = str(profile)
        result = self.powershell(
            "-NoOpen", script=COLLECTOR.with_name("Start-KronosClockBatch.ps1"),
            input_text=str(self.folder) + "\nSerialNumber=CASE-A\n\n", env=environment,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Saved HTML", result.stdout)
        reports = list(profile.glob("SysAdminSuite/Evidence/KronosClock/*/KronosClockBatch.html"))
        self.assertEqual(len(reports), 1, result.stdout)
        self.assertIn("CASE-A", reports[0].read_text("utf-8-sig"))

    def test_legacy_inventory_lookup_and_custom_html_path_still_work(self):
        inventory = self.csv("legacy", ("IPAddress", "HostName", "MACAddress", "SerialNumber"), [
            ("192.0.2.11", "clock-a", "02-00-00-00-00-11", "CASE-A"),
            ("192.0.2.12", "clock-b", "02-00-00-00-00-12", "CASE-B"),
        ])
        report = self.folder / "clock lookup.html"
        result = self.powershell(
            "-InventoryPath", inventory, "-LookupBy", "MAC", "-LookupValue", "02:00:00:00:00:11",
            "-OutHtml", report,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        html = report.read_text("utf-8-sig")
        self.assertIn("CASE-A", html)
        self.assertNotIn("CASE-B", html)


if __name__ == "__main__":
    unittest.main()
