#!/usr/bin/env bash
set -euo pipefail

python3 tests/survey/test_serial_first_identity.py
python3 tests/survey/test_cybernet_cleanup_report.py
python3 Tests/survey/test_ad_probe_resilience_contracts.py
python3 Tests/survey/test_ad_existence_bulk_contracts.py
python3 Tests/survey/test_serial_network_preflight_contracts.py
python3 Tests/survey/test_low_noise_policy_contracts.py
python3 Tests/survey/test_english_event_renderer.py
python3 Tests/survey/test_probe_socket_access_contracts.py
python3 Tests/survey/test_standard_corporate_tooling_contracts.py
python3 Tests/survey/test_hotfix_command_registry_contracts.py
python3 Tests/survey/test_cybernet_com_qr_pack_contracts.py
python3 Tests/survey/test_checkpoint_discipline_contracts.py
python3 Tests/survey/test_agent_instruction_factoring_contracts.py
python3 Tests/survey/test_agent_capability_manifest_contracts.py
python3 Tests/survey/test_local_harness_contracts.py
python3 Tests/survey/test_software_install_harness_contracts.py
python3 Tests/survey/test_run_context_contracts.py
python3 Tests/survey/test_network_survey_delta_contracts.py
python3 Tests/survey/test_network_survey_denominator_contracts.py

if command -v pwsh >/dev/null 2>&1 || command -v powershell.exe >/dev/null 2>&1 || command -v powershell >/dev/null 2>&1; then
  python3 Tests/survey/test_one_command_harness_proof_contracts.py
else
  printf '[SKIP] PowerShell runtime unavailable; one-command harness proof contracts run in the dedicated Windows workflow.\n'
fi

bash Tests/bash/test_target_reduction_plan_contracts.sh
