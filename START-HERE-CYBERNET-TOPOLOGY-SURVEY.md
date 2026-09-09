# START HERE — Cybernet Topology Survey

This is the field-facing entrypoint for one question:

**Which network locations have enough deployment evidence to deserve a bounded, low-noise targeted Cybernet survey?**

It does **not** decide whether a host is a Cybernet. That is hardware identity, a separate authority.

## The one thing to click

```text
Run-CybernetTopologySurvey.cmd
```

Double-click it. No arguments. It does not matter whether this is your first click or your fiftieth.

Every click does the same safe sequence:

1. creates your local session if it does not exist yet
2. absorbs any new evidence you or a colleague dropped in
3. recomputes which CIDRs are eligible for a targeted pass
4. compares the result against your previous click
5. writes a fresh probe plan and review queue
6. opens the operator handoff so you can read what changed

The launcher performs **no network activity**. Nothing is probed and no device is reclassified.

## Your three folders

Everything lives under `evidence\CybernetTopology\`, which is gitignored.

| Folder | What you put there | Who fills it |
|---|---|---|
| `ingest\` | Your own probe result JSON | You |
| `inbox\` | Bundles you received from another technician | A colleague |
| `outbox\` | Bundles you can send to another technician | The launcher |

`ingest\` and `inbox\` are drained automatically on the next click. Files you dropped are moved into
`inbox\imported\` with the run id prefixed, so you can always see what was absorbed and when.

You never have to remember an import command. Drop the file, click the CMD.

## What you get back from each run

Under `evidence\CybernetTopology\runs\<run-id>\`:

| File | What it answers |
|---|---|
| `operator_handoff.txt` | What changed, what is approved, what is blocked, what to do next |
| `next_probe_targets.csv` | The CIDRs approved for a bounded pass, with their allowed profile and ports |
| `review_required.csv` | Blocked rows plus the exact evidence that would unblock each one |
| `iteration_summary.json` | Machine-readable version of the same run |

`next_probe_targets.csv` is the handoff into the existing survey lanes. It authorizes only the listed
bounded profile and ports. It is not permission for a broad scan.

If a row shows `BUDGET_NOT_DECLARED`, that CIDR has enough evidence to deserve a look but nobody has
declared how much looking is allowed. Blank does not mean unlimited. Declare `targeted_pass_budget`
for that subnet before probing it.

## How results feed the next run

This is the point of the loop. Each run's evidence becomes the next run's starting context:

```text
click 1  ->  no evidence yet, empty plan, handoff explains what to add
   add evidence to ingest/
click 2  ->  evidence merged, freshness renewed, some CIDRs become eligible
   colleague sends you their bundle, drop it in inbox/
click 3  ->  their evidence merges with yours, more rows clear, delta shows the promotions
```

Merge rules, so you can predict what a click will do:

- sites merge by `site_id`, subnets by `subnet_id`, evidence by `evidence_id`
- the same `evidence_id` seen again only wins if its `observed_at` is newer
- `last_observed` is recomputed from the newest merged evidence, so real new observations
  genuinely renew freshness instead of quietly going stale
- a declared `subnet_confidence` only replaces yours when its `calculated_at` is newer
- eligibility is **always** recomputed locally; a bundle can never hand you a pre-approved `ELIGIBLE`

New evidence never silently lowers the bar. A discovery-only observation refreshes the date but still
cannot authorize a targeted pass on its own.

## Sharing results with another technician

### To send your results

```text
Run-CybernetTopologySurvey.cmd
```

Then send the file named in the handoff under `Share bundle`, from `evidence\CybernetTopology\outbox\`.

Before export, machine-local absolute paths in `source_reference` are replaced with
`operator-local-reference`, and computed eligibility is stripped so the receiver recomputes it against
their own policy.

### To receive someone's results

Either drop their JSON into `evidence\CybernetTopology\inbox\` and click the CMD, or:

```text
Run-CybernetTopologySurvey.cmd Import "C:\path\to\their-bundle.json"
```

The launcher accepts both a bundle (`sas-cybernet-topology-evidence-bundle/v1`) and a raw registry
(`sas-cybernet-deployment-topology-registry/v1`). Anything else is refused rather than merged blindly.

### Sharing rules

- A bundle **always** contains operator-local data: site names, CIDRs, and device keys.
- Keep bundles in local ignored folders or approved internal channels.
- **Never commit a bundle.** `evidence/*` and `*.zip` are gitignored for this reason.
- Do not paste bundle contents into a ticket, chat, or AI prompt.

## Reading the review queue

Every blocked row names the evidence that would move it forward. The common ones:

| Status | Typical meaning | What actually unblocks it |
|---|---|---|
| `REVIEW_REQUIRED` | MEDIUM confidence, only one supporting source | A second SUBNET-supporting source with a different `source_type` |
| `NOT_ELIGIBLE` | No subnet-linked deployment proof | Authoritative deployment evidence whose `supports` includes `SUBNET` |
| `STALE` | Newest qualifying evidence is past the freshness horizon | Re-observe the subnet |
| `CONFLICTING` | Two credible sources disagree on placement | Operator review, not another probe |
| `SUPERSEDED` | Device relocated | Probe the superseding subnet instead |

`review_required.csv` carries the same guidance per row, so you do not need this table in the field.

## Hard rules

- No CIDR is ever invented from a hostname convention or from live hosts answering.
- Site-only deployment proof is proof about a facility, not authorization to survey a CIDR.
- Organization and site are independent profile boundaries. Missing `organization_id` or a
  non-`ACTIVE` site fails closed.
- Repeated clicks are safe. Repeated *probes* are not — use the plan, do not re-scan by habit.
- Never commit live evidence, bundles, run folders, or the local registry.

## For agents working on this surface

The engine is `scripts\SasCybernetTopologySession.psm1` and the entry is
`scripts\Invoke-SasCybernetTopologySession.ps1`. Eligibility semantics belong to
`DeploymentTracker\CybernetTopology.Eligibility.psm1` and must not be reimplemented here.

Contracts and proof live in `Tests\Pester\CybernetTopologySession.Tests.ps1`. Design rationale is in
`docs\CYBERNET_DEPLOYMENT_TOPOLOGY_REGISTRY.md`.

Do not add probing, hardware classification, or a second eligibility implementation to this lane.

This workflow is boring on purpose. Boring survives the field.
