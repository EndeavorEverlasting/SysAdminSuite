# Low-noise policy normalization sprint

## Status

Planning artifact for the next implementation PR.

```text
repo: EndeavorEverlasting/SysAdminSuite
planning branch: docs/low-noise-policy-normalization-plan
recommended implementation branch: feat/low-noise-policy-normalization
recommended base: main after this planning PR is merged
lane: harness architecture / policy normalization
```

## Mission

Make low-noise behavior a normalized, versioned repository contract instead of a collection of repeated strings, flags, port lists, retry rules, and output fields.

Success means every survey or reachability lane obtains the same policy values through a canonical provider, emits the same policy version in machine-readable artifacts, and fails closed when a consumer omits or overrides required boundaries without an explicit approved profile.

This sprint is not about hiding activity. Low-noise means fewer justified packets, bounded target populations, minimal ports, capped rate/retries, fresh-evidence reuse, transparent operator intent, local-only evidence, and no target-side survey artifacts.

## Current architecture to preserve

The repository already has useful foundations:

```text
Config/operational-posture.json
scripts/SasLowNoisePolicy.psm1
docs/LOW_NOISE_PROBE_PRINCIPLES.md
docs/LOW_NOISE_SURVEY_DOCTRINE.md
docs/OPERATIONAL_POSTURE.md
survey/sas-serial-preflight-plan.ps1
survey/sas-network-preflight.ps1
survey/sas-target-intake-dispatch.ps1
survey/sas-run-naabu-pipeline.sh
survey/sas-cybernet-subnet-survey.sh
Tests/bash/test_operational_posture_contracts.sh
tests/survey/run_offline_survey_tests.sh
```

Existing rules that remain binding:

- approved manifests or evidence define population; subnet probing does not invent population
- serial-only values are review items, not network targets
- fresh identity/reachability evidence suppresses habitual re-probing
- shell choice is not a network-visibility control
- Naabu output remains silent and machine-readable where used in pipelines
- CDN/WAF/cloud-edge handling remains bounded
- survey lanes do not mutate target systems
- runtime evidence stays local and ignored
- deployment/mutation lanes remain separately authorized and teardown-aware

## Problem statement

Low-noise doctrine currently spans multiple authority surfaces:

1. `Config/operational-posture.json` defines cross-lane posture and some defaults.
2. `scripts/SasLowNoisePolicy.psm1` hardcodes survey policy wording and artifact fields.
3. Bash and PowerShell consumers can still encode their own port, rate, retry, profile, or output defaults.
4. Documentation describes overlapping policy at different levels.
5. Static contracts often assert literal strings rather than validating one normalized policy object and its consumers.

The result is drift risk. A lane can appear compliant while using a different default port set, retry count, rate cap, freshness rule, edge-target treatment, or artifact schema.

## Owned scope

- inventory every tracked surface that selects targets, ports, rate, retries, freshness, output mode, or edge handling
- define one versioned low-noise policy data contract
- keep `scripts/SasLowNoisePolicy.psm1` as the PowerShell provider and compatibility surface
- factor consumer defaults through canonical getters/adapters
- make machine-readable artifacts include policy version and effective profile
- add contracts that detect duplicated or divergent defaults
- preserve existing safe CLI behavior unless a mismatch is a documented defect
- update doctrine and operator docs to name the canonical source and override rules

## Forbidden scope

- no PR #142 changes
- no PR #156 runtime proof or COM AutoFix behavior changes
- no live probing, packet capture, target mutation, deployment, or remote execution
- no attempt to suppress Windows, EDR, firewall, switch, or network telemetry
- no broad port expansion
- no subnet-derived population generation
- no new external runtime dependency without proof it already exists in supported environments
- no dashboard rewrite
- no unrelated cleanup or naming churn
- no generated runtime artifacts committed

## Canonical contract design

Create a dedicated versioned policy document:

```text
Config/low-noise-policy.json
```

`Config/operational-posture.json` remains the lane/posture authority and references the low-noise policy document. It should not duplicate detailed packet-profile values.

Minimum normalized fields:

```text
schema_version
policy_version
population_source_policy
freshness_policy
retry_policy
rate_policy
edge_target_policy
output_policy
evidence_policy
profiles
```

Each profile must declare effective values rather than rely on hidden consumer defaults:

```text
id
purpose
target_source
ports
tcp_only
rate_cap
retries
host_discovery_mode
exclude_cdn
silent_output
machine_output
local_evidence_only
target_mutation
```

Initial profiles should be derived from current tracked behavior, not invented from preference. At minimum inventory and normalize:

```text
Cybernet key-port reachability
web reachability
admin-surface reachability
serial-to-target preflight
subnet confirmation
Naabu pipe output
Naabu JSON evidence
```

## Implementation sequence

### 1. Drift inventory and characterization

Before changing behavior, identify every literal/default source for:

```text
ports
rate
retries
timeouts
freshness
-silent
-json
-ec
-sa
host discovery
population source
output roots
network_activity_performed
low_noise_policy_version
```

Produce a tracked matrix in the implementation PR description or a bounded document. Mark each consumer as:

```text
canonical
compatible adapter
intentional override
drift defect
legacy/deprecated
```

Do not normalize a value until its current behavior and callers are known.

### 2. Add and validate the policy schema

Add `Config/low-noise-policy.json` with a deterministic schema and current effective profiles.

Add a validator that checks:

- required fields and supported schema version
- unique profile IDs
- nonempty bounded port sets
- nonnegative retry values
- positive rate caps within operational posture limits
- survey profiles declare `target_mutation: never`
- evidence outputs are local-only
- no profile enables subnet population discovery
- machine-readable profiles declare their output mode

Prefer a dependency-free validator using Python standard library so CI and offline contracts can execute it.

### 3. Refactor the PowerShell provider

Refactor `scripts/SasLowNoisePolicy.psm1` to load and validate the canonical policy document.

Preserve current exported compatibility functions where practical:

```text
Get-SasLowNoisePolicy
Add-SasLowNoisePolicyToObject
New-SasLowNoiseSummaryObject
Get-SasLowNoiseOperatorLines
```

Add bounded getters for effective profiles rather than allowing each consumer to parse JSON independently.

Required behavior:

- fail closed when policy/config is missing or invalid
- expose policy and schema versions
- return copies/objects that consumers cannot accidentally mutate globally
- preserve operator wording through the provider
- keep summary JSON fields stable unless a versioned migration is documented

### 4. Add nonduplicating Bash/CLI access

Bash consumers must derive effective values from the same canonical document without copying a second default table.

Choose the smallest adapter already supported by repository/environment evidence. Do not introduce `jq`, Python, or another dependency merely by assumption. The implementation PR must prove the selected adapter in CI and document the field environment requirement.

### 5. Migrate highest-risk consumers first

Priority order:

1. `survey/sas-run-naabu-pipeline.sh`
2. `survey/sas-cybernet-subnet-survey.sh`
3. `survey/sas-network-preflight.ps1`
4. `survey/sas-serial-preflight-plan.ps1`
5. `survey/sas-target-intake-dispatch.ps1`
6. dashboard command generation surfaces that emit these commands

For each consumer:

- preserve public parameters where compatible
- obtain defaults from a named profile
- record the effective profile and policy version in dry-run/audit output
- distinguish explicit operator override from canonical default
- reject overrides that broaden forbidden population or mutation boundaries
- keep actual network activity disabled in tests

### 6. Strengthen contracts and CI

Add or extend:

```text
Tests/survey/test_low_noise_policy_contracts.py
Tests/Pester/SasLowNoisePolicy.Tests.ps1
Tests/bash/test_operational_posture_contracts.sh
tests/survey/run_offline_survey_tests.sh
.github/workflows/operational-posture.yml
```

Contracts must prove behavior, not only search for slogans.

Required assertions:

- policy JSON parses and validates
- operational posture references the canonical policy path/version
- PowerShell provider returns exact canonical profile values
- representative Bash dry-run plans use canonical values
- all probe-staging artifacts include policy version/profile
- no survey profile permits target mutation
- no consumer silently broadens default ports, rate, retries, or population
- explicit overrides are visible in output
- local ignored output roots remain enforced
- no live network command executes in contracts

Add a drift check that fails when protected consumers hardcode canonical default port/rate/retry sets outside approved fixtures/provider code.

### 7. Documentation closure

Update doctrine so authority is unambiguous:

```text
Config/operational-posture.json     lane and mutation posture
Config/low-noise-policy.json        normalized survey/probe policy
scripts/SasLowNoisePolicy.psm1      PowerShell access/provider
```

Document:

- how profiles are selected
- how explicit overrides are recorded
- which overrides are forbidden
- how policy versions appear in artifacts
- how to add a new profile without copying defaults
- why low-noise is transparent scope control, not telemetry suppression

## Acceptance criteria

The implementation PR is complete only when:

1. one canonical policy document defines effective low-noise profiles
2. `Config/operational-posture.json` references it without duplicating profile values
3. PowerShell and Bash/CLI consumers use canonical adapters
4. current public commands remain compatible or migration is explicitly documented
5. policy version and profile ID appear in generated plans/summaries
6. survey consumers remain read-only toward targets
7. no default broadens target population, ports, rate, or retries
8. static drift contracts fail on duplicated protected defaults
9. targeted Pester, Python, Bash, and offline survey checks pass
10. no runtime evidence or machine-local artifacts are committed

## Validation commands for the implementation PR

Run the strongest available subset and report exact skips:

```powershell
python Tests/survey/test_low_noise_policy_contracts.py
Invoke-Pester .\Tests\Pester\SasLowNoisePolicy.Tests.ps1
```

```bash
bash Tests/bash/test_operational_posture_contracts.sh
bash tests/survey/run_offline_survey_tests.sh
```

Also run:

```bash
git diff --check
git status --short
git diff --stat
git diff
```

No validation step should send network packets.

## Parallel lanes

Parallel work is safe only with serialized ownership of shared authority files.

| Lane | Owned files | Parallel-safe with | Collision risk |
|---|---|---|---|
| A: inventory/schema | `Config/low-noise-policy.json`, posture reference, schema validator | C after schema shape is frozen | High with B/D if schema changes concurrently |
| B: PowerShell provider | `scripts/SasLowNoisePolicy.psm1`, Pester tests | D after provider API is frozen | High with consumer migrations importing new getters |
| C: Bash/CLI adapter | bounded adapter plus Bash tests | B when schema is frozen | High with Naabu/subnet scripts |
| D: consumer migration | survey planners/pipelines/dispatcher | docs lane | High across shared survey scripts; assign one owner per file |
| E: docs/CI closure | doctrine docs, workflow wiring, offline runner | B/C/D after interfaces stabilize | Medium; avoid editing same contract files as implementation lanes |

Recommended sequence:

```text
A schema freeze
-> B and C adapters in parallel
-> D consumers split by file ownership
-> E contracts/docs/CI closure
```

Do not run multiple agents against `Config/low-noise-policy.json`, `scripts/SasLowNoisePolicy.psm1`, or the same survey consumer simultaneously.

## PR strategy

Use one bounded implementation PR unless the inventory proves the Bash and PowerShell migrations are independently reviewable without duplicating policy authority.

Recommended PR:

```text
title: feat(survey): normalize low-noise policy across probe lanes
branch: feat/low-noise-policy-normalization
base: main
```

The PR should begin with characterization and contracts, then migrate consumers. Do not combine PR #156 Cybernet runtime proof with this architectural sprint.
