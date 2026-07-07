# Run context lane boundary

This harness-foundation PR should not be the authority for the canonical run-context module.

The focused run-context PR owns that module and its behavior tests. This PR should keep its contract suite focused on fixture-backed reports, command-surface wrappers, schemas, workflow specs, and local harness validation surfaces.

Do not add new foundation-contract assertions here that make this PR the behavioral owner of the run-context module.
