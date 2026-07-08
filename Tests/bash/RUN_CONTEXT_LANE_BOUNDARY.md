# Run context lane boundary

This harness-foundation PR is not the authority for the canonical run-context module.

PR #146, `feat/harness): add canonical run context module`, owns `scripts/SasRunContext.psm1`, the run-context API surface, and the run-context behavior tests. That lane has been merged to `main`; this PR must consume that module after rebasing instead of carrying a duplicate copy.

This PR keeps its contract suite focused on fixture-backed reports, command-surface wrappers, schemas, workflow specs, documentation indexes, launcher surfaces, and local harness validation surfaces.

The duplicate run-context module was removed from this branch, so this PR no longer physically overlaps that lane.

Do not add new foundation-contract assertions here that make this PR the behavioral owner of the run-context module. If this PR needs run-context behavior, update the branch from `main` and depend on the merged PR #146 implementation.
