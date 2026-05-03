#!/usr/bin/env bash
# SysAdminSuite — sas-stage-fileshare.sh
# Stages installers from the local software repo onto a target host's admin share.
# Verifies share reachability (mirrors sas-smb-readonly-recon.sh pattern) then
# copies matching installers into \\TARGET\C$\SoftwareRepo\staged\<LIST_NAME>\.
#
# Usage:
#   ./bash/apps/sas-stage-fileshare.sh --target HOSTNAME --list LIST_NAME [options]
#
# Examples:
#   ./bash/apps/sas-stage-fileshare.sh --target WKS001 --list workstation-baseline
#   ./bash/apps/sas-stage-fileshare.sh --target WKS001 --list lab-tools --repo-root /mnt/SoftwareRepo

set -euo pipefail

TARGET=""
LIST_NAME=""
SOURCES_YAML="Config/sources.yaml"
REPO_ROOT="${SAS_REPO_ROOT:-C:/SoftwareRepo}"
SHARE="C$"
STAGED_DIR="SoftwareRepo/staged"
SMB_USER="${SAS_SMB_USER:-}"
SMB_PASS="${SAS_SMB_PASS:-}"
SMB_DOMAIN="${SAS_SMB_DOMAIN:-}"
TIMEOUT=10
DRY_RUN=0
LOG_DIR="bash/apps/output"

usage() {
  cat <<'USAGE'
SysAdminSuite — Stage Installers to File Share

Usage:
  ./bash/apps/sas-stage-fileshare.sh --target HOSTNAME --list LIST_NAME [options]

Options:
  --target HOST       Target hostname (admin share \\HOST\C$ must be reachable)
  --list NAME         Named app list from sources.yaml (e.g. workstation-baseline)
  --yaml PATH         Path to sources.yaml (default: Config/sources.yaml)
  --repo-root PATH    Local path to software repo installers dir (default: C:/SoftwareRepo)
  --share NAME        Admin share name on target (default: C$)
  --smb-user USER     SMB username (or set SAS_SMB_USER)
  --smb-pass PASS     SMB password (or set SAS_SMB_PASS)
  --smb-domain DOM    SMB domain (or set SAS_SMB_DOMAIN)
  --timeout SEC       SMB timeout seconds (default: 10)
  --dry-run           Print what would be copied without copying
  --log-dir PATH      Output log directory (default: bash/apps/output)
  -h, --help          Show help

Environment variables:
  SAS_SMB_USER, SAS_SMB_PASS, SAS_SMB_DOMAIN, SAS_REPO_ROOT
USAGE
}

fail() { printf '[sas-stage] ERROR: %s\n' "$*" >&2; exit 1; }
log()  { printf '[sas-stage] %s\n' "$*" >&2; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)     TARGET="${2:?missing value for --target}"; shift 2 ;;
    --list)       LIST_NAME="${2:?missing value for --list}"; shift 2 ;;
    --yaml)       SOURCES_YAML="${2:?missing value for --yaml}"; shift 2 ;;
    --repo-root)  REPO_ROOT="${2:?missing value for --repo-root}"; shift 2 ;;
    --share)      SHARE="${2:?missing value for --share}"; shift 2 ;;
    --smb-user)   SMB_USER="${2:?missing value for --smb-user}"; shift 2 ;;
    --smb-pass)   SMB_PASS="${2:?missing value for --smb-pass}"; shift 2 ;;
    --smb-domain) SMB_DOMAIN="${2:?missing value for --smb-domain}"; shift 2 ;;
    --timeout)    TIMEOUT="${2:?missing value for --timeout}"; shift 2 ;;
    --dry-run)    DRY_RUN=1; shift ;;
    --log-dir)    LOG_DIR="${2:?missing value for --log-dir}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    --) shift; break ;;
    -*) fail "Unknown option: $1" ;;
    *) fail "Unexpected argument: $1" ;;
  esac
done

[[ -n "$TARGET" ]]    || fail "--target is required"
[[ -n "$LIST_NAME" ]] || fail "--list is required"
has_cmd python3        || fail "python3 is required"
[[ -f "$SOURCES_YAML" ]] || fail "sources.yaml not found: $SOURCES_YAML"

# Input validation — reject shell metacharacters in user-supplied values
[[ "$TARGET"    =~ ^[A-Za-z0-9_.\-]+$ ]] || fail "--target contains invalid characters: $TARGET"
[[ "$LIST_NAME" =~ ^[A-Za-z0-9_.\-]+$ ]] || fail "--list contains invalid characters: $LIST_NAME"

mkdir -p "$LOG_DIR"
STAMP="$(date '+%Y%m%d_%H%M%S')"
LOG_FILE="$LOG_DIR/sas-stage-${TARGET}-${LIST_NAME}-${STAMP}.log"

tee_log() { tee -a "$LOG_FILE"; }

# Write Python helper to temp file — avoids bash double-quote expansion issues
# that occur with python3 -c "$var" when Python code contains " characters.
_PY_HELPER="$(mktemp /tmp/sas-stage-XXXXXX.py)"
trap 'rm -f "$_PY_HELPER"' EXIT

cat > "$_PY_HELPER" << 'PYEOF'
import sys, json, os, glob

yaml_path = sys.argv[1]
list_name = sys.argv[2]

def parse_sources_yaml(path):
    with open(path, encoding='utf-8-sig') as f:
        lines = f.readlines()
    apps = []; lists = {}; i = 0; n = len(lines)

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
            elif key == 'lists':
                i += 1; cur = None
                while i < n:
                    raw2 = lines[i]; line2 = strip_comment(raw2).rstrip(); stripped2 = line2.lstrip()
                    if not stripped2 or stripped2.startswith('#'): i += 1; continue
                    ind2 = indent_of(raw2)
                    if ind2 == 0 and not stripped2.startswith('-'): break
                    if ind2 == 2 and ':' in stripped2 and not stripped2.startswith('-'):
                        cur = stripped2.rstrip(':').strip(); lists[cur] = []; i += 1; continue
                    if ind2 == 4 and stripped2.startswith('- ') and cur:
                        lists[cur].append(stripped2[2:].strip().strip("'\"")); i += 1; continue
                    i += 1
                continue
        i += 1
    return {'apps': apps, 'lists': lists}

data = parse_sources_yaml(yaml_path)
if list_name not in data['lists']:
    available = ', '.join(data['lists'].keys())
    print(f"ERROR:List '{list_name}' not found. Available: {available}", file=sys.stderr)
    sys.exit(1)

wanted = set(data['lists'][list_name])
result = []
for a in data['apps']:
    if a.get('name', '') in wanted:
        ft  = a.get('filename_template', '') or ''
        ver = a.get('version', '') or ''
        ft_resolved = ft.replace('{{version}}', ver)
        has_asset = '{{asset}}' in ft_resolved
        if has_asset:
            ft_resolved = ft_resolved.replace('{{asset}}', '*')
        result.append({
            'name':                 a.get('name', ''),
            'filename_template':    ft_resolved,
            'has_asset_placeholder': has_asset,
            'asset_regex':          a.get('asset_regex', '') or '',
            'type':                 a.get('type', ''),
            'strategy':             a.get('strategy', ''),
            'source':               a.get('source', ''),
        })
print(json.dumps(result))
PYEOF

{
log "Starting staging: target=$TARGET list=$LIST_NAME repo=$REPO_ROOT"
log "Log: $LOG_FILE"

# ---------------------------------------------------------------------------
# Resolve installer filenames for the named list via python3 (temp file)
# ---------------------------------------------------------------------------
INSTALLERS_JSON="$(python3 "$_PY_HELPER" "$SOURCES_YAML" "$LIST_NAME")"
APP_COUNT="$(python3 - "$INSTALLERS_JSON" <<'PY'
import sys, json; print(len(json.loads(sys.argv[1])))
PY
)"
log "Resolved $APP_COUNT app(s) in list '$LIST_NAME'"

# ---------------------------------------------------------------------------
# Verify admin share reachability
# ---------------------------------------------------------------------------
ADMIN_SHARE="//${TARGET}/${SHARE}"
DEST_PATH="${STAGED_DIR}/${LIST_NAME}"

smb_auth_args() {
  local args=()
  if [[ -n "$SMB_USER" ]]; then
    args+=(-U "${SMB_USER}%${SMB_PASS}")
  else
    args+=(-N)
  fi
  [[ -n "$SMB_DOMAIN" ]] && args+=(-W "$SMB_DOMAIN")
  printf '%s\0' "${args[@]}"
}

run_smb_cmd() {
  local cmd="$1"
  local args=() part
  while IFS= read -r -d '' part; do args+=("$part"); done < <(smb_auth_args)
  if has_cmd timeout; then
    timeout "$TIMEOUT" smbclient "$ADMIN_SHARE" "${args[@]}" -c "$cmd" 2>&1
  else
    smbclient "$ADMIN_SHARE" "${args[@]}" -c "$cmd" 2>&1
  fi
}

smb_put_file() {
  local local_file="$1" remote_path="$2"
  local args=() part
  while IFS= read -r -d '' part; do args+=("$part"); done < <(smb_auth_args)
  local remote_win="${remote_path//\//\\}"
  local remote_dir_win
  remote_dir_win="$(dirname "$remote_path" | sed 's|/|\\|g')"
  local cmd="mkdir \"${remote_dir_win}\"; put \"${local_file}\" \"${remote_win}\""
  if has_cmd timeout; then
    timeout "$TIMEOUT" smbclient "$ADMIN_SHARE" "${args[@]}" -c "$cmd" 2>&1
  else
    smbclient "$ADMIN_SHARE" "${args[@]}" -c "$cmd" 2>&1
  fi
}

# Determine copy method: smbclient preferred; robocopy/cmd.exe as Windows fallback.
# In non-dry-run mode, fail fast if neither is available.
COPY_METHOD=""
if has_cmd smbclient; then
  COPY_METHOD="smbclient"
elif has_cmd cmd.exe && cmd.exe /c "where robocopy" >/dev/null 2>&1; then
  COPY_METHOD="robocopy"
elif [[ "$DRY_RUN" -eq 1 ]]; then
  COPY_METHOD="dry-only"
  log "WARN: Neither smbclient nor robocopy available — dry-run mode only"
else
  fail "Neither smbclient nor cmd.exe/robocopy is available — cannot stage installers to $TARGET"
fi

if [[ "$COPY_METHOD" == "smbclient" ]]; then
  log "Checking admin share reachability via smbclient: $ADMIN_SHARE"
  RECON_OUT="$(run_smb_cmd "pwd" 2>&1 || true)"
  if echo "$RECON_OUT" | grep -Eiq 'NT_STATUS_ACCESS_DENIED|LOGON_FAILURE|Authentication'; then
    fail "Admin share access denied on $TARGET — check credentials"
  elif echo "$RECON_OUT" | grep -Eiq 'NT_STATUS_BAD_NETWORK_NAME|NT_STATUS_HOST_UNREACHABLE|Connection.*failed|timed out'; then
    fail "Admin share unreachable on $TARGET — check network/firewall"
  else
    log "Admin share reachable: $ADMIN_SHARE"
  fi
  if [[ "$DRY_RUN" -eq 0 ]]; then
    DEST_WIN="${DEST_PATH//\//\\}"
    run_smb_cmd "mkdir \"${DEST_WIN}\"" >/dev/null 2>&1 || true
    log "Ensured remote staged directory: ${DEST_PATH}"
  fi
elif [[ "$COPY_METHOD" == "robocopy" ]]; then
  log "Checking admin share reachability via cmd.exe: \\\\${TARGET}\\${SHARE}"
  RECON_OUT="$(cmd.exe /c "dir \"\\\\${TARGET}\\${SHARE}\"" 2>&1 || true)"
  if echo "$RECON_OUT" | grep -Eiq 'Access is denied|network path was not found|could not be found'; then
    fail "Admin share unreachable or access denied on $TARGET — check network/credentials"
  else
    log "Admin share reachable: \\\\${TARGET}\\${SHARE}"
  fi
fi

# ---------------------------------------------------------------------------
# Locate installer files locally and copy to staged share via smbclient put
# ---------------------------------------------------------------------------
REPO_INSTALLERS="${REPO_ROOT}/installers"
LOCAL_REPO_INSTALLERS="${REPO_INSTALLERS//\\//}"

if [[ ! -d "$LOCAL_REPO_INSTALLERS" ]]; then
  log "WARN: Local installers directory not found at '$LOCAL_REPO_INSTALLERS' — staging will report missing files"
fi

COPIED=0
FAILED=0
SKIPPED=0

# Read app list as newline-delimited JSON objects, extract fields with Python
# (pass JSON as argv to avoid heredoc+pipe stdin conflict)
while IFS= read -r APP_NAME <&3 && IFS= read -r APP_PATTERN <&4 && IFS= read -r APP_HAS_ASSET <&5 && IFS= read -r APP_ASSET_REGEX <&6; do
  NAME="$APP_NAME"
  PATTERN="$APP_PATTERN"
  HAS_ASSET="$APP_HAS_ASSET"
  ASSET_REGEX="$APP_ASSET_REGEX"

  if [[ -z "$PATTERN" && "$HAS_ASSET" != "1" ]]; then
    printf '  SKIP  %-32s — no filename_template\n' "$NAME"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  MATCH=""
  if [[ "$HAS_ASSET" == "1" ]]; then
    # {{asset}} entries: use asset_regex to match against files already in the local repo
    if [[ -z "$ASSET_REGEX" ]]; then
      printf '  SKIP  %-32s — {{asset}} with no asset_regex in sources.yaml\n' "$NAME"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    if [[ -d "$LOCAL_REPO_INSTALLERS" ]]; then
      MATCH="$(python3 - "$LOCAL_REPO_INSTALLERS" "$ASSET_REGEX" <<'PY'
import sys, os, re
dirp, rx_str = sys.argv[1], sys.argv[2]
try:
    rx = re.compile(rx_str, re.IGNORECASE)
    matches = sorted(f for f in os.listdir(dirp) if rx.search(f))
    if matches: print(os.path.join(dirp, matches[-1]))
except Exception: pass
PY
      )"
    fi
    if [[ -z "$MATCH" ]]; then
      printf '  MISS  %-32s — no file matching /%s/ in %s\n' "$NAME" "$ASSET_REGEX" "$LOCAL_REPO_INSTALLERS"
      FAILED=$((FAILED + 1))
      continue
    fi
  else
    if [[ -d "$LOCAL_REPO_INSTALLERS" ]]; then
      MATCH="$(ls -1 "${LOCAL_REPO_INSTALLERS}/${PATTERN}" 2>/dev/null | tail -1 || true)"
    fi
    if [[ -z "$MATCH" ]]; then
      printf '  MISS  %-32s — not found: %s/%s\n' "$NAME" "$LOCAL_REPO_INSTALLERS" "$PATTERN"
      FAILED=$((FAILED + 1))
      continue
    fi
  fi

  FNAME="$(basename "$MATCH")"
  SIZE_KB=$(( $(wc -c < "$MATCH") / 1024 ))
  SHA256="$(sha256sum "$MATCH" 2>/dev/null | cut -c1-16 || python3 -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest()[:16])" "$MATCH" 2>/dev/null || echo "n/a")"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '  DRY   %-32s — would copy %s (%s KB) sha256=%s\n' "$NAME" "$FNAME" "$SIZE_KB" "$SHA256"
    COPIED=$((COPIED + 1))
    continue
  fi

  REMOTE_FILE="${DEST_PATH}/${FNAME}"
  COPY_OK=0

  if [[ "$COPY_METHOD" == "smbclient" ]]; then
    PUT_OUT="$(smb_put_file "$MATCH" "$REMOTE_FILE" 2>&1 || true)"
    if echo "$PUT_OUT" | grep -iq 'putting file'; then
      COPY_OK=1
    elif echo "$PUT_OUT" | grep -Eiq 'NT_STATUS_|Error|failed'; then
      printf '  FAIL  %-32s — smbclient error: %s\n' "$NAME" "$PUT_OUT"
      FAILED=$((FAILED + 1))
      continue
    else
      COPY_OK=1
    fi

  elif [[ "$COPY_METHOD" == "robocopy" ]]; then
    # Build Windows paths without relying on POSIX dirname (which ignores backslashes).
    # Source dir: convert Unix path of local file's directory to Windows notation.
    LOCAL_DIR_WIN="$(cygpath -w "$(dirname "$MATCH")" 2>/dev/null || printf '%s' "$(dirname "$MATCH")" | sed 's|/|\\|g;s|^\\|C:\\|')"
    # Destination dir: DEST_PATH is already the staged dir (no filename), convert to UNC.
    DEST_DIR_WIN="\\\\${TARGET}\\${SHARE}\\${DEST_PATH//\//\\}"
    RC=0
    cmd.exe /c "robocopy \"${LOCAL_DIR_WIN}\" \"${DEST_DIR_WIN}\" \"${FNAME}\" /NP /NJH /NJS /R:1 /W:1" 2>&1 || RC=$?
    # Robocopy exit 0 = no files copied (nothing to do); 1 = files copied (success); 8+ = error
    if [[ "$RC" -le 1 ]]; then
      COPY_OK=1
    else
      printf '  FAIL  %-32s — robocopy exit %s\n' "$NAME" "$RC"
      FAILED=$((FAILED + 1))
      continue
    fi
  fi

  if [[ "$COPY_OK" -eq 1 ]]; then
    printf '  COPY  %-32s — %s (%s KB) sha256=%s -> \\\\%s\\%s\\%s\n' \
      "$NAME" "$FNAME" "$SIZE_KB" "$SHA256" "$TARGET" "$SHARE" "${REMOTE_FILE//\//\\}"
    COPIED=$((COPIED + 1))
  fi

done \
  3< <(python3 - "$INSTALLERS_JSON" <<'PY'
import sys, json
apps = json.loads(sys.argv[1])
for a in apps: print(a['name'])
PY
) \
  4< <(python3 - "$INSTALLERS_JSON" <<'PY'
import sys, json
apps = json.loads(sys.argv[1])
for a in apps: print(a['filename_template'])
PY
) \
  5< <(python3 - "$INSTALLERS_JSON" <<'PY'
import sys, json
apps = json.loads(sys.argv[1])
for a in apps: print('1' if a['has_asset_placeholder'] else '0')
PY
) \
  6< <(python3 - "$INSTALLERS_JSON" <<'PY'
import sys, json
apps = json.loads(sys.argv[1])
for a in apps: print(a['asset_regex'])
PY
)

printf '\n  Summary: %d copied, %d failed, %d skipped\n' "$COPIED" "$FAILED" "$SKIPPED"

if [[ "$FAILED" -gt 0 && "$DRY_RUN" -eq 0 ]]; then
  log "Staging finished with $FAILED failure(s). Log: $LOG_FILE"
  exit 1
else
  log "Staging complete. Log: $LOG_FILE"
fi

} 2>&1 | tee_log
