# Neuron Maintenance Tools

This document describes the local Neuron maintenance survey helpers used by SysAdminSuite.

## Survey intent

The tools collect read-only evidence similar to what a technician reviews from the Neuron maintenance console: host identity, ping checks, IP configuration, routes, service status, firewall profile, netstat output, and wireless state.

## Remote intent

Remote use is for evidence gathering and remote emulation of maintenance review only. The workflow is designed to avoid target-side mutation unless an operator explicitly chooses a documented reset action.

## Maintenance safety

Default behavior is read-only. Network release/renew is blocked unless the operator supplies the explicit approval switch.
