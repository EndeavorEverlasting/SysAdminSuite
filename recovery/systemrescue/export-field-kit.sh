#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)

die() { printf 'STOP: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Export a privacy-safe SysAdminSuite SystemRescue field kit.

Usage:
  export-field-kit.sh --target-root DIR [--name NAME]

The target root must already exist on a writable filesystem.
The exporter never overwrites an existing kit directory.
USAGE
}

target_root=''
name='sas-systemrescue-field-kit'
while [ $# -gt 0 ]; do
  case "$1" in
    --target-root) target_root=${2:-}; shift 2;;
    --name) name=${2:-}; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown argument: $1";;
  esac
done

[ -n "$target_root" ] || die "--target-root is required"
[ -d "$target_root" ] || die "target root is not a directory: $target_root"
[ ! -L "$target_root" ] || die "target root must not be a symlink: $target_root"
[ -w "$target_root" ] || die "target root is not writable: $target_root"
target_real=$(readlink -f -- "$target_root")
case "$target_real/" in
  "$ROOT"/*) die "target root must be outside the repository: $target_real";;
esac
[[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "unsafe kit name: $name"

opts=$(findmnt -n -o OPTIONS --target "$target_root" 2>/dev/null || true)
case ",$opts," in
  *,ro,*) die "target filesystem is read-only: $target_root";;
esac

dest="$target_root/$name"
[ ! -e "$dest" ] || die "destination already exists; refusing overwrite: $dest"

mkdir -p "$dest/recovery"
cp -a "$SCRIPT_DIR" "$dest/recovery/systemrescue"
cp "$ROOT/START-HERE-SYSTEMRESCUE-RECOVERY.md" "$dest/START-HERE-SYSTEMRESCUE-RECOVERY.md"

(
  cd "$dest"
  find . -type f ! -name MANIFEST.sha256 -print0 |
    sort -z |
    xargs -0 sha256sum > MANIFEST.sha256
)

files=$(find "$dest" -type f | wc -l)
backing=$(findmnt -n -o SOURCE,FSTYPE,OPTIONS --target "$target_root" 2>/dev/null || printf 'UNKNOWN')
printf 'FIELD_KIT=%s\n' "$dest"
printf 'FILES=%s\n' "$files"
printf 'MANIFEST=%s\n' "$dest/MANIFEST.sha256"
printf 'TARGET_BACKING=%s\n' "$backing"
printf 'NEXT=bash %s/recovery/systemrescue/verify-field-kit.sh\n' "$dest"
