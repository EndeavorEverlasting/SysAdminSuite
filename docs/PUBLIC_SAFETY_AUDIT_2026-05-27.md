# Public Safety Audit (2026-05-27)

Validation branch: `docs/post-convergence-validation-2026-05-27`  
Commit under test: `9ec89e44fb2fe24458dbdb799ac64d8b4f796bdf`

## Commands run

```bash
git grep -n "C:\\Users\\|C:/Users" -- . ':!docs/LOCAL_REFERENCE_POLICY.md' || true
git grep -n "local-reference" -- AGENTS.md docs || true
git grep -nE "([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}" -- . || true
git grep -nE "WNH|WMH|WBS|LIJ|NSUH|Northwell|Marcus|Bayshore|Glen Cove|CCMC" -- . || true
```

## Match counts

| Query | Matches |
|---|---:|
| `C:\\Users\\|C:/Users` (excluding local reference policy doc) | 0 |
| `local-reference` in `AGENTS.md` + `docs/` | 0 |
| MAC address pattern | 49 |
| Site/org keywords (`WNH|WMH|...`) | 234 |

## Findings classification

| Path | Example | Classification | Notes |
|---|---|---|---|
| `dashboard/js/sample-data.js` | sample `WMH*` hosts, MACs, and placeholder operators | `acceptable_fixture` | Test/dashboard sample corpus, not operator-local runtime output |
| `deployment-audit/tests/test_deployment_audit_contracts.sh` | fixture MAC and site tokens (`LIJ`, `WMH*`) | `acceptable_fixture` | Contract evidence strings and expected output checks |
| `docs/HOSTNAME_AVAILABILITY.md` + `docs/NEURON_NAME_AVAILABILITY.md` | conventions such as `WNH270OPR`, `LIJ-MACH-*`, `CCMC-MACH-*` | `acceptable_doc_example` | Product documentation examples |
| `AGENTS.md`, `docs/BASH_MIGRATION.md`, `replit.md` | policy-level "Northwell" references | `acceptable_doc_example` | Intentional policy wording |
| `Next plan.md` | literal historical text containing username + org mention | `needs_redaction` | Stale planning artifact still tracked; should be sanitized or removed from tracked docs |

## Known gaps

- One tracked planning artifact (`Next plan.md`) still contains historical PII-oriented instruction text.
- Pattern-based grep cannot distinguish all fixture vs production contexts automatically; manual classification remains required.

## Risks

- Future commits can accidentally propagate planning-artifact text if stale scratch docs remain tracked.
- Sample data may be misread as production data unless clearly labeled in docs/tests.

## Targets

1. Sanitize or remove `Next plan.md` from tracked content.
2. Keep fixture paths clearly marked as sample-only (`fixtures`, `sample-data`, test files).
3. Re-run this grep audit before every release-tag cut or branch cleanup wave.

## Verdict

Privacy posture remains improved after #40. No absolute user-profile paths were found in active docs/code matches for this sweep, but one tracked planning file still needs cleanup.
