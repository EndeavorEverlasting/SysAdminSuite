# Neuron Software Reference

This Software Reference describes the offline baseline used to compare observed Neuron package inventories.

## Survey use case

During a survey, collect observed packages into a CSV with this header:

```csv
Category,Name,Version
```

The comparison tooling checks the observed firmware and DDI package list against the local reference JSON. This is an evidence review workflow and does not connect to or change Neuron devices.
