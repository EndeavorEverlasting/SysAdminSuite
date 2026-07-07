# SysAdminSuite network guard local setup

Live SysAdminSuite operational scripts require an approved Northwell network posture before they run target-facing work.

Wi-Fi is accepted when the connected SSID starts with `NSLIJHS-WAB`.

Wired Ethernet is accepted only when the workstation has local evidence that matches a local allowlist. The local allowlist is intentionally not committed to the public repo.

## Local wired setup

1. Copy the example file:

   ```bash
   cp Config/sas-network-guard.example.json Config/sas-network-guard.local.json
   ```

2. Replace the documentation-only example values with approved internal/site values supplied through the proper internal channel.

3. Keep only the categories that are approved for your environment. Empty arrays are allowed for categories you do not use.

4. Do not commit `Config/sas-network-guard.local.json`. It is ignored by git.

## Supported allowlist categories

The local JSON file supports these keys:

```json
{
  "allowedDnsSuffixes": ["wired.example.invalid"],
  "allowedWindowsDomains": ["EXAMPLE"],
  "allowedLocalIpCidrs": ["192.0.2.0/24"],
  "allowedGatewayCidrs": ["198.51.100.0/24"],
  "allowedDnsServerCidrs": ["203.0.113.0/24"]
}
```

The committed example uses documentation ranges and placeholder names only. Do not replace the committed example with real internal values.

## Environment variable alternative

Operators can also provide allowlists through comma-separated environment variables:

- `SAS_NETWORK_GUARD_ALLOWED_DNS_SUFFIXES`
- `SAS_NETWORK_GUARD_ALLOWED_WINDOWS_DOMAINS`
- `SAS_NETWORK_GUARD_ALLOWED_LOCAL_IP_CIDRS`
- `SAS_NETWORK_GUARD_ALLOWED_GATEWAY_CIDRS`
- `SAS_NETWORK_GUARD_ALLOWED_DNS_SERVER_CIDRS`

The local JSON file and environment variables can be used together.

## Guard-only local checks

These checks read local workstation state only and do not run a target-facing workflow.

Bash / Git Bash:

```bash
source survey/lib/sas-network-guard.sh
sas_require_northwell_wifi && echo "NETWORK_GUARD_OK"
```

PowerShell:

```powershell
Import-Module .\scripts\SasNetworkGuard.psm1
Assert-SasNorthwellWifi
"NETWORK_GUARD_OK"
```

## Failure behavior

If Wi-Fi does not match `NSLIJHS-WAB*` and no approved wired evidence is configured or matched, live scripts fail closed before expensive or target-facing work begins.

Malformed local JSON also fails closed. Fix the local file instead of bypassing the guard.
