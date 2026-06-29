# AD Computer Candidate Pool Sprint Contract

## Purpose

This document turns the Cybernet hostname variant doctrine into an implementation-ready sprint for the AD identity lane.

The goal is to build an **AD computer candidate pool** from approved Northwell naming conventions before any AD lookup is attempted. The pool is a bounded list of exact candidate computer names, not a generic fuzzy search pattern.

## Problem

`survey/sas-ad-identity-export.ps1` currently performs bounded hostname lookup for hostname-like identifiers, but the candidate set is mostly limited to:

```text
original identifier
short hostname
short hostname + $
```

That is safe, but incomplete for Northwell Cybernet work. Field data regularly contains naming-convention mistakes that are predictable enough to generate bounded candidates from approved manifests.

The implementation gap is not "make AD fuzzy." The implementation gap is:

```text
Build the AD computer candidate pool from known Northwell naming-convention variants,
then query AD exactly against those generated candidates.
```

## Non-negotiable doctrine

This is **naming-doctrine fuzzing**, not character-level fuzzy search.

Allowed:

- generate a small candidate pool from approved manifest rows
- query exact AD names / DNSHostName values from that candidate pool
- classify variant matches as candidates
- require serial / privileged identity proof before confirmation

Forbidden:

- generic edit-distance search
- unbounded wildcard AD queries
- broad `Name -like '*'` style searches
- searching outside the approved candidate set
- treating a variant match as serial proof
- auto-resolving multiple candidates
- expanding approved scan scope from a typo match alone

## Source inputs

The generator must consume only approved/codified input material:

```text
targets/local/
logs/targets/
survey/input/   # normalized staging only
```

The implementation must use the existing target-intake helpers where possible:

```text
scripts/SasTargetIntake.psm1
survey/sas-target-intake-dispatch.ps1
survey/lib/sas-target-intake.sh
```

## Required manifest fields

A useful candidate pool row needs, when available:

```text
ExpectedHostname
HostName
Hostname
ComputerName
Target
Identifier
ExpectedSerial
Serial
Site
Source
```

Implementation rule:

- Prefer explicit hostname fields over ambiguous `Identifier`.
- Treat serial-only rows as not AD-probe-ready until normalized or enriched to a hostname.
- Do not infer scan scope from serial-only material.

## Candidate-pool output schema

Create a machine-readable candidate-pool output before querying AD.

Recommended local ignored path:

```text
survey/output/ad_candidate_pool/<run_id>/ad_computer_candidates.csv
```

Required columns:

```text
InputRowId
InputSource
ExpectedHostname
CandidateHostname
CandidateSamAccountName
VariantClass
ConfidenceTier
Site
SitePrefixExpectation
SitePrefixStatus
ExpectedSerial
SerialProofStatus
QueryAllowed
ReviewRequired
Reason
```

Column meanings:

| Column | Meaning |
|---|---|
| `InputRowId` | Stable row number or generated row id from the approved input. |
| `InputSource` | Source file path or source label, local only. |
| `ExpectedHostname` | The hostname recorded in the approved manifest/source row. |
| `CandidateHostname` | Candidate computer name without trailing `$`. |
| `CandidateSamAccountName` | Candidate `sAMAccountName`, normally `CandidateHostname + '$'`. |
| `VariantClass` | Exact variant class, e.g. `exact`, `separator_only`, `opr_o0_swap`. |
| `ConfidenceTier` | `highest`, `high`, `medium-high`, `medium`, `low`, or `review`. |
| `Site` | Manifest site/location context when available. |
| `SitePrefixExpectation` | Expected prefix family inferred from site context, if known. |
| `SitePrefixStatus` | `matching`, `conflicting`, `unknown`, or `not_applicable`. |
| `ExpectedSerial` | Serial from manifest/source when present. |
| `SerialProofStatus` | Always `serial_unverified` at candidate-pool stage. |
| `QueryAllowed` | `true` only for bounded exact AD lookups. |
| `ReviewRequired` | `true` for low/review variants or site-prefix conflicts. |
| `Reason` | Human-readable explanation for the candidate. |

## Candidate generation order

Candidate generation must run in this fixed order. Order matters because stronger candidates should be queried/classified before lower-confidence candidates.

### 1. Exact hostname

Generate the exact normalized hostname first.

Example:

```text
WNH269OPR009
```

Classification:

```text
VariantClass = exact
ConfidenceTier = highest
ReviewRequired = false
```

### 2. Separator-only variants

Generate only separator presence/placement variants. Do not change letters or numbers.

Examples:

```text
WNH269OPR009
WNH-269-OPR-009
WNH269-OPR009
WNH269OPR-009
```

Classification:

```text
VariantClass = separator_only
ConfidenceTier = high
```

### 3. O/0 swaps in OPR-like segments

Generate O/0 substitutions only inside known OPR-style segments.

Examples:

```text
WNH269OPR009
WNH2690PR009
WNH269OPRO09
WNH2690PRO09
```

Classification:

```text
VariantClass = opr_o0_swap
ConfidenceTier = medium-high
```

Guardrail:

Do not perform global O/0 swapping across the whole hostname. Keep it scoped to OPR-like segments.

### 4. Missing or extra zero

Generate bounded zero-count drift in numeric suffixes.

Examples:

```text
WNH269OPR009
WNH269OPR09
WNH269OPR0009
```

Classification:

```text
VariantClass = zero_count_drift
ConfidenceTier = medium
```

Guardrail:

Only add or remove one zero in the trailing numeric suffix or a clearly recognized zero-padded block. No arbitrary zero insertion.

### 5. Known WNH / WMH prefix substitution

Generate `WNH` <-> `WMH` substitution as a known Northwell prefix-memory error.

Examples:

```text
WNH269OPR009
WMH269OPR009
```

Classification:

```text
VariantClass = known_prefix_substitution
ConfidenceTier = medium or low/review depending on site context
```

Site rules:

- `WNH` loosely aligns with LIJ / LIJ lineage.
- `WMH` loosely aligns with NSUH / Manhasset / NSUH lineage.
- If `Site` conflicts with the substituted prefix, classify the candidate as review-required.

Required statuses when conflict exists:

```text
ad_prefix_site_mismatch
needs_site_context_review
serial_unverified
```

### 6. Prefix-letter transposition

Generate bounded reordering of the three-letter prefix only.

Examples:

```text
WNH269OPR009
NWH269OPR009
WHN269OPR009
HNW269OPR009
```

Classification:

```text
VariantClass = prefix_letter_transposition
ConfidenceTier = low
ReviewRequired = true
```

Guardrail:

Do not transpose arbitrary letters in the full hostname. Only the prefix segment may be transposed.

### 7. Bounded numeric-block transposition

Generate adjacent single-swap permutations within one numeric block.

Examples:

```text
WNH269OPR009
WNH296OPR009
WNH629OPR009
WNH269OPR090
WNH269OPR900
```

Classification:

```text
VariantClass = numeric_block_transposition
ConfidenceTier = low
ReviewRequired = true
```

Guardrail:

No full permutation explosion. Only adjacent swaps inside one numeric block at a time.

## Absolute candidate cap

The implementation must enforce a hard per-input cap.

Recommended cap:

```text
MaxCandidatesPerInput = 25
```

If a row would exceed the cap:

- keep higher-confidence candidates first
- drop lower-confidence candidates
- emit `ReviewRequired = true`
- record the truncation in `Reason`

## Deduplication

Deduplicate candidates case-insensitively by:

```text
CandidateHostname
CandidateSamAccountName
```

Keep the highest-confidence classification when multiple variant classes generate the same candidate.

## AD query contract

The AD query layer must consume the candidate pool. It must not generate broad search clauses from raw identifiers.

Allowed query forms:

```text
Get-ADComputer -Identity <CandidateHostname>
Get-ADComputer -Identity <CandidateSamAccountName>
LDAP exact equality against name or dNSHostName from CandidateHostname
```

Forbidden query forms:

```text
Name -like '*<partial>*'
LDAP substring search generated from raw identifier
edit-distance expansion against AD
querying all AD computers and filtering broadly client-side
```

Description search must remain opt-in and must not become a substitute for hostname candidate generation.

## Result classification contract

A matched AD object must include the candidate-pool fields that explain why the lookup happened.

Required output additions for `sas-ad-identity-export.ps1` or its downstream normalized output:

```text
CandidateHostname
CandidateSamAccountName
VariantClass
ConfidenceTier
SitePrefixStatus
ReviewRequired
SerialProofStatus
```

Status mapping:

| Candidate result | AD status |
|---|---|
| exact candidate, one AD object, DNS found | `AD_OBJECT_FOUND_DNS_FOUND` or existing exact equivalent |
| exact candidate, one AD object, DNS missing | `AD_OBJECT_FOUND_DNS_MISSING` |
| variant candidate, one AD object | `NEEDS_OPERATOR_REVIEW` plus variant metadata, unless a future mapped status is implemented |
| multiple objects | `AD_DUPLICATE_CANDIDATES` |
| prefix/site conflict | `NEEDS_OPERATOR_REVIEW` plus `ad_prefix_site_mismatch` reason |
| no candidate match | `AD_NOT_FOUND` |

Do not emit `AD_CONFIRMED` from a variant match unless a separate approved identity source corroborates serial/device identity.

## Required implementation surfaces

Preferred code changes for the implementation sprint:

```text
survey/sas-ad-identity-export.ps1
scripts/SasHostnameCandidatePool.psm1        # new shared generator module, if useful
Tests/Pester/AdComputerCandidatePool.Tests.ps1
Tests/bash/test_ad_computer_candidate_pool_contracts.sh
survey/fixtures/ad_candidate_pool.sample.csv
```

Avoid burying the generator inside one script if it will also be needed by dashboard or offline planning lanes.

## Required tests

Tests must prove:

1. Exact hostname candidate is generated first.
2. Separator-only variants are generated without changing letters/numbers.
3. O/0 swaps only occur in OPR-like segments.
4. Missing/extra zero variants only affect bounded numeric suffix/zero-padded blocks.
5. WNH/WMH substitution is generated and site context is evaluated.
6. Prefix-letter transpositions are generated only for the prefix segment.
7. Numeric block transpositions are adjacent single swaps only.
8. Candidate count is capped.
9. Candidates are deduplicated case-insensitively.
10. Serial-only rows do not generate AD computer candidates.
11. Candidate output includes `VariantClass`, `ConfidenceTier`, `ReviewRequired`, and `SerialProofStatus`.
12. No wildcard or unbounded fuzzy AD query patterns are introduced.
13. Variant matches cannot become serial-confirmed in fixture/test outputs.
14. Existing AD probe resilience classifications still pass.

## Validation commands

Expected validation for the implementation sprint:

```powershell
pwsh -NoProfile -File tools/Test-Pester5Suite.ps1
```

```bash
bash tests/survey/run_offline_survey_tests.sh
bash Tests/bash/test_ad_computer_candidate_pool_contracts.sh
bash Tests/bash/test_powershell_network_preflight_contracts.sh
```

If live AD validation is requested, it must be run only on an authorized domain runtime and against an approved manifest. Offline CI must not pretend live AD validation ran.

## Acceptance criteria

The sprint is done when:

- `sas-ad-identity-export.ps1` consumes an AD computer candidate pool instead of only original/short hostname candidates.
- Candidate generation follows the Northwell naming classes above.
- AD lookup uses exact bounded candidates only.
- Output records show why each candidate was queried.
- Variant matches are review/candidate evidence, not serial proof.
- Tests prove no wildcard/fuzzy-soup behavior was introduced.
- No live target/evidence files are committed.

## Copy-ready next-agent prompt

```text
You are continuing SysAdminSuite.

Current doctrine to implement:
- docs/CYBERNET_HOSTNAME_VARIANT_DOCTRINE.md
- docs/AD_COMPUTER_CANDIDATE_POOL_SPRINT.md
- docs/AD_PROBE_RESILIENCE.md

Mission:
Implement the AD computer candidate-pool generator for Northwell Cybernet naming conventions.

Do not implement generic fuzzy search.
Do not introduce wildcard AD search.
Do not query outside bounded candidates generated from approved manifests.
Do not treat variant matches as serial proof.

Required candidate classes:
1. exact hostname
2. separator-only variants
3. O/0 swaps in OPR-like segments
4. missing/extra zero in bounded numeric suffix or zero-padded block
5. known WNH/WMH prefix substitution with site-context review
6. prefix-letter transposition only in the prefix segment
7. adjacent numeric-block transposition only, capped

Required outputs:
- CandidateHostname
- CandidateSamAccountName
- VariantClass
- ConfidenceTier
- SitePrefixStatus
- ReviewRequired
- SerialProofStatus

Preferred implementation:
- Add a shared candidate-pool module if appropriate.
- Wire survey/sas-ad-identity-export.ps1 to use it.
- Add Pester and bash/static contracts.
- Add synthetic fixtures only.

Validation:
- Pester suite
- offline survey tests
- candidate-pool contract tests

Merge policy:
merge_when_green.
```
