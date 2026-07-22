#!/usr/bin/env bash
set -euo pipefail

python3 tests/survey/test_serial_first_identity.py
python3 tests/survey/test_cybernet_cleanup_report.py
python3 Tests/survey/test_ad_probe_resilience_contracts.py
python3 Tests/survey/test_ad_existence_bulk_contracts.py
python3 Tests/survey/test_serial_network_preflight_contracts.py
python3 Tests/survey/test_low_noise_policy_contracts.py
python3 Tests/survey/test_port_fallback_decision_contracts.py
python3 Tests/survey/test_english_event_renderer.py
python3 Tests/survey/test_probe_socket_access_contracts.py
python3 Tests/survey/test_standard_corporate_tooling_contracts.py
python3 Tests/survey/test_hotfix_command_registry_contracts.py
python3 Tests/survey/test_cybernet_com_qr_pack_contracts.py
python3 Tests/survey/test_cybernet_power_hardening_contracts.py
python3 Tests/survey/test_cybernet_display_button_control_contracts.py
python3 Tests/survey/test_cybernet_hardware_batch_contracts.py
python3 Tests/survey/test_cybernet_client_configuration_contracts.py
python3 Tests/survey/test_cybernet_operator_documentation_contracts.py
python3 Tests/survey/test_cybernet_software_deployment_documentation_contracts.py
python3 Tests/survey/test_software_deployment_input_invalidation_contracts.py
python3 Tests/survey/test_checkpoint_discipline_contracts.py
python3 Tests/survey/test_agent_instruction_factoring_contracts.py
python3 Tests/survey/test_agent_capability_manifest_contracts.py
python3 Tests/survey/test_agent_routing_manifest_contracts.py
python3 Tests/survey/test_autologon_agent_harness_contracts.py
python3 Tests/survey/test_agent_sprint_capsule_contracts.py
python3 Tests/survey/test_developer_workstation_agent_harness_contracts.py
python3 Tests/survey/test_developer_workstation_profile_contracts.py
python3 Tests/survey/test_developer_workstation_lifecycle_contracts.py
python3 Tests/survey/test_developer_workstation_inventory_contracts.py
python3 Tests/survey/test_windows_wezterm_tmux_service_contracts.py
python3 Tests/survey/test_linux_wezterm_tmux_contracts.py
python3 Tests/survey/test_e2e_default_posture_contracts.py
python3 Tests/survey/test_local_harness_contracts.py
python3 Tests/survey/test_software_install_harness_contracts.py
python3 Tests/survey/test_software_deployment_transport_contracts.py
python3 Tests/survey/test_autologon_proof_contract_floor_contracts.py
python3 Tests/survey/test_autologon_canonical_e2e_contracts.py
python3 Tests/survey/test_software_deployment_transport_preflight_contracts.py
python3 Tests/survey/test_software_deployment_transport_live_cert_contracts.py
python3 Tests/survey/test_canonical_smb_task_deployment_contracts.py
python3 Tests/survey/test_deployment_transport_convergence_contracts.py
python3 Tests/survey/test_software_install_finalization_contracts.py
python3 Tests/survey/test_run_context_contracts.py
python3 Tests/survey/test_approved_software_acceptance_contracts.py
python3 Tests/survey/test_autodidact_install_capsule_contracts.py
python3 Tests/survey/test_authorized_deployment_manifest_contracts.py
python3 Tests/survey/test_authorized_package_intake_contracts.py
python3 Tests/survey/test_qr_field_command_capsule_contracts.py
python3 Tests/survey/test_package_static_analysis_contracts.py
python3 Tests/survey/test_package_semantic_analysis_contracts.py
python3 Tests/survey/test_package_vm_qualification_profile_contracts.py


has_powershell=0
if command -v pwsh >/dev/null 2>&1; then
  pwsh_path=$(command -v pwsh)
  if [[ "$pwsh_path" != /mnt/* ]]; then
    has_powershell=1
  fi
fi
if [ "$has_powershell" -eq 0 ] && command -v powershell >/dev/null 2>&1; then
  ps_path=$(command -v powershell)
  if [[ "$ps_path" != /mnt/* ]]; then
    has_powershell=1
  fi
fi

if [ "$has_powershell" -eq 1 ]; then
  python3 Tests/survey/test_one_command_harness_proof_contracts.py
else
  printf '[SKIP] PowerShell runtime unavailable or Windows-only under WSL; one-command harness proof contracts run in the dedicated Windows workflow.\n'
fi

bash Tests/bash/test_target_reduction_plan_contracts.sh
