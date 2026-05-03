#!/usr/bin/env bash
# SysAdminSuite — sas-populate-tracker.sh
# Upserts discovered software entries into Config/sources.yaml.
# Accepts a software_superset.csv (from Inventory-Software.ps1) or connects
# to a host to pull its installed software list.
#
# For each discovered app not already tracked, appends a new entry with
# unmanaged: true, the app's display name, and detected registry key.
# Existing entries are updated with detect_value if currently empty.
# A backup (sources.yaml.bak) is always written before modifying.
#
# Usage:
#   ./bash/apps/sas-populate-tracker.sh --from-csv PATH [options]
#   ./bash/apps/sas-populate-tracker.sh --from-host HOSTNAME [options]

set -euo pipefail

FROM_CSV=""
FROM_HOST=""
SOURCES_YAML="Config/sources.yaml"
DRY_RUN=0
MIN_MATCH_SCORE=80  # fuzzy match threshold (0-100) for name deduplication

usage() {
  cat <<'USAGE'
SysAdminSuite — Software Tracker Populator

Usage:
  ./bash/apps/sas-populate-tracker.sh --from-csv PATH [options]
  ./bash/apps/sas-populate-tracker.sh --from-host HOSTNAME [options]

Options:
  --from-csv PATH     Path to software_superset.csv (from Inventory-Software.ps1)
  --from-host HOST    Hostname to query for installed software via WMI/remote (requires PowerShell)
  --yaml PATH         Path to sources.yaml to update (default: Config/sources.yaml)
  --dry-run           Print what would change without writing
  -h, --help          Show help

Behaviour:
  - Reads the existing sources.yaml and builds a set of known app names.
  - For each discovered app in the CSV/host output:
      * If a match exists by name, update detect_value if currently empty.
      * If no match, append a new entry with unmanaged: true.
  - Writes sources.yaml.bak before any modification.
  - The YAML file is rewritten in place preserving comments and structure.

CSV expected columns (software_superset.csv output from Inventory-Software.ps1):
  Name, Version, Publisher, DetectType, DetectValue, Host, Timestamp
USAGE
}

fail() { printf '[sas-populate] ERROR: %s\n' "$*" >&2; exit 1; }
log()  { printf '[sas-populate] %s\n' "$*" >&2; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-csv)  FROM_CSV="${2:?missing value for --from-csv}"; shift 2 ;;
    --from-host) FROM_HOST="${2:?missing value for --from-host}"; shift 2 ;;
    --yaml)      SOURCES_YAML="${2:?missing value for --yaml}"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    --) shift; break ;;
    -*) fail "Unknown option: $1" ;;
    *) fail "Unexpected argument: $1" ;;
  esac
done

[[ -n "$FROM_CSV" || -n "$FROM_HOST" ]] || fail "Provide --from-csv or --from-host"
has_cmd python3 || fail "python3 is required"
[[ -f "$SOURCES_YAML" ]] || fail "sources.yaml not found: $SOURCES_YAML"

# ---------------------------------------------------------------------------
# If --from-host: use PowerShell remoting to collect installed software
# ---------------------------------------------------------------------------
TEMP_CSV=""
if [[ -n "$FROM_HOST" ]]; then
  [[ "$FROM_HOST" =~ ^[A-Za-z0-9_.\-]+$ ]] || fail "--from-host contains invalid characters: $FROM_HOST"
  has_cmd pwsh || has_cmd powershell || fail "PowerShell (pwsh) is required for --from-host"
  PWSH="$(command -v pwsh 2>/dev/null || command -v powershell)"
  TEMP_CSV="$(mktemp /tmp/sas-inventory-XXXXXX.csv)"
  log "Collecting installed software from host: $FROM_HOST"
  "$PWSH" -NoProfile -Command "
    \$arp = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    \$rows = Invoke-Command -ComputerName '$FROM_HOST' -ScriptBlock {
      param(\$hives)
      foreach(\$h in \$hives){
        Get-ChildItem \$h -EA SilentlyContinue | ForEach-Object {
          \$p = Get-ItemProperty \$_.PSPath -EA SilentlyContinue
          if(\$p.DisplayName){
            [pscustomobject]@{Name=\$p.DisplayName;Version=\$p.DisplayVersion;Publisher=\$p.Publisher;DetectType='regkey';DetectValue=\$_.Name;Host='$FROM_HOST';Timestamp=(Get-Date -Format 's')}
          }
        }
      }
    } -ArgumentList (,\$arp)
    \$rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path '$TEMP_CSV'
  " 2>&1 || fail "Failed to collect software from $FROM_HOST"
  FROM_CSV="$TEMP_CSV"
  log "Collected software list written to: $TEMP_CSV"
fi

# ---------------------------------------------------------------------------
# Main upsert logic via python3
# ---------------------------------------------------------------------------
python3 - "$SOURCES_YAML" "$FROM_CSV" "$DRY_RUN" <<'PY'
import sys, csv, os, re, shutil
from datetime import datetime

yaml_path  = sys.argv[1]
csv_path   = sys.argv[2]
dry_run    = sys.argv[3] == '1'

# ---- Read existing sources.yaml as raw text (preserve formatting) ----
with open(yaml_path, encoding='utf-8-sig') as f:
    original_content = f.read()

# ---- Parse existing app names and detect_values ----
def parse_sources_yaml(path):
    with open(path, encoding='utf-8-sig') as f:
        lines = f.readlines()
    apps = []; i = 0; n = len(lines)

    def strip_comment(s):
        result = []; in_sq = False
        for ch in s:
            if ch == "'" and not in_sq: in_sq = True; result.append(ch); continue
            if ch == "'" and in_sq: in_sq = False; result.append(ch); continue
            if ch == '#' and not in_sq: break
            result.append(ch)
        return ''.join(result).rstrip()

    def unquote(s):
        s = s.strip()
        if (s.startswith('"') and s.endswith('"')) or (s.startswith("'") and s.endswith("'")):
            return s[1:-1]
        return s

    def indent_of(line): return len(line) - len(line.lstrip())

    while i < n:
        raw = lines[i]; line = strip_comment(raw).rstrip(); stripped = line.lstrip()
        if not stripped or stripped.startswith('#'): i += 1; continue
        ind = indent_of(raw)
        if ind == 0 and ':' in stripped:
            key = stripped.split(':', 1)[0].strip()
            if key == 'apps':
                i += 1
                while i < n:
                    raw2 = lines[i]; line2 = strip_comment(raw2).rstrip(); stripped2 = line2.lstrip()
                    if not stripped2 or stripped2.startswith('#'): i += 1; continue
                    ind2 = indent_of(raw2)
                    if ind2 == 0 and not stripped2.startswith('-'): break
                    if stripped2.startswith('- ') and ind2 == 2:
                        app = {}
                        rest = stripped2[2:].strip()
                        if ':' in rest:
                            k2, v2 = rest.split(':', 1); app[k2.strip()] = unquote(v2.strip())
                        i += 1
                        while i < n:
                            raw3 = lines[i]; line3 = strip_comment(raw3).rstrip(); stripped3 = line3.lstrip()
                            if not stripped3 or stripped3.startswith('#'): i += 1; continue
                            ind3 = indent_of(raw3)
                            if ind3 <= 2 and ind3 != 4: break
                            if ':' in stripped3:
                                k3, v3 = stripped3.split(':', 1); app[k3.strip()] = unquote(v3.strip())
                            i += 1
                        apps.append(app)
                    else: i += 1
                continue
        i += 1
    return apps

existing_apps = parse_sources_yaml(yaml_path)
existing_names_lower = {a.get('name','').lower(): a for a in existing_apps}

# ---- Read discovered software CSV ----
discovered = []
with open(csv_path, newline='', encoding='utf-8-sig') as f:
    reader = csv.DictReader(f)
    for row in reader:
        name = (row.get('Name') or row.get('name') or '').strip()
        if not name: continue
        discovered.append({
            'name':         name,
            'version':      (row.get('Version') or row.get('version') or '').strip(),
            'publisher':    (row.get('Publisher') or row.get('publisher') or '').strip(),
            'detect_type':  (row.get('DetectType') or row.get('detect_type') or 'regkey').strip(),
            'detect_value': (row.get('DetectValue') or row.get('detect_value') or '').strip(),
        })

print(f"[sas-populate] Discovered {len(discovered)} software entries from CSV")
print(f"[sas-populate] Existing tracked apps: {len(existing_apps)}")

new_entries  = []
updated      = []

for disc in discovered:
    name_lower = disc['name'].lower()
    if name_lower in existing_names_lower:
        # Existing entry — update detect_value if empty
        existing = existing_names_lower[name_lower]
        if not existing.get('detect_value') and disc['detect_value']:
            updated.append({
                'name': disc['name'],
                'detect_value': disc['detect_value'],
                'detect_type':  disc['detect_type'],
            })
    else:
        # New unmanaged entry
        new_entries.append(disc)

print(f"[sas-populate] New (unmanaged): {len(new_entries)}")
print(f"[sas-populate] Detect-value updates: {len(updated)}")

if not new_entries and not updated:
    print("[sas-populate] Nothing to change.")
    sys.exit(0)

if dry_run:
    print("\n[DRY-RUN] Would add these unmanaged entries:")
    for e in new_entries:
        print(f"  + {e['name']}  (detect: {e['detect_type']}={e['detect_value']})")
    print("\n[DRY-RUN] Would update detect_value for:")
    for u in updated:
        print(f"  ~ {u['name']}  -> {u['detect_value']}")
    sys.exit(0)

# ---- Backup ----
bak_path = yaml_path + '.bak'
shutil.copy2(yaml_path, bak_path)
print(f"[sas-populate] Backup written: {bak_path}")

# ---- Apply detect_value updates (in-place text replacement) ----
content = original_content
for u in updated:
    # Find the app block and update detect_value
    # Simple pattern: find name line and then detect_value within next N lines
    name_escaped = re.escape(u['name'])
    # Single-quoted YAML: backslash is literal, only '' escapes a literal '
    dv_squoted = "'" + u['detect_value'].replace("'", "''") + "'"
    pattern = r'(  - name: [\'"]?' + name_escaped + r'[\'"]?.*?)(    detect_value: .*?\n)'
    replacement = r'\g<1>    detect_value: ' + dv_squoted + '\n'
    new_content, count = re.subn(pattern, replacement, content, count=1, flags=re.DOTALL)
    if count:
        content = new_content
        print(f"[sas-populate] Updated detect_value for: {u['name']}")

# ---- Append new unmanaged entries ----
stamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
def yaml_squote(s):
    """Wrap a string in YAML single-quoted scalar.
    Backslash is literal (no escape processing). Only '' escapes a literal '."""
    return "'" + str(s).replace("'", "''") + "'"

new_yaml_blocks = []
for e in new_entries:
    name_y    = yaml_squote(e['name'])
    version_y = yaml_squote(e['version'])
    dv_y      = yaml_squote(e['detect_value'])
    block = f"""
  - name: {name_y}
    source: url
    repo: ""
    strategy: pinned
    version: {version_y}
    url_template: ""
    asset_regex: ""
    filename_template: ""
    type: exe
    silent_args: ""
    detect_type: {e['detect_type']}
    detect_value: {dv_y}
    add_to_path: ""
    post_install: ""
    allow_domains: ""
    unmanaged: true
    discovered_at: '{stamp}'
"""
    new_yaml_blocks.append(block)
    print(f"[sas-populate] Added unmanaged: {e['name']}")

if new_yaml_blocks:
    # Append before final newline
    content = content.rstrip('\n') + '\n' + ''.join(new_yaml_blocks)

with open(yaml_path, 'w', encoding='utf-8') as f:
    f.write(content)

print(f"[sas-populate] sources.yaml updated. Added: {len(new_entries)}, Updated: {len(updated)}")
PY

# Cleanup temp CSV if created for --from-host
[[ -n "$TEMP_CSV" && -f "$TEMP_CSV" ]] && rm -f "$TEMP_CSV"

log "Done."
