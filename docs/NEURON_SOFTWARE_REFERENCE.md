# Neuron Software Reference

This Software Reference describes the offline baseline used to compare observed Neuron package inventories.

## Survey use case

During a survey, collect observed packages into a CSV with this header:

```csv
Category,Name,Version
```

The comparison tooling checks the observed firmware and DDI package list against the local reference JSON. This is an evidence review workflow and does not connect to or change Neuron devices.

## Related live administrative reference

For authorized live Neuron inspection, troubleshooting/analysis, and role-permitted configuration, see [Neuron Capsule Command Console (CCC)](NEURON_CAPSULE_COMMAND_CONSOLE.md).

CCC is a separate organization-hosted administrative surface. The offline software-reference workflow remains read-only and independent of CCC access, and SysAdminSuite does not store CCC credentials or live infrastructure endpoints.
