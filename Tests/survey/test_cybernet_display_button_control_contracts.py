#!/usr/bin/env python3
"""Dependency-free contracts for the Cybernet MCCS 2.2 display-button lane."""

from pathlib import Path
import re
import unittest


REPO = Path(__file__).resolve().parents[2]
CSHARP = REPO / "scripts" / "SasDdcciMonitorControl.cs"
ORCHESTRATOR = REPO / "scripts" / "Invoke-SasCybernetDisplayButtonControl.ps1"
DOC = REPO / "docs" / "CYBERNET_POWER_HARDENING.md"
WORKFLOW = REPO / ".github" / "workflows" / "cybernet-display-button-control.yml"


class CybernetDisplayButtonContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.csharp = CSHARP.read_text(encoding="utf-8")
        cls.orchestrator = ORCHESTRATOR.read_text(encoding="utf-8")
        cls.doc = DOC.read_text(encoding="utf-8")

    def test_required_surfaces_exist(self) -> None:
        for path in (CSHARP, ORCHESTRATOR, DOC):
            self.assertTrue(path.is_file(), path)

    def test_protocol_constants_are_explicit(self) -> None:
        self.assertIn("MccsVersionCode = 0xDF", self.csharp)
        self.assertIn("OsdButtonControlCode = 0xCA", self.csharp)
        self.assertIn("LockedButtonValue = 0x0303", self.csharp)
        self.assertIn("VCP_CA_V22_BUTTON_LOCK_READY", self.csharp)
        self.assertIn("MCCS_PRE_2_2_OSD_ONLY", self.csharp)

    def test_mutation_is_read_before_write_and_verified(self) -> None:
        read_index = self.csharp.index("Probe(index, monitors[index])")
        set_index = self.csharp.index("SetVCPFeature(monitor.Handle, OsdButtonControlCode, desiredValue)")
        verify_index = self.csharp.index("finalValue == desiredValue")
        self.assertLess(read_index, set_index)
        self.assertLess(set_index, verify_index)
        self.assertIn("VERIFY_FAILED_ROLLED_BACK", self.csharp)
        self.assertIn("selected.VcpCaCurrentValue", self.csharp)
        self.assertIn("DestroyPhysicalMonitor", self.csharp)

    def test_apply_fails_closed_without_mccs_22_host_control(self) -> None:
        self.assertIn("REFUSED_MCCS_PRE_2_2", self.csharp)
        self.assertIn("REFUSED_HOST_CONTROL_UNSUPPORTED", self.csharp)
        self.assertRegex(
            self.csharp,
            r"return value >= 1 && value <= 3;",
        )
        self.assertIn("Multiple eligible physical monitors were found", self.csharp)

    def test_orchestrator_requires_explicit_mutation_authorization(self) -> None:
        text = self.orchestrator
        self.assertRegex(text, r"SupportsShouldProcess\s*=\s*\$true")
        self.assertRegex(text, r"ConfirmImpact\s*=\s*'High'")
        self.assertIn("[switch]$AllowTargetMutation", text)
        self.assertIn("Refusing $Operation target mutation without -AllowTargetMutation", text)
        self.assertIn("$PSCmdlet.ShouldProcess", text)

    def test_whatif_and_fixture_precede_remote_contact(self) -> None:
        text = self.orchestrator
        invoke_index = text.index("Invoke-Command")
        self.assertLess(text.index("if ($WhatIfPreference)"), invoke_index)
        self.assertLess(text.index("if ($FixtureMode)"), invoke_index)
        self.assertIn("network_activity_performed = $false", text)
        self.assertIn("target_mutation_performed = $false", text)

    def test_target_and_output_boundaries_are_reused(self) -> None:
        text = self.orchestrator
        self.assertIn("SasTargetIntake.psm1", text)
        self.assertIn("Assert-SasApprovedInputPath", text)
        self.assertIn("Assert-SasApprovedOutputPath", text)
        self.assertIn("[ValidateRange(1, 25)]", text)
        self.assertIn("Target count $($targets.Count) exceeds MaxTargets", text)

    def test_restore_manifest_is_generated_and_consumed(self) -> None:
        text = self.orchestrator
        self.assertIn("sas-cybernet-display-button-restore/v1", text)
        self.assertIn("original_vcp_ca_value", text)
        self.assertIn("Restore requires -RestoreManifest", text)
        self.assertIn("-AllowGenerated", text)
        self.assertIn("RestoreButtonLock", text)

    def test_no_scanning_registry_or_windows_power_substitute(self) -> None:
        combined = self.csharp + "\n" + self.orchestrator
        forbidden = (
            "Test-Connection",
            "ping.exe",
            "UIBUTTON_ACTION",
            "Set-ItemProperty",
            "New-ItemProperty",
            "Remove-ItemProperty",
            "Register-ScheduledTask",
            "New-Service",
            "powercfg.exe",
        )
        for token in forbidden:
            self.assertNotIn(token, combined, token)

    def test_documentation_names_proof_ceiling_and_exact_value(self) -> None:
        self.assertIn("VCP `0xCA`", self.doc)
        self.assertIn("`0x0303`", self.doc)
        self.assertIn("MCCS 2.2", self.doc)
        self.assertIn("restore manifest", self.doc.lower())
        self.assertIn("does not prove", self.doc.lower())

    def test_dedicated_workflow_is_registered(self) -> None:
        self.assertTrue(WORKFLOW.is_file(), WORKFLOW)
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("Run dependency-free display-button contracts", workflow)
        self.assertIn("Compile DDC CI helper", workflow)
        self.assertIn("Execute offline apply and restore fixtures", workflow)
        self.assertIn("Run targeted display-button Pester contracts", workflow)
        self.assertIn("git diff --check", workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
