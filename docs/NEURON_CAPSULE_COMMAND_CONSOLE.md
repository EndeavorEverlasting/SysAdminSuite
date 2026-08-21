# Neuron Capsule Command Console (CCC)

The Capsule Command Console (CCC) is an organization-hosted administrative surface that authorized operators can use alongside SysAdminSuite when working with Neuron devices.

CCC is external to SysAdminSuite. SysAdminSuite does not host CCC, grant CCC access, store CCC credentials, or automate CCC actions.

## What CCC is useful for

Depending on the operator's server-side role and the CCC version deployed by the organization, CCC can be used to:

- review live Neuron state and operational information;
- inspect device configuration for troubleshooting and analysis;
- edit or configure Neuron settings when the operator's granted role permits those actions; and
- provide an additional administrative view when SysAdminSuite survey evidence needs human comparison against the managed Neuron environment.

Exact controls and available actions are permission-dependent. Do not assume that RDP reachability or a visible CCC page authorizes configuration changes.

## Access model

1. Obtain explicit CCC/server access through the organization's normal access-request process.
2. Connect from an approved network context or approved remote-access path as required by the organization.
3. RDP to the approved CCC server or administrative host using the organization-provided connection information.
4. Inside the authorized session, open the approved CCC login endpoint and authenticate with separately issued credentials.
5. Stay within the permissions and change process assigned to the operator.

Do not bypass access controls, reuse another operator's session, or infer authorization from network reachability.

## Endpoint and credential handling

The CCC server name, login URL, credentials, bookmarks, screenshots, exports, and live Neuron identifiers are operational/private material and are intentionally not committed to this public repository.

Use the current CCC endpoint supplied through an approved private organizational channel or an operator-local, gitignored reference. If the endpoint changes, update the private reference rather than embedding the live infrastructure address in tracked documentation.

## Relationship to SysAdminSuite

Use the two tools as complementary surfaces:

- **SysAdminSuite survey and maintenance helpers** provide repository-owned, reproducible evidence collection and local analysis workflows.
- **CCC** provides an authorized server-hosted administrative view and, where permissions allow, a configuration surface for Neurons.

A change made through CCC is an external/manual administrative action. SysAdminSuite must not claim that change as a SysAdminSuite deployment result unless a separate approved evidence workflow actually observes and records the resulting state.

For local Neuron maintenance helpers, see [Neuron Maintenance Tools](NeuronMaintenanceTools.md). For the offline package baseline comparison, see [Neuron Software Reference](NEURON_SOFTWARE_REFERENCE.md).

## Current scope

This is a documentation reference only. It defines no CCC API integration, automated login, credential storage, remote-control implementation, or target-mutation authority inside SysAdminSuite.
