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
LOW_NOISE_POLICY="Config/low-noise-policy.json"
LOW_NOISE_MODULE="scripts/SasLowNoisePolicy.psm1"

for f in "$DOCTRINE" "$RUNTIME" "$GEN" "$LOW_NOISE_POLICY" "$LOW_NOISE_MODULE"; do
  [[ -f "$f" ]] || { echo "missing: $f"; exit 1; }
done

if command -v python3 >/dev/null 2>&1; then PYTHON_BIN=python3; else PYTHON_BIN=python; fi

bash -n "$GEN"

# Both JSON documents must parse.
"$PYTHON_BIN" -m json.tool "$DOCTRINE" >/dev/null || { echo 'doctrine JSON failed to parse'; exit 1; }
"$PYTHON_BIN" -m json.tool "$RUNTIME" >/dev/null || { echo 'runtime JSON failed to parse'; exit 1; }
"$PYTHON_BIN" -m json.tool "$LOW_NOISE_POLICY" >/dev/null || { echo 'low-noise policy JSON failed to parse'; exit 1; }

# Runtime config must match a fresh generation (no drift).
bash "$GEN" --check || { echo 'runtime config is stale; run: bash survey/sas-generate-naabu-runtime-profiles.sh'; exit 1; }

# Derive canonical ports from the doctrine file rather than hardcoding a third copy.
CANONICAL_CYBERNET_PORTS="$("$PYTHON_BIN" - "$DOCTRINE" <<'PY'
import json,sys
d = json.load(open(sys.argv[1],encoding="utf-8"))
kp = d["profiles"]["keyports_cybernet_json"]
print(kp["ports"])
PY
)"

CANONICAL_CYBERNET_PIPE_PORTS="$("$PYTHON_BIN" - "$DOCTRINE" <<'PY'
import json,sys
d = json.load(open(sys.argv[1],encoding="utf-8"))
kp = d["profiles"]["keyports_cybernet_pipe"]
print(kp["ports"])
PY
)"

# Default profile is the full Cybernet key-port JSON evidence profile.
DEFAULT_PROFILE="$("$PYTHON_BIN" - "$RUNTIME" <<'PY'
import json,sys
print(json.load(open(sys.argv[1],encoding="utf-8")).get("defaultProfile",""))
PY
)"
[[ "$DEFAULT_PROFILE" == "keyports_cybernet_json" ]] || { echo "unexpected default profile: $DEFAULT_PROFILE"; exit 1; }

# Both profile authorities must agree on the canonical Cybernet key-port set.
[[ "$CANONICAL_CYBERNET_PORTS" == "$CANONICAL_CYBERNET_PIPE_PORTS" ]] || {
  echo "keyports_cybernet_json and keyports_cybernet_pipe must use identical ports"
  exit 1
}

# The canonical Cybernet key-port profile must not contain printer port 9100.
if [[ "$CANONICAL_CYBERNET_PORTS" == *"9100"* ]]; then
  echo "keyports_cybernet_json must not include printer port 9100 by default"
  exit 1
fi

# Confirm expected canonical port list.
EXPECTED="80,443,135,445,3389,5985,5986"
[[ "$CANONICAL_CYBERNET_PORTS" == "$EXPECTED" ]] || {
  echo "canonical Cybernet key ports mismatch: expected $EXPECTED, got $CANONICAL_CYBERNET_PORTS"
  exit 1
}

# Low-noise module must expose canonical data, not embed a decision engine.
grep -qF 'function Get-SasCanonicalLowNoiseDocument' "$LOW_NOISE_MODULE" || { echo 'low-noise module missing canonical document loader'; exit 1; }
grep -qF 'Get-SasLowNoisePolicy' "$LOW_NOISE_MODULE" || { echo 'low-noise module missing Get-SasLowNoisePolicy'; exit 1; }
grep -qF 'Get-SasLowNoiseProfile' "$LOW_NOISE_MODULE" || { echo 'low-noise module missing Get-SasLowNoiseProfile'; exit 1; }

# The network_preflight profile in low-noise policy must retain port 9100 as intentional.
NETWORK_PREFLIGHT_PORTS="$("$PYTHON_BIN" - "$LOW_NOISE_POLICY" <<'PY'
import json,sys
p = json.load(open(sys.argv[1],encoding="utf-8"))
for profile in p["profiles"]:
    if profile["id"] == "network_preflight":
        ports = sorted(profile["ports"])
        print(",".join(str(x) for x in ports))
        break
PY
)"
[[ "$NETWORK_PREFLIGHT_PORTS" == "135,445,3389,9100" ]] || {
  echo "network_preflight profile ports must remain 135,445,3389,9100 (intentional field profile)"
  exit 1
}

# Doctrine principle checks on the runtime representation.
"$PYTHON_BIN" - "$RUNTIME" "$CANONICAL_CYBERNET_PORTS" <<'PY'
import json, sys

cfg = json.load(open(sys.argv[1], encoding="utf-8"))
expected_ports = sys.argv[2]
profiles = cfg["profiles"]
errors = []

# Default key-port profile must carry full Windows key ports + JSON output.
kp = profiles["keyports_cybernet_json"]
if kp.get("ports") != expected_ports:
    errors.append("keyports_cybernet_json wrong ports: %s" % kp.get("ports"))
if kp.get("outputFormat") != "json":
    errors.append("keyports_cybernet_json must be json output")
if "9100" in str(kp.get("ports", "")):
    errors.append("keyports_cybernet_json must not include printer port 9100 by default")

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

printf 'Naabu profile sync contracts passed. Canonical Cybernet ports: %s\n' "$CANONICAL_CYBERNET_PORTS"
