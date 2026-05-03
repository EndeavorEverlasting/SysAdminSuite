#!/usr/bin/env bash
# SysAdminSuite — sas-list-apps.sh
# Reads Config/sources.yaml and lists apps with their key attributes.
# Supports named lists (deployment groups) defined in sources.yaml lists: section.
#
# Usage:
#   ./bash/apps/sas-list-apps.sh [--list LIST_NAME] [--json] [--yaml PATH]
#
# Examples:
#   ./bash/apps/sas-list-apps.sh
#   ./bash/apps/sas-list-apps.sh --list workstation-baseline
#   ./bash/apps/sas-list-apps.sh --list lab-tools --json

set -euo pipefail

SOURCES_YAML="Config/sources.yaml"
LIST_NAME=""
JSON_OUTPUT=0

usage() {
  cat <<'USAGE'
SysAdminSuite — App List Viewer

Usage:
  ./bash/apps/sas-list-apps.sh [options]

Options:
  --list NAME       Filter to a named deployment list (e.g. workstation-baseline)
  --json            Output as JSON array instead of formatted table
  --yaml PATH       Path to sources.yaml (default: Config/sources.yaml)
  -h, --help        Show this help

Named lists are defined in the lists: section of sources.yaml.
USAGE
}

fail() { printf '[sas-list-apps] ERROR: %s\n' "$*" >&2; exit 1; }
log()  { printf '[sas-list-apps] %s\n' "$*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) LIST_NAME="${2:?missing value for --list}"; shift 2 ;;
    --json) JSON_OUTPUT=1; shift ;;
    --yaml) SOURCES_YAML="${2:?missing value for --yaml}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) fail "Unknown option: $1" ;;
    *) fail "Unexpected argument: $1" ;;
  esac
done

command -v python3 >/dev/null 2>&1 || fail "python3 is required"
[[ -f "$SOURCES_YAML" ]] || fail "sources.yaml not found: $SOURCES_YAML"

python3 - "$SOURCES_YAML" "$LIST_NAME" "$JSON_OUTPUT" <<'PY'
import sys, json, re

yaml_path  = sys.argv[1]
list_name  = sys.argv[2]  # empty string = show all
json_mode  = sys.argv[3] == '1'

# ---------------------------------------------------------------------------
# Minimal YAML parser sufficient for the flat-mapping sources.yaml structure.
# Handles: top-level keys, lists of mappings, quoted/unquoted scalars,
# block sequences under lists: and apps:.
# ---------------------------------------------------------------------------

def parse_sources_yaml(path):
    with open(path, encoding='utf-8-sig') as f:
        lines = f.readlines()

    apps   = []
    lists  = {}
    i      = 0
    n      = len(lines)

    def strip_comment(s):
        # Remove inline # comments not inside quotes
        result = []
        in_sq = False
        for ch in s:
            if ch == "'" and not in_sq:
                in_sq = True; result.append(ch); continue
            if ch == "'" and in_sq:
                in_sq = False; result.append(ch); continue
            if ch == '#' and not in_sq:
                break
            result.append(ch)
        return ''.join(result).rstrip()

    def unquote(s):
        s = s.strip()
        if (s.startswith('"') and s.endswith('"')) or \
           (s.startswith("'") and s.endswith("'")):
            return s[1:-1]
        return s

    def indent_of(line):
        return len(line) - len(line.lstrip())

    # Find top-level section starts
    while i < n:
        raw = lines[i]
        line = strip_comment(raw).rstrip()
        stripped = line.lstrip()

        if not stripped or stripped.startswith('#'):
            i += 1; continue

        ind = indent_of(raw)

        # Top-level keys (indent 0)
        if ind == 0 and ':' in stripped:
            key = stripped.split(':', 1)[0].strip()

            if key == 'apps':
                i += 1
                # parse list of app mappings
                while i < n:
                    raw2 = lines[i]
                    line2 = strip_comment(raw2).rstrip()
                    stripped2 = line2.lstrip()
                    if not stripped2 or stripped2.startswith('#'):
                        i += 1; continue
                    ind2 = indent_of(raw2)
                    if ind2 == 0 and not stripped2.startswith('-'):
                        break  # new top-level key
                    if stripped2.startswith('- ') and ind2 == 2:
                        # start of an app entry
                        app = {}
                        # first field on same line as '-'
                        rest = stripped2[2:].strip()
                        if ':' in rest:
                            k2, v2 = rest.split(':', 1)
                            app[k2.strip()] = unquote(v2.strip())
                        i += 1
                        # collect continuation fields (indent > 2)
                        while i < n:
                            raw3 = lines[i]
                            line3 = strip_comment(raw3).rstrip()
                            stripped3 = line3.lstrip()
                            if not stripped3 or stripped3.startswith('#'):
                                i += 1; continue
                            ind3 = indent_of(raw3)
                            if ind3 <= 2 and not (ind3 == 4):
                                break
                            if ':' in stripped3:
                                k3, v3 = stripped3.split(':', 1)
                                app[k3.strip()] = unquote(v3.strip())
                            i += 1
                        apps.append(app)
                    else:
                        i += 1
                continue

            elif key == 'lists':
                i += 1
                current_list_name = None
                while i < n:
                    raw2 = lines[i]
                    line2 = strip_comment(raw2).rstrip()
                    stripped2 = line2.lstrip()
                    if not stripped2 or stripped2.startswith('#'):
                        i += 1; continue
                    ind2 = indent_of(raw2)
                    if ind2 == 0 and not stripped2.startswith('-'):
                        break
                    if ind2 == 2 and ':' in stripped2 and not stripped2.startswith('-'):
                        # list name line e.g. "  workstation-baseline:"
                        current_list_name = stripped2.rstrip(':').strip()
                        lists[current_list_name] = []
                        i += 1; continue
                    if ind2 == 4 and stripped2.startswith('- ') and current_list_name:
                        app_name = stripped2[2:].strip().strip('"\'')
                        lists[current_list_name].append(app_name)
                        i += 1; continue
                    i += 1
                continue

        i += 1

    return {'apps': apps, 'lists': lists}

data     = parse_sources_yaml(yaml_path)
all_apps = data['apps']
all_lists= data['lists']

# Filter by named list
if list_name:
    if list_name not in all_lists:
        available = ', '.join(all_lists.keys()) if all_lists else '(none defined)'
        print(f"[sas-list-apps] ERROR: List '{list_name}' not found. Available: {available}", file=sys.stderr)
        sys.exit(1)
    wanted = set(all_lists[list_name])
    apps = [a for a in all_apps if a.get('name','') in wanted]
else:
    apps = all_apps

if json_mode:
    print(json.dumps(apps, indent=2))
    sys.exit(0)

# Table output
COL_WIDTHS = [30, 8, 8, 9, 7, 10, 8]
HEADERS    = ['Name', 'Source', 'Strategy', 'Version', 'Type', 'Detect', 'Managed']

def trunc(s, w):
    s = str(s or '')
    return s[:w-1] + '…' if len(s) > w else s.ljust(w)

sep = '+' + '+'.join('-' * (w + 2) for w in COL_WIDTHS) + '+'

def row(*vals):
    cells = [' ' + trunc(v, w) + ' ' for v, w in zip(vals, COL_WIDTHS)]
    return '|' + '|'.join(cells) + '|'

header_line = row(*HEADERS)
print()
if list_name:
    print(f"  List: {list_name}  ({len(apps)} app(s))")
else:
    print(f"  All apps  ({len(apps)} total)")
print()
print(sep)
print(header_line)
print(sep)
for a in apps:
    unmanaged = str(a.get('unmanaged', '')).lower() in ('true', '1', 'yes')
    managed_str = 'NO ⚠' if unmanaged else 'yes'
    detect = a.get('detect_type', '')
    print(row(
        a.get('name', ''),
        a.get('source', ''),
        a.get('strategy', ''),
        a.get('version', '') or '(latest)',
        a.get('type', ''),
        detect,
        managed_str,
    ))
print(sep)
print()

# If showing all, also print available lists
if not list_name and all_lists:
    print("  Named lists:")
    for lname, lmembers in all_lists.items():
        print(f"    {lname}  ({len(lmembers)} apps): {', '.join(lmembers)}")
    print()

PY
