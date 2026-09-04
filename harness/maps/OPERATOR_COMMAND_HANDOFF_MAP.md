# Operator Command Handoff Map

| Gate | Canonical owner | Required evidence | Failure posture |
|---|---|---|---|
| Canonical location | `harness/skills/canonical-path-resolution/SKILL.md`, `harness/api/canonical-path-registry.json` | machine/profile path classification, exact checkout/runtime authority, Git I/O health | preserve state; no fallback clone or bare product command |
| Repository freshness | `harness/workflows/repository-freshness-before-launch.yaml` | refreshed remote default, local/default comparison, safe FF-only convergence when eligible, selected executing commit | preserve dirty/diverged/unhealthy state; stop before command |
| Starting network / intent | `scripts/SasNetworkIntent.psm1` | starting classification/label/authority and resolved `InternetSync`, `ProtectedNorthwell`, `LocalOnly`, or `CommandSpecific` intent | no guessed VPN/WLAN manipulation; stop/manual gate when unproven |
| Canonical execution | `harness/skills/operator-execution-route/SKILL.md`, `harness/api/operator-execution-route-registry.json` | registered front door, target encoding/validation, child exit, durable evidence pointer | fail closed; do not substitute inner/remembered command |
| Network restoration | `scripts/Invoke-SasNetworkAwareField.ps1`, `Restore-SasNetworkIntent` | restore disposition to captured starting WLAN when automatically changed, or explicit manual return posture | required restore failure prevents overall success |

## Agent handoff authority

`harness/skills/operator-command-handoff/SKILL.md` composes the five gates above. It owns ordering, not the underlying path, Git, network, or product implementations.

The required sequence is:

`path -> freshness -> network intent -> command -> restoration`

Agent-facing routing surfaces that emit operator commands must reference that skill before exposing product syntax.
