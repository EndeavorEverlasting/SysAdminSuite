# Dependency registry

`Config/toolbox-dependencies.json` is the canonical repo-wide dependency registry. Agents and
operators should treat it as the single authority for "what is pinned, where the pin lives, and
whether a dependency is needed for a given use case."

Human and agent entry points:

- Registry: [`Config/toolbox-dependencies.json`](../Config/toolbox-dependencies.json)
- Live presence probe: `bash scripts/sas-probe-toolbox.sh`
- Pin drift contract: `bash Tests/bash/test_dependency_registry_contracts.sh`

## Field schema

Each `tools[]` entry includes:

| Field | Purpose |
|-------|---------|
| `id` | Stable machine id used by probes and contracts |
| `displayName` | Human label |
| `tier` | `required`, `recommended`, or `workflow` |
| `category` | `runtime`, `build`, `library`, `field-tool`, `app`, or `meta` |
| `requiredFor` | Subset of `source-build`, `field-release`, `ci`, `runtime` |
| `versionSource` | Relative path to the file that owns the pin, or `null` for detect-only |
| `registryOnly` | When `true`, the live probe skips this entry (registry metadata only) |
| `workflows` | Dashboard/survey workflow tags |
| `pinnedVersion` | Pinned semver or TFM string; `null` when detect-only |

## Source-of-truth map

| Registry id | Pin owner |
|-------------|-----------|
| `dotnet_aspnet`, `dotnet_desktop`, `dotnet_sdk` | `Config/dotnet-bootstrap.json` |
| `naabu` | `Config/cybernet-naabu-profiles.json` (`naabuVersion`) |
| `pwsh`, `python` | `Config/sources.yaml` |
| `go`, `naabu_v2_library` | `probe/packet-expenditure/go.mod` |
| `dotnet_tfm` | `src/SysAdminSuite.DashboardHost/SysAdminSuite.DashboardHost.csproj` |

## Use-case filtering

An engine can answer "needed right now?" by intersecting `requiredFor` with the active context:

- **field-release** — packaged dashboard for machines without the SDK. Needs runtimes and the
  dashboard host; not `dotnet_sdk`, `go`, or `naabu_v2_library`.
- **source-build** — developer checkout building hosts or the packet-probe library engine. Needs
  `dotnet_sdk`, `go`, and `naabu_v2_library` when using `--engine library`.
- **ci** — automation runners. Needs build pins and contract-tested versions.
- **runtime** — live field survey/dashboard execution. May need `naabu`, `nmap`, and `npcap` for
  packet-probe SYN paths on Windows.

`registryOnly` entries (`go`, `naabu_v2_library`, `npcap`, `dotnet_tfm`) never appear in
`dashboard/toolbox-status.json`; they exist so agents can reason about pins without polluting the
live checklist.

## Drift checks

`Tests/bash/test_dependency_registry_contracts.sh` is read-only. It cross-validates registry pins
against their `versionSource` files and asserts that `registryOnly` ids stay out of the probe
output. Mismatches fail CI; the registry does not auto-bump pins.
