# Live Serial Probe Sprint

## Objective

Probe live Cybernet and Neuron workstation targets for serial and MAC evidence, then classify each target into a clear operational lane.

The audit report is the triage lens. The live probe is the confirmation layer.

## Primary Command

```bash
bash survey/sas-live-serial-probe.sh \
  --manifest survey/output/remote_survey_manifest.csv \
  --output survey/output/live_serial_probe_results.csv \
  --dashboard survey/output/live_serial_probe_dashboard.html
```

## Safe Offline/Test Mode

Use `--identity-csv` to test classification and dashboard rendering without touching live endpoints.

```bash
bash survey/sas-live-serial-probe.sh \
  --manifest survey/fixtures/live_serial_manifest.sample.csv \
  --identity-csv survey/fixtures/live_serial_identity.sample.csv \
  --output survey/output/live_serial_probe_results.csv \
  --dashboard survey/output/live_serial_probe_dashboard.html
```

## Output Classifications

| Classification | Meaning | Action |
|---|---|---|
| `live_serial_confirmed` | Live probe found serial or MAC evidence | Populate missing fields or confirm tracker values |
| `reachable_no_serial` | Host responds but serial/MAC was not collected | Try approved stronger identity path or Vision |
| `unreachable_mark_off` | Host is unreachable | Mark off and route to AD/Vision before treating as error |
| `needs_ad_lookup` | Target or DNS posture is weak | Locate object in AD |
| `needs_vision_lookup` | Asset inventory lookup needed | Locate in Northwell Vision or equivalent inventory |
| `manual_review` | Observed values conflict with tracker values | Human review before tracker update |

## Dashboard Panels

The HTML dashboard shows:

- total rows
- live confirmed rows
- rows where serials can be populated
- rows where MACs can be populated
- rows where tracker already had serials/MACs
- unreachable/off rows
- manual review rows
- category panels with filters
- follow-up routing counts
- dashboard summary JSON

Generated dashboards are local operational artifacts. Do not commit dashboards or CSVs containing real hostnames, serials, MACs, or locations.

## Field Rule

Unreachable does not mean duplicate error.

Unreachable means:

1. mark off for now
2. locate in AD or Vision
3. only escalate after external lookup fails or conflicts

No ghosts. No panic. No theatrical red cells.
