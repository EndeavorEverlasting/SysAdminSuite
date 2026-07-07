# Run context lane boundary

This harness-foundation PR is not the authority for the canonical run-context module.

The focused run-context PR owns that module and its behavior tests. This PR keeps its contract suite focused on fixture-backed reports, command-surface wrappers, schemas, workflow specs, and local harness validation surfaces.

The duplicate run-context module was removed from this branch so this PR no longer physically overlaps that lane.

Do not add new foundation-contract assertions here that make this PR the behavioral owner of the run-context module.
