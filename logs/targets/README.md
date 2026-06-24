# AD-derived target store (`logs/targets/`)

Place AD-derived Cybernet population exports or derived host lists here for local field execution.

This folder is gitignored because files may contain live hostnames, IPs, serials, site names, ticket references, or internal device evidence.

Only `.gitkeep` and README/documentation files should be committed.

## Target population doctrine

```text
AD registered Cybernet population = target population source
logs/targets/                     = local gitignored AD-derived target store
confirm-windows host file         = derived subset from AD export (one host per line, no CIDR)
naabu/nmap                        = reachability validation only
followup/CIM/WMI/SCCM/manual      = identity/serial proof where approved
```

Do not use naabu or nmap discovery output as the device population. Export registered Cybernet devices from AD (or an approved AD-derived report), place the export here, then derive a plain-text `--host-file` for `confirm-windows`.

## Example layout (local only — not committed)

```text
logs/targets/SSUH_cybernet_registered.xlsx    # AD population export
logs/targets/SSUH_confirm_hosts.txt            # derived subset for confirm-windows
```

## Field command reference

See [`docs/WAB_TEST_READINESS.md`](../docs/WAB_TEST_READINESS.md) Phase 2b and [`docs/NAABU_CYBERNET_PROFILES.md`](../docs/NAABU_CYBERNET_PROFILES.md).
