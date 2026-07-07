#!/usr/bin/env bash
# Contract: the runtime naabu config (Config/cybernet-naabu-profiles.json) must be a
# clean, deterministic generation of the doctrine contract (survey/naabu_profiles.json).
# Fails if the committed runtime config is stale. Read-only. No network, no targets.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

DOCTRINE="survey/naabu_profiles.json"
RUNTIME="Config/cybernet-naabu-profiles.json"
GEN="survey/sas-generate-naabu-runtime-profiles.sh"
LOW_NOISE="scripts/SasLowNoisePolicy.psm1"
PS_PREFLIGHT="survey/sas-network-preflight.ps1"

for f in "$DOCTRINE" "$RUNTIME" "$GEN" "$LOW_NOISE" "$PS_PREFLIGHT"; do
  [[ -f "$f" ]] || { echo "missing: $f"; exit 1; }
done

if command -v python3 >/dev/null 2>&1; then PYTHON_BIN=python3; else PYTHON_BIN=python; fi

bash -n "$GEN"

# Both JSON documents must parse.
"$PYTHON_BIN" -m json.tool "$DOCTRINE" >/dev/null || { echo 'doctrine JSON failed to parse'; exit 1; }
"$PYTHON_BIN" -m json.tool "$RUNTIME" >/dev/null || { echo 'runtime JSON failed to parse'; exit 1; }

# Runtime config must match a fresh generation (no drift).
bash "$GEN" --check || { echo 'runtime config is stale; run: bash survey/sas-generate-naabu-runtime-profiles.sh'; exit 1; }

# Default profile is the full Cybernet key-port JSON evidence profile.
DEFAULT_PROFILE="$("$PYTHON_BIN" - "$RUNTIME" <<'PY'
import json,sys
print(json.load(open(sys.argv[1],encoding="utf-8")).get("defaultProfile",""))
PY
)"
[[ "$DEFAULT_PROFILE" == "keyports_cybernet_json" ]] || { echo "unexpected default profile: $DEFAULT_PROFILE"; exit 1; }

EXPECTED_PORTS="80,443,135,445,3389,5985,5986"

# PowerShell preflight must consume the shared low-noise default instead of reintroducing a second hardcoded default.
grep -qF 'function Get-SasDefaultCybernetTcpPorts' "$LOW_NOISE" || { echo 'low-noise module missing Get-SasDefaultCybernetTcpPorts'; exit 1; }
grep -qF 'return @(80, 443, 135, 445, 3389, 5985, 5986)' "$LOW_NOISE" || { echo 'low-noise module default ports drifted'; exit 1; }
grep -qF '$Ports = @(Get-SasDefaultCybernetTcpPorts)' "$PS_PREFLIGHT" || { echo 'PowerShell preflight must load default ports from SasLowNoisePolicy'; exit 1; }
if grep -qF '@(135, 445, 3389, 9100)' "$PS_PREFLIGHT"; then
  echo 'PowerShell preflight must not keep the old 9100 default'
  exit 1
fi

# Doctrine principle checks on the runtime representation.
"$PYTHON_BIN" - "$RUNTIME" "$EXPECTED_PORTS" <<'PY'
import json, sys

cfg = json.load(open(sys.argv[1], encoding="utf-8"))
expected_ports = sys.argv[2]
profiles = cfg["profiles"]
errors = []

# Default key-port profile must carry full Windows key ports + JSON output.
kp = profiles["keyports_cybernet_json"]
if kp.get("ports") != expected_ports:
    errors.append("keyports_cybernet_json wrong ports: %s" % kp.get("ports"))
if "9100" in str(kp.get("ports", "")):
    errors.append("keyports_cybernet_json must not include printer port 9100 by default")
if kp.get("outputFormat") != "json":
    errors.append("keyports_cybernet_json must be json output")

# Pipe profile shares ports but is txt (no durable json).
pipe = profiles["keyports_cybernet_pipe"]
if pipe.get("ports") != expected_ports:
    errors.append("keyports_cybernet_pipe wrong ports")
if pipe.get("outputFormat") != "txt":
    errors.append("keyports_cybernet_pipe must be txt output")

# Justification + scope gates present where doctrine requires them.
if profiles["udp_dns_snmp_json"].get("requiresJustification") is not True:
    errors.append("udp_dns_snmp_json must require justification")
if profiles["allports_low_noise_json"].get("requiresJustification") is not True:
    errors.append("allports_low_noise_json must require justification")
if profiles["allports_low_noise_json"].get("allowFullPorts") is not True:
    errors.append("allports_low_noise_json must require explicit full-port approval")
if profiles["host_discovery_web_syn_txt"].get("requiresApprovedSubnetScope") is not True:
    errors.append("host_discovery_web_syn_txt must require approved subnet scope")
if profiles["load_balanced_hostname_all_ips_json"].get("scanAllIps") is not True:
    errors.append("load_balanced_hostname_all_ips_json must preserve -sa scan-all-IPs behavior")
if profiles["load_balanced_hostname_all_ips_json"].get("requiresHost") is not True:
    errors.append("load_balanced_hostname_all_ips_json must require host input")

# Every reachability/discovery profile is silent and CDN-excluding by default.
for name, p in profiles.items():
    if p.get("silent") is not True:
        errors.append("%s must be silent" % name)
    if p.get("excludeCdn") is not True:
        errors.append("%s must exclude CDN (-ec)" % name)

# Aliases must point at real profiles.
for alias, target in cfg.get("profileAliases", {}).items():
    if target not in profiles:
        errors.append("alias %s -> unknown profile %s" % (alias, target))

if errors:
    for e in errors:
        print("FAIL: " + e, file=sys.stderr)
    sys.exit(1)
PY

printf 'Naabu profile sync contracts passed. Default Cybernet ports: %s\n' "$EXPECTED_PORTS"
