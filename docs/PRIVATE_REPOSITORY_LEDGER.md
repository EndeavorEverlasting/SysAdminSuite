# Private Repository Ledger

SysAdminSuite keeps commit/decision/plan continuity in a **machine-local, ignored JSONL ledger**. The ledger is operational context, not source control and not public repository evidence.

## Canonical local artifact

`runs/private-ledger/ledger.jsonl`

`runs/` is already gitignored. The ledger may contain branch names, commit identities, changed path names, and operator/agent summaries, so it must remain local and untracked.

## Automatic commit capture

The tracked `.githooks/post-commit` hook runs:

```text
python3 scripts/sas-private-ledger.py commit-hook
```

Each successful commit appends one `kind=commit` event containing:

- UTC timestamp;
- current branch;
- exact HEAD SHA;
- commit subject;
- changed repository path names only.

The writer does **not** record diff bodies, file contents, environment dumps, credentials, network observations, or target data.

A commit message may also carry explicit private decision/plan trailers:

```text
SAS-Decision: keep the existing validator as the canonical owner
SAS-Plan: add the private ledger gate before broader CI
```

The post-commit hook appends those as separate `decision` / `plan` events associated with the same commit.

## Explicit decision or plan capture

A decision or plan that should be preserved before the next commit uses the repository-owned writer directly:

```text
python3 scripts/sas-private-ledger.py append decision "reuse the existing P11 one-command proof"
python3 scripts/sas-private-ledger.py append plan "wire local commit capture into hook hygiene validation"
```

Agents operating the repository sprint lane should use this command after a durable decision or plan is made when that information is useful for later resumption.

Read-only status:

```text
python3 scripts/sas-private-ledger.py status
```

`status` does not create or mutate the ledger.

## Hook activation

The repository uses tracked hooks under `.githooks/`. A checkout uses them only when its Git configuration points `core.hooksPath` at `.githooks`; hook activation remains a local checkout setting and is not proof that any particular commit was captured.

## Proof boundary

The private ledger is continuity evidence only. It does not prove application runtime behavior, network reachability, deployment, account/save mutation, target mutation, review acceptance, or merge state. The one-command synthetic harness validates the ledger **contract and hook hygiene**, not the operator's historical ledger contents.
