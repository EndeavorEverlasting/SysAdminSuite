# Agent Handoff Addendum — Dashboard / Parser Lanes

Last updated: 2026-06-25  
`main` baseline: `2bca023` (PR #69 merged)

Use this addendum with any sprint handoff. It captures sharp edges that executive summaries often flatten.

---

## Critical PR #69 history

PR #69 re-landed the PR #54 Cybernet target manifest work after earlier manifest changes were reverted/reset out of `main`. The branch was manually reconciled with:

- **#56** AD registered population (`ad-registered-population` parser/store/UI)
- **#68** Naabu JSON parser contracts

Do not assume parser history on `main` was linear. Future rebases must preserve coexistence of AD + manifest + Naabu detection paths.

---

## Critical PR #69 parser risk

Cybernet manifest detection in [`dashboard/js/parsers.js`](../../dashboard/js/parsers.js) is **header-based** (`isCybernetManifestHeader`) and filename-based (`CYBERNET_MANIFEST_FILENAMES`).

**Known risk:** broad inventory CSVs whose headers resemble target manifests may false-positive as `cybernet-target-manifest`.

Future parser work must:

1. Preserve strict detection tests in [`dashboard/smoke-test.js`](../../dashboard/smoke-test.js).
2. Avoid classifying general inventory/evidence files as target manifests.
3. Prefer filename allowlist when ambiguous; tighten header heuristics before widening them.

**Product semantics (not proof):**

| Source | Meaning |
|--------|---------|
| AD registered population | Population authority — registered computer accounts |
| Cybernet target manifest | Target list rows — not reachability or serial proof |
| Naabu / network evidence | Reachability findings — separate from AD population |
| Workstation identity | Identity/serial evidence — separate from AD population |

---

## PR #69 review-history wart

PR #69 body may still say "Need reviewer/local check" for Node/manual drag-drop even though local smoke and CI passed before merge. Treat that as stale PR-body text. Browser QA gap below still applies.

---

## QR rule

Do **not** merge PR #47 (web QR builder) or PR #43 (WinForms QR tab) directly.

Build a new QR implementation under **Advanced Tools** per [`QR_CONVERGENCE_PLAN.md`](QR_CONVERGENCE_PLAN.md).

---

## Open PR identities (held / deferred)

| PR | Identity | Lane guidance |
|----|----------|---------------|
| #47 | Web dashboard QR payload builder | Hold — rebuild under Advanced Tools |
| #43 | WinForms QR Generator tab | Superseded for dashboard convergence |
| #44 | PS-independent dashboard tray host | Separate host lane |
| #42 | SAS artifact delivery companion | Survey/transport lane |
| #41 | Post-convergence validation / branch hygiene | Docs/hygiene lane |

---

## Stale worktrees (feature lanes)

| Worktree | Branch | Notes |
|----------|--------|-------|
| `SysAdminSuite-g1-profile-integration` | `feature/naabu-profile-runtime-integration` | Rebase onto current `main` before work |
| `SysAdminSuite-h1-docs` | `feature/naabu-docs-consolidation` | Rebase onto current `main` before work |

`SysAdminSuite-m-pester` was an orphan candidate (PR #58 closed; main Pester green). Remote branch deleted; remove local folder if it lingers.

---

## Hard rules (preserve)

- Do not touch `logs/targets/` tracked policy files without explicit authorization.
- No live AD exports, hostnames, serials, MACs, or survey outputs committed.
- Rebuild [`dashboard/js/bundle.js`](../../dashboard/js/bundle.js) from source only (`node dashboard/build-bundle.js`).
- Bash-first for new operational work; do not delete or weaken existing PowerShell files.
