# AutoLogon Deployment Orchestration Capability

## Contract

Route `autologon.admin_deploy` only through `scripts/Invoke-SasAutoLogonDeployment.ps1`, which owns the final-step gate and canonical Kerberos/SMB scheduled-task deployment front door.

## Inputs and preconditions

- Require explicit approved targets, package metadata, non-secret authorization and change references, current transport preflight evidence, and applicable policy paths.
- Default to planning or `-WhatIf`; network activity and target mutation remain false until the operator supplies target/change authority and explicitly enables the application entrypoint's mutation gate.
- Confirm the AutoLogon package remains enabled in the approved catalog and the final-step gate passes before application.

## Outputs and ceiling

- Consume the canonical deployment result, result retrieval, cleanup status, classification, reason codes, registered artifacts, and operator handoff.
- `deployment_succeeded` proves only authorized canonical transport execution, result retrieval, and cleanup. It does not prove reboot, automatic sign-in, current-token access, or application behavior.

## Guardrails

- Never route AutoLogon through the disposable package-VM lane or directly to the legacy WinRM implementation.
- Never reproduce request validation, transport selection, installer execution, finalization, or teardown logic in prompts.
- Never request or render password data, `DefaultPassword`, live hostnames, account identifiers, private package paths, or raw runtime evidence.
- A deployment result cannot activate or satisfy runtime proof.

## Authority

- `scripts/Invoke-SasAutoLogonDeployment.ps1`
- `scripts/Invoke-SasValidatedSoftwareDeployment.ps1`
- `docs/AUTOLOGON_DEPLOYMENT_WORKFLOW.md`
- `harness/workflows/autologon-proof-contract-floor.yaml`

## Used by

- `.claude/skills/autologon-deployment/SKILL.md`
