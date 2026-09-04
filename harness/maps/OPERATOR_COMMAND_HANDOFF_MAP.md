# Operator Command Handoff Map

| Gate | Canonical owner | Required evidence | Failure posture |
|---|---|---|---|
| Canonical path/location + starting posture capture | `harness/skills/canonical-path-resolution/SKILL.md`, `harness/api/canonical-path-registry.json` | machine/profile canonical development classification, exact checkout authority, Git I/O health, starting network classification/label/authority captured before any transition | preserve state; no fallback clone or bare product command |
| Repository freshness + freshness-network return | `harness/workflows/repository-freshness-before-launch.yaml`, `scripts/SasNetworkIntent.psm1` | `InternetSync` admitted before remote Git, refreshed remote default, local/default comparison, safe FF-only convergence when eligible, selected repository commit, return to the recorded starting network posture | preserve dirty/diverged/unhealthy state; failed freshness return stops before product intent/command |
| Production/runtime currentness when separate | `scripts/Refresh-SasOperatorCommand.ps1`, `scripts/SasPortableLauncher.ps1` | for sealed AutoLogon: refreshed field-ready source, `%LOCALAPPDATA%\SysAdminSuite\autologon-short-runtime.json`, selected-matching `prepared_commit`, local-filesystem-only transport, removed remotes, complete SHA-256 seal, protected bootstrap | never use Git inside `C:\SASAL`; return to Guest/Internet and refresh/reseal when stale or unproved |
| Product network intent | `scripts/SasNetworkIntent.psm1` | from recorded/restored starting posture, resolved `InternetSync`, `ProtectedNorthwell`, `LocalOnly`, or `CommandSpecific` product intent | no guessed VPN/WLAN manipulation; stop/manual gate when unproven |
| Canonical execution | `harness/skills/operator-execution-route/SKILL.md`, `harness/api/operator-execution-route-registry.json` | registered front door, target encoding/validation, child exit, durable evidence pointer | fail closed; do not substitute inner/remembered command |
| Final network restoration | `scripts/Invoke-SasNetworkAwareField.ps1`, `Restore-SasNetworkIntent` | restore disposition to captured starting WLAN when automatically changed, or explicit manual return posture | required restore failure prevents overall success |

## Agent handoff authority

`harness/skills/operator-command-handoff/SKILL.md` composes the gates above. It owns ordering, not the underlying path, Git, seal/update, network, or product implementations.

The required shorthand remains:

`path -> freshness -> network intent -> command -> restoration`

The executable detail is stricter: path resolution captures the starting network **before freshness**; freshness performs its own `InternetSync` transition and returns to that posture; separate runtime currentness is proved next when applicable; only then is the product command's network intent selected and executed.

Agent-facing routing surfaces that emit operator commands must reference that skill before exposing product syntax.
