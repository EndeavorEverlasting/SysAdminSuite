# Cybernet Network Posture Profiles Plan

## Purpose

Extend the local-only Cybernet posture gate into explicit environment profiles. The operator must be able to test the corporate/WAB environment, an approved local LAN, an approved VPN path, or an unknown/blocked environment without silently weakening the safety policy.

The existing `scripts/Test-CybernetNetworkPosture.ps1` remains the local evidence collector and fail-closed gate. This plan defines the profile contract around it; it does not authorize target probes, subnet discovery, or target mutation.

## Profile contract

| Profile id | Intended environment | Required evidence | Default target actions | Failure classification |
|---|---|---|---|---|
| `corporate_wab` | Corporate/WAB segment | Approved SSID, wired allowlist, or approved enterprise VPN evidence | Read-only target preflight only | `ENVIRONMENT_BLOCKED_GUEST_NETWORK` or `ENVIRONMENT_BLOCKED_POLICY` |
| `approved_lan` | Approved local test LAN | Explicit local profile allowlist for suffix, IP, gateway, and DNS evidence | Local-device inventory and explicitly allowed read-only checks | `ENVIRONMENT_BLOCKED_POLICY` or `INCONCLUSIVE` |
| `approved_vpn` | Approved VPN path | Explicit VPN adapter, route, DNS, or domain evidence | Read-only target preflight only | `ENVIRONMENT_BLOCKED_POLICY` or `INCONCLUSIVE` |
| `unknown` | Any unclassified environment | No trusted profile evidence | No target actions | `INCONCLUSIVE` |

Profile selection is an explicit toggle/configuration input. It must not be inferred from a friendly SSID or used to bypass an allowlist. A selected profile is only eligible when its configured evidence passes.

## Evidence and reporting contract

Every posture result and evidence-derived English report should carry:

- `profile_id` and profile display name
- evidence source (`wifi`, `wired`, `vpn`, `fixture`, or `none`)
- `guard_configured` versus empty/default guard state
- classification and confidence (`proven`, `blocked`, or `inconclusive`)
- `allowed_for_target_preflight`
- permitted, skipped, and forbidden action classes
- `network_activity_performed` and `target_mutation_performed`
- raw-evidence artifact references separate from structured posture fields
- exact `next_action`

Human console status belongs on the host/information stream. Structured callers must receive only the posture object or JSON contract; mixed output is a harness defect.

## Implementation slices

1. Add a versioned profile configuration schema and an example containing no live addresses or credentials.
2. Extend the posture gate with `ProfileId` and profile-specific evidence evaluation while preserving the current default behavior.
3. Add fixture coverage for each profile, empty/default configuration, malformed configuration, and profile mismatch.
4. Add profile fields to operator-report and handoff adapters, preserving raw/structured traceability.
5. Expose a read-only agent/MCP capability that reports available profiles and the current evidence classification; it must not execute target actions.
6. Run Windows fixture validation, then perform real target preflight only on an approved profile and approved target list.

## Safety and proof boundaries

- Profile selection never grants permission by itself.
- `unknown` and failed evidence remain fail-closed.
- Local LAN mode is not a license for subnet scanning; any discovery remains a separately authorized workflow.
- No profile may collect secrets or persist live target data in tracked files.
- Runtime proof must identify the selected profile, evidence artifacts, target scope, and skipped checks.

## Validation commands

```powershell
Invoke-Pester -Path .\Tests\Pester\CybernetNetworkPosture.Tests.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-ai-layer.ps1
```

```bash
bash tests/survey/run_offline_survey_tests.sh
```

The first implementation PR should update the existing posture contract test before changing any target-facing workflow.
