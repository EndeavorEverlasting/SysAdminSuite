#!/usr/bin/env bash
set -euo pipefail

MANIFEST=""
OUTPUT="survey/output/autologon_assessment.csv"
DASHBOARD=""
NO_DASHBOARD=0
PASS_THRU=0
OPEN=0
AD_LIVE=0
AD_OUTPUT=""
AD_CSV=""
LOCAL=0
FIXTURE_DRY_RUN=0

usage(){ cat <<'USAGE'
SysAdminSuite Auto-logon Workstation Assessment

Usage:
  bash survey/sas-assess-autologon.sh --manifest targets.csv [options]
  bash survey/sas-assess-autologon.sh --local [options]

Options:
  --manifest PATH         Input manifest CSV (HostName column)
  --output PATH           Output assessment CSV
  --dashboard PATH        Output dashboard HTML (default: sibling of CSV)
  --no-dashboard          Skip dashboard rendering
  --pass-thru             Print output CSV after writing
  --open                  Open dashboard HTML when rendering completes
  --ad-live               Query AD via survey/sas-ad-identity-export.ps1
  --ad-output PATH        Path for generated AD evidence CSV
  --local                 Assess local workstation registry only
  --fixture-dry-run       Deterministic fixture output for CI (no reg.exe)
  -h, --help              Show help

Safety:
  Read-only. No endpoint or AD mutation.
USAGE
}

fail(){ echo "[autologon-assess] ERROR: $*" >&2; exit 1; }
log(){ echo "[autologon-assess] $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="${2:?missing --manifest value}"; shift 2 ;;
    --output) OUTPUT="${2:?missing --output value}"; shift 2 ;;
    --dashboard) DASHBOARD="${2:?missing --dashboard value}"; shift 2 ;;
    --no-dashboard) NO_DASHBOARD=1; shift ;;
    --pass-thru) PASS_THRU=1; shift ;;
    --open) OPEN=1; shift ;;
    --ad-live) AD_LIVE=1; shift ;;
    --ad-output) AD_OUTPUT="${2:?missing --ad-output value}"; shift 2 ;;
    --local) LOCAL=1; shift ;;
    --fixture-dry-run) FIXTURE_DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

command -v python3 >/dev/null 2>&1 || fail "python3 is required"
mkdir -p "$(dirname "$OUTPUT")"
[[ -z "$DASHBOARD" ]] && DASHBOARD="$(dirname "$OUTPUT")/autologon_dashboard.html"

if [[ "$LOCAL" -eq 1 && -n "$MANIFEST" ]]; then
  fail "Use either --local or --manifest, not both"
fi
if [[ "$LOCAL" -eq 0 && -z "$MANIFEST" && "$FIXTURE_DRY_RUN" -eq 0 ]]; then
  fail "--manifest is required unless --local is used"
fi
if [[ -n "$MANIFEST" && ! -f "$MANIFEST" ]]; then
  fail "Manifest not found: $MANIFEST"
fi

PROBE_JSON="$(mktemp "${TMPDIR:-/tmp}/sas-autologon-probes.XXXXXX")"
trap 'rm -f "$PROBE_JSON"' EXIT

if [[ "$FIXTURE_DRY_RUN" -eq 1 ]]; then
  log "Fixture dry-run mode — skipping live registry probes"
  printf '[]' > "$PROBE_JSON"
elif [[ "$LOCAL" -eq 1 ]]; then
  log "Local workstation assessment"
  python3 - "$PROBE_JSON" <<'PY'
import json, os, subprocess, sys
out = sys.argv[1]
host = ""
for cmd in (["hostname.exe"], ["cmd.exe", "/c", "hostname"]):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if p.returncode == 0 and p.stdout.strip():
            host = p.stdout.strip().splitlines()[-1].strip()
            break
    except Exception:
        pass
if not host:
    host = os.environ.get("COMPUTERNAME", "LOCALHOST")

def reg_val(root, name):
    try:
        p = subprocess.run(
            ["reg.exe", "QUERY", root, "/v", name],
            capture_output=True, text=True, timeout=20,
        )
        if p.returncode != 0:
            return "", p.stdout + p.stderr
        for line in p.stdout.splitlines():
            if name in line and "REG_" in line:
                parts = line.split(None, 2)
                if len(parts) >= 3:
                    return parts[-1].strip(), p.stdout.strip()
        return "", p.stdout.strip()
    except Exception as exc:
        return "", str(exc)

post_val, post_raw = reg_val(r"HKLM\SOFTWARE\NSLIJHS\PostInstall", "SetAutoLogon")
auto_val, win_raw_auto = reg_val(r"HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon", "AutoAdminLogon")
user_val, win_raw_user = reg_val(r"HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon", "DefaultUserName")
raw = "\n".join(x for x in [post_raw, win_raw_auto, win_raw_user] if x)
row = {
    "HostName": host,
    "Reachability": "local",
    "AdminShareOk": "n/a",
    "PostInstall_SetAutoLogon": post_val,
    "PostInstall_Raw": post_raw,
    "Winlogon_AutoAdminLogon": auto_val,
    "Winlogon_DefaultUserName": user_val,
    "ProbeMethod": "local_reg_query",
    "ProbeError": "",
}
with open(out, "w", encoding="utf-8") as handle:
    json.dump([row], handle)
PY
else
  log "Remote registry assessment for manifest: $MANIFEST"
  python3 - "$MANIFEST" "$PROBE_JSON" <<'PY'
import csv, json, subprocess, sys

manifest, out = sys.argv[1:3]

def first(row, names):
    lower = {str(k).strip().lower(): (v or "").strip() for k, v in row.items() if k is not None}
    for name in names:
        val = lower.get(name.lower(), "")
        if val:
            return val
    return ""

def ping_ok(host):
    for cmd in (
        ["ping.exe", "-n", "1", "-w", "2000", host],
        ["ping", "-c", "1", "-W", "2", host],
    ):
        try:
            if subprocess.run(cmd, capture_output=True, timeout=15).returncode == 0:
                return True
        except Exception:
            pass
    return False

def admin_share_ok(host):
    unc = fr"\\{host}\c$"
    try:
        p = subprocess.run(
            ["cmd.exe", "/c", f'if exist "{unc}\\nul" (echo OK)'],
            capture_output=True, text=True, timeout=20,
        )
        return p.returncode == 0 and "OK" in (p.stdout or "")
    except Exception:
        return False

def reg_query(host, subkey, value):
    path = fr"\\{host}\HKLM\{subkey}"
    try:
        p = subprocess.run(
            ["reg.exe", "QUERY", path, "/v", value],
            capture_output=True, text=True, timeout=30,
        )
        raw = (p.stdout or "") + (p.stderr or "")
        if p.returncode != 0:
            return "", raw.strip(), f"reg_exit_{p.returncode}"
        for line in p.stdout.splitlines():
            if value in line and "REG_" in line:
                parts = line.split(None, 2)
                if len(parts) >= 3:
                    return parts[-1].strip(), raw.strip(), ""
        return "", raw.strip(), "value_not_found"
    except Exception as exc:
        return "", str(exc), "reg_exception"

rows = []
with open(manifest, newline="", encoding="utf-8-sig") as handle:
    for raw in csv.DictReader(handle):
        host = first(raw, ["HostName", "Hostname", "Host", "Target", "ComputerName"])
        if not host:
            continue
        reachable = "online" if ping_ok(host) else "offline"
        admin_ok = "yes" if reachable == "online" and admin_share_ok(host) else "no"
        probe_method = "remote_reg_admin_share"
        probe_error = ""
        post_val = post_raw = auto_val = user_val = ""
        if reachable == "offline":
            probe_method = "ping_failed"
        elif admin_ok != "yes":
            probe_method = "admin_share_failed"
        else:
            post_val, post_raw, err1 = reg_query(host, r"SOFTWARE\NSLIJHS\PostInstall", "SetAutoLogon")
            auto_val, raw_auto, err2 = reg_query(host, r"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon", "AutoAdminLogon")
            user_val, raw_user, err3 = reg_query(host, r"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon", "DefaultUserName")
            post_raw = "\n".join(x for x in [post_raw, raw_auto, raw_user] if x)
            probe_error = err1 or err2 or err3
            if probe_error and not post_val and not auto_val and not user_val:
                probe_method = "remote_reg_failed"
        rows.append({
            "HostName": host,
            "Reachability": reachable,
            "AdminShareOk": admin_ok,
            "PostInstall_SetAutoLogon": post_val,
            "PostInstall_Raw": post_raw,
            "Winlogon_AutoAdminLogon": auto_val,
            "Winlogon_DefaultUserName": user_val,
            "ProbeMethod": probe_method,
            "ProbeError": probe_error,
        })

with open(out, "w", encoding="utf-8") as handle:
    json.dump(rows, handle)
PY
fi

if [[ "$AD_LIVE" -eq 1 && -z "$AD_CSV" ]]; then
  AD_HELPER="survey/sas-ad-identity-export.ps1"
  [[ -f "$AD_HELPER" ]] || fail "AD helper not found: $AD_HELPER"
  [[ -z "$AD_OUTPUT" ]] && AD_OUTPUT="$(dirname "$OUTPUT")/autologon_ad_evidence.csv"
  PS_EXE=""
  if command -v powershell.exe >/dev/null 2>&1; then PS_EXE="powershell.exe"; fi
  if [[ -z "$PS_EXE" ]] && command -v pwsh >/dev/null 2>&1; then PS_EXE="pwsh"; fi
  if [[ -z "$PS_EXE" ]] && command -v powershell >/dev/null 2>&1; then PS_EXE="powershell"; fi
  if [[ -z "$PS_EXE" ]]; then
    log "AD live requested, but no PowerShell runtime is available. Continuing without AD evidence."
  else
    AD_ARGS=(-NoProfile -ExecutionPolicy Bypass -File "$AD_HELPER" -Manifest "$MANIFEST" -Output "$AD_OUTPUT" -IncludeComputerOU -LookupHostnameAsUser)
    if "$PS_EXE" "${AD_ARGS[@]}"; then
      AD_CSV="$AD_OUTPUT"
      log "AD evidence CSV generated: $AD_CSV"
    else
      log "AD evidence helper failed. Continuing without AD evidence."
    fi
  fi
fi

python3 - "$MANIFEST" "$PROBE_JSON" "$AD_CSV" "$OUTPUT" "$FIXTURE_DRY_RUN" "$LOCAL" <<'PY'
import csv, datetime as dt, json, sys
from pathlib import Path

manifest, probe_json, ad_csv, output, dry_flag, local_flag = sys.argv[1:7]
dry = dry_flag == "1"
local_mode = local_flag == "1"

FIELDS = [
    "Timestamp", "HostName", "Reachability", "AdminShareOk",
    "PostInstall_SetAutoLogon", "PostInstall_Raw",
    "Winlogon_AutoAdminLogon", "Winlogon_DefaultUserName", "Hostname_User_Match",
    "AD_User_Found", "AD_Computer_OU", "Legacy_OU_Warning",
    "OverallStatus", "AssessmentStage", "ProbeMethod", "EvidenceDetail", "RevisitRecommendation",
]

def first(row, names):
    lower = {str(k).strip().lower(): (v or "").strip() for k, v in row.items() if k is not None}
    for name in names:
        val = lower.get(name.lower(), "")
        if val:
            return val
    return ""

def short_host(hostname):
    return (hostname or "").strip().split(".")[0].upper()

def has_intent(post_val, post_raw):
    blob = f"{post_val} {post_raw}".upper().replace("_", "").replace(" ", "")
    return "AUTOLOGONYES" in blob

def hostname_user_match(hostname, default_user):
    if not default_user:
        return "no"
    return "yes" if short_host(default_user) == short_host(hostname) else "no"

def winlogon_auto_enabled(auto_val):
    return str(auto_val or "").strip() in {"1", "0x1"}

def winlogon_configured(auto_val, default_user, hostname):
    return winlogon_auto_enabled(auto_val) and hostname_user_match(hostname, default_user) == "yes"

def ou_under_managed_shared(ou_path):
    if not ou_path:
        return False
    norm = ou_path.replace("\\", "/").upper()
    return "MANAGED_SHARED" in norm

def legacy_ou_warning(ou_path, warning):
    if warning:
        return warning
    if not ou_path:
        return ""
    legacy_patterns = ["FORBIDDEN", "LEGACY", "PHASED OUT", "OLD WORKSTATIONS"]
    up = ou_path.upper()
    for pat in legacy_patterns:
        if pat in up:
            return "LEGACY OU -- review Managed/Managed_Shared placement"
    return ""

def load_ad_index(path):
    index = {}
    if not path or not Path(path).exists():
        return index
    with open(path, newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            host = first(row, ["Target", "HostName", "Hostname", "ADHostname"])
            if not host:
                continue
            index[short_host(host)] = row
    return index

def fixture_probe(host):
    token = short_host(host)
    scenarios = {
        "SAMPLE301MSO001": dict(
            Reachability="online", AdminShareOk="yes", PostInstall_SetAutoLogon="Autologon_NO",
            PostInstall_Raw="SetAutoLogon    REG_SZ    Autologon_NO",
            Winlogon_AutoAdminLogon="0", Winlogon_DefaultUserName="",
            AD_User_Found="n/a", AD_Computer_OU="OU=Clinic,OU=Managed,DC=sample,DC=local",
            Legacy_OU_Warning="", ProbeMethod="fixture_dry_run", ProbeError="",
        ),
        "SAMPLE301MSO002": dict(
            Reachability="online", AdminShareOk="yes", PostInstall_SetAutoLogon="Autologon_YES",
            PostInstall_Raw="SetAutoLogon    REG_SZ    Autologon_YES",
            Winlogon_AutoAdminLogon="1", Winlogon_DefaultUserName="SAMPLE301MSO002",
            AD_User_Found="yes", AD_Computer_OU="OU=Pavilion,OU=Managed_Shared,DC=sample,DC=local",
            Legacy_OU_Warning="", ProbeMethod="fixture_dry_run", ProbeError="",
        ),
        "SAMPLE301MSO003": dict(
            Reachability="online", AdminShareOk="yes", PostInstall_SetAutoLogon="Autologon_YES",
            PostInstall_Raw="SetAutoLogon    REG_SZ    Autologon_YES",
            Winlogon_AutoAdminLogon="0", Winlogon_DefaultUserName="",
            AD_User_Found="yes", AD_Computer_OU="OU=Pavilion,OU=Managed_Shared,DC=sample,DC=local",
            Legacy_OU_Warning="", ProbeMethod="fixture_dry_run", ProbeError="",
        ),
        "SAMPLE301MSO004": dict(
            Reachability="online", AdminShareOk="yes", PostInstall_SetAutoLogon="Autologon_YES",
            PostInstall_Raw="SetAutoLogon    REG_SZ    Autologon_YES",
            Winlogon_AutoAdminLogon="0", Winlogon_DefaultUserName="",
            AD_User_Found="no", AD_Computer_OU="OU=Pavilion,OU=Managed_Shared,DC=sample,DC=local",
            Legacy_OU_Warning="", ProbeMethod="fixture_dry_run", ProbeError="",
        ),
        "SAMPLE301MSO005": dict(
            Reachability="online", AdminShareOk="yes", PostInstall_SetAutoLogon="Autologon_YES",
            PostInstall_Raw="SetAutoLogon    REG_SZ    Autologon_YES",
            Winlogon_AutoAdminLogon="1", Winlogon_DefaultUserName="WRONGUSER",
            AD_User_Found="yes", AD_Computer_OU="OU=Pavilion,OU=Managed_Shared,DC=sample,DC=local",
            Legacy_OU_Warning="", ProbeMethod="fixture_dry_run", ProbeError="",
        ),
        "SAMPLE301MSO006": dict(
            Reachability="online", AdminShareOk="yes", PostInstall_SetAutoLogon="Autologon_YES",
            PostInstall_Raw="SetAutoLogon    REG_SZ    Autologon_YES",
            Winlogon_AutoAdminLogon="1", Winlogon_DefaultUserName="SAMPLE301MSO006",
            AD_User_Found="yes", AD_Computer_OU="OU=Legacy,OU=Workstations,DC=sample,DC=local",
            Legacy_OU_Warning="LEGACY OU -- must be moved to Managed_Shared",
            ProbeMethod="fixture_dry_run", ProbeError="",
        ),
        "SAMPLE301MSO007": dict(
            Reachability="offline", AdminShareOk="no", PostInstall_SetAutoLogon="",
            PostInstall_Raw="", Winlogon_AutoAdminLogon="", Winlogon_DefaultUserName="",
            AD_User_Found="unknown", AD_Computer_OU="", Legacy_OU_Warning="",
            ProbeMethod="fixture_dry_run", ProbeError="",
        ),
        "SAMPLE301MSO008": dict(
            Reachability="online", AdminShareOk="yes", PostInstall_SetAutoLogon="",
            PostInstall_Raw="ERROR: access denied", Winlogon_AutoAdminLogon="", Winlogon_DefaultUserName="",
            AD_User_Found="unknown", AD_Computer_OU="", Legacy_OU_Warning="",
            ProbeMethod="remote_reg_failed", ProbeError="reg_exit_5",
        ),
    }
    return scenarios.get(token, dict(
        Reachability="online", AdminShareOk="yes", PostInstall_SetAutoLogon="Autologon_NO",
        PostInstall_Raw="", Winlogon_AutoAdminLogon="0", Winlogon_DefaultUserName="",
        AD_User_Found="unknown", AD_Computer_OU="", Legacy_OU_Warning="",
        ProbeMethod="fixture_dry_run", ProbeError="",
    ))

def classify(host, probe, ad_row):
    reach = probe.get("Reachability", "unknown")
    admin_ok = probe.get("AdminShareOk", "no")
    post_val = probe.get("PostInstall_SetAutoLogon", "")
    post_raw = probe.get("PostInstall_Raw", "")
    auto_val = probe.get("Winlogon_AutoAdminLogon", "")
    user_val = probe.get("Winlogon_DefaultUserName", "")
    probe_method = probe.get("ProbeMethod", "unknown")
    probe_error = probe.get("ProbeError", "")

    ad_user = probe.get("AD_User_Found", "")
    ad_ou = probe.get("AD_Computer_OU", "")
    legacy = probe.get("Legacy_OU_Warning", "")

    if ad_row:
        ad_user = first(ad_row, ["ADUserFound", "AD_User_Found"]) or ad_user
        ad_ou = first(ad_row, ["ComputerOU", "AD_Computer_OU", "DirectoryPath", "OUPath"]) or ad_ou
        legacy = first(ad_row, ["LegacyOUWarning", "Legacy_OU_Warning", "OUPolicyWarning"]) or legacy
        if not ad_user:
            status = first(ad_row, ["ADUserStatus", "ADStatus"])
            ad_user = "yes" if status in {"ad_user_found", "ad_object_found"} else "no" if status in {"ad_user_missing", "ad_no_match"} else ad_user

    if reach == "offline" or (admin_ok == "no" and reach != "local"):
        return "unreachable", "transport", probe_method, "Host offline or admin share unavailable", "Retry when on-segment with admin credentials"

    if probe_error and probe_method in {"remote_reg_failed", "remote_reg_admin_share"} and not post_val and not auto_val:
        if "access denied" in (post_raw or "").lower() or probe_error:
            return "probe_failed", "registry", probe_method, post_raw or probe_error, "Verify admin share ACLs and remote registry access"

    intent = has_intent(post_val, post_raw)
    if not intent:
        return "shared_device", "postinstall", probe_method, "PostInstall SetAutoLogon lacks Autologon_YES", "No auto-logon setup required"

    if ad_user == "no":
        return "account_missing", "ad_user", probe_method, f"No AD user found for hostname {short_host(host)}", "Create/provision hostname user before running NW_AutoLogon_Setup"

    if winlogon_configured(auto_val, user_val, host):
        if ad_ou and not ou_under_managed_shared(ad_ou):
            return "ou_mismatch", "ad_ou", probe_method, f"Computer OU not under Managed_Shared: {ad_ou}", "Move computer to Managed_Shared OU per policy"
        if legacy:
            return "ou_mismatch", "ad_ou", probe_method, legacy, "Move computer to Managed_Shared OU per policy"
        return "autologon_ready", "complete", probe_method, "PostInstall intent, Winlogon, AD user, and OU aligned", "None"

    if winlogon_auto_enabled(auto_val) and hostname_user_match(host, user_val) == "no":
        return "setup_incomplete", "winlogon", probe_method, f"DefaultUserName={user_val} does not match hostname", "Re-run NW_AutoLogon_Setup or correct Winlogon keys"

    if ad_user in {"yes", "unknown"} and not winlogon_auto_enabled(auto_val):
        return "intent_only", "postinstall", probe_method, "PostInstall intent recorded; Winlogon not configured yet", "Run NW_AutoLogon_Setup_x64.exe per SSUH_Pavilion_Install gate"

    return "setup_incomplete", "winlogon", probe_method, "Auto-logon intent present but Winlogon incomplete", "Complete auto-logon setup and re-assess"

manifest_hosts = []
if manifest and Path(manifest).exists():
    with open(manifest, newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            host = first(row, ["HostName", "Hostname", "Host", "Target", "ComputerName"])
            if host:
                manifest_hosts.append(host)

if local_mode and not manifest_hosts:
    with open(probe_json, encoding="utf-8") as handle:
        probes = json.load(handle)
    manifest_hosts = [p.get("HostName", "LOCALHOST") for p in probes]

probe_map = {}
if dry:
    for host in manifest_hosts:
        probe_map[short_host(host)] = fixture_probe(host)
else:
    with open(probe_json, encoding="utf-8") as handle:
        for item in json.load(handle):
            probe_map[short_host(item.get("HostName", ""))] = item

ad_index = load_ad_index(ad_csv)
rows = []
now = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

for host in manifest_hosts:
    probe = probe_map.get(short_host(host), {})
    ad_row = ad_index.get(short_host(host), {})
    status, stage, method, detail, revisit = classify(host, probe, ad_row)
    rows.append({
        "Timestamp": now,
        "HostName": host,
        "Reachability": probe.get("Reachability", "unknown"),
        "AdminShareOk": probe.get("AdminShareOk", "unknown"),
        "PostInstall_SetAutoLogon": probe.get("PostInstall_SetAutoLogon", ""),
        "PostInstall_Raw": probe.get("PostInstall_Raw", ""),
        "Winlogon_AutoAdminLogon": probe.get("Winlogon_AutoAdminLogon", ""),
        "Winlogon_DefaultUserName": probe.get("Winlogon_DefaultUserName", ""),
        "Hostname_User_Match": hostname_user_match(host, probe.get("Winlogon_DefaultUserName", "")),
        "AD_User_Found": probe.get("AD_User_Found") or first(ad_row, ["ADUserFound", "AD_User_Found"]) or "unknown",
        "AD_Computer_OU": probe.get("AD_Computer_OU") or first(ad_row, ["ComputerOU", "AD_Computer_OU", "DirectoryPath", "OUPath"]) or "",
        "Legacy_OU_Warning": legacy_ou_warning(
            probe.get("AD_Computer_OU") or first(ad_row, ["ComputerOU", "AD_Computer_OU", "DirectoryPath", "OUPath"]),
            probe.get("Legacy_OU_Warning") or first(ad_row, ["LegacyOUWarning", "Legacy_OU_Warning", "OUPolicyWarning"]),
        ),
        "OverallStatus": status,
        "AssessmentStage": stage,
        "ProbeMethod": method if not dry else probe.get("ProbeMethod", method),
        "EvidenceDetail": detail,
        "RevisitRecommendation": revisit,
    })

Path(output).parent.mkdir(parents=True, exist_ok=True)
with open(output, "w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=FIELDS, quoting=csv.QUOTE_ALL, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
PY

if [[ "$NO_DASHBOARD" -eq 0 ]]; then
  RENDERER="deployment-audit/sas-render-autologon-dashboard.py"
  if [[ -f "$RENDERER" ]]; then
    python3 "$RENDERER" --input "$OUTPUT" --output "$DASHBOARD"
    log "Dashboard written: $DASHBOARD"
    if [[ "$OPEN" -eq 1 ]]; then
      if command -v cmd.exe >/dev/null 2>&1; then
        cmd.exe /c start "" "$(cygpath -w "$DASHBOARD" 2>/dev/null || echo "$DASHBOARD")" >/dev/null 2>&1 || true
      elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$DASHBOARD" >/dev/null 2>&1 || true
      fi
    fi
  else
    log "Dashboard renderer not found: $RENDERER"
  fi
fi

printf '%s\n' "$OUTPUT"
[[ -n "$DASHBOARD" && "$NO_DASHBOARD" -eq 0 ]] && printf '%s\n' "$DASHBOARD"
[[ "$PASS_THRU" -eq 1 ]] && cat "$OUTPUT" || true
