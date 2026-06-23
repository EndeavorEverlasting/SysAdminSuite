# Cybernet Discovery Workflow

This is the technician-facing structure view for Cybernet subnet discovery and survey handoff.

Use this diagram to explain how serial inventory, infrastructure evidence, Naabu, Nmap, and reconciliation fit together.

```mermaid
flowchart LR
  A["Cybernet Serials CSV<br/>identity anchor"]
  B["Known Host / MAC Data<br/>tracker or deployment notes"]
  C["Infrastructure Evidence<br/>DNS, DHCP, AD, SCCM, CMD context"]

  D["CybernetSubnetDiscovery<br/>normalize, merge, resolve, map"]
  E["Approved Scan Scope<br/>TargetIPs.txt<br/>SubnetsToSurvey.csv"]

  F["Naabu Survey<br/>fast selected-port pass"]
  G["Nmap Survey<br/>artifact-oriented host/port pass"]

  H["Survey Evidence<br/>JSONL / XML artifacts"]
  I["Cybernet Reconciliation<br/>compare expected vs observed"]
  J["Technician Outputs<br/>presence report, action items, manual review"]

  A --> D
  B --> D
  C --> D
  D --> E
  E --> F
  E --> G
  F --> H
  G --> H
  D --> I
  H --> I
  I --> J

  K["Guardrails<br/>approved subnets only<br/>read-only<br/>no full-port default"]
  K -. applies to .-> D
  K -. applies to .-> F
  K -. applies to .-> G
```

## Operator rule

Do not start with a guessed subnet scan.

Start with serials, attach infrastructure evidence, generate approved scope, then survey with Naabu or Nmap.
