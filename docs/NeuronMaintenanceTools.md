# Neuron Maintenance Tools

This document describes the local Neuron maintenance survey helpers used by SysAdminSuite.

## Survey intent

The tools collect read-only evidence similar to what a technician reviews from the Neuron maintenance console: host identity, ping checks, IP configuration, routes, service status, firewall profile, netstat output, and wireless state.

## Remote intent

Remote use is for evidence gathering and remote emulation of maintenance review only. The workflow is designed to avoid target-side mutation unless an operator explicitly chooses a documented reset action.

## Capsule Command Console (CCC)

Authorized operators can also use the organization-hosted Capsule Command Console (CCC) as a complementary Neuron administration surface. CCC can support live review, troubleshooting/analysis, and role-permitted Neuron editing or configuration after the operator has been granted the required server access and enters through the approved RDP path.

CCC is external to SysAdminSuite. Its live server name, login endpoint, credentials, screenshots, exports, and target identifiers remain private/operator-local and are not tracked in this public repository.

See [Neuron Capsule Command Console (CCC)](NEURON_CAPSULE_COMMAND_CONSOLE.md) for the access model, capability boundary, and relationship to SysAdminSuite evidence.

## Maintenance safety

Default behavior is read-only. Network release/renew is blocked unless the operator supplies the explicit approval switch.
