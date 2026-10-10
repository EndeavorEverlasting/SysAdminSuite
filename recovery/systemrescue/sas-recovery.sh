#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PROGRAM="sas-recovery"
VERSION="0.3.0"
QR_LIMIT_DEFAULT=240
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

# shellcheck source=recovery/systemrescue/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=recovery/systemrescue/lib/imaging.sh
source "$SCRIPT_DIR/lib/imaging.sh"
# shellcheck source=recovery/systemrescue/lib/extraction.sh
source "$SCRIPT_DIR/lib/extraction.sh"
# shellcheck source=recovery/systemrescue/lib/forensics.sh
source "$SCRIPT_DIR/lib/forensics.sh"
# shellcheck source=recovery/systemrescue/lib/qr.sh
source "$SCRIPT_DIR/lib/qr.sh"

usage() {
  cat <<'USAGE'
SysAdminSuite SystemRescue recovery harness

Usage:
  sas-recovery.sh inventory
  sas-recovery.sh protect-source --source DEV [--expect-model TEXT] [--expect-serial TEXT]
  sas-recovery.sh mount-destination --partition DEV --mount DIR [--expect-label LABEL]
  sas-recovery.sh verify-workdir --workdir DIR --image NAME --map NAME
  sas-recovery.sh start-image --source DEV --destination-partition DEV --destination-mount DIR --workdir DIR --image NAME --map NAME --confirm-new-image
  sas-recovery.sh resume-image --source DEV --destination-partition DEV --destination-mount DIR --workdir DIR --image NAME --map NAME
  sas-recovery.sh image-status --workdir DIR --image NAME --map NAME
  sas-recovery.sh capture-checkpoint --destination-partition DEV --destination-mount DIR --workdir DIR --map NAME --tag TEXT
  sas-recovery.sh attach-image --destination-partition DEV --destination-mount DIR --image FILE --state-file FILE
  sas-recovery.sh open-bitlocker --partition DEV --name NAME
  sas-recovery.sh mount-ntfs --mapper DEV --mount DIR
  sas-recovery.sh audit-user-data --source-root DIR --destination-partition DEV --destination-mount DIR --report FILE [--include-appdata]
  sas-recovery.sh copy-user-data --source-root DIR --destination-partition DEV --destination-mount DIR --destination-root DIR --log FILE [--include-appdata]
  sas-recovery.sh cleanup --mount DIR --mapper-name NAME --loop-state-file FILE --image FILE
  sas-recovery.sh nvme-baseline --source DEV --workdir DIR [--expect-model TEXT] [--expect-serial TEXT]
  sas-recovery.sh nvme-classify-log --kernel-log FILE --ddrescue-rc N
  sas-recovery.sh nvme-read-repro --source DEV --workdir DIR [--expect-model TEXT] [--expect-serial TEXT]
  sas-recovery.sh qr-catalog --repo-mount DIR [--max-chars N]
  sas-recovery.sh forensics-qr-catalog --repo-mount DIR --source DEV --expect-model TEXT --expect-serial TEXT --workdir DIR [--max-chars N]

Safety contract:
  * Never repairs or mounts the failing source read-write.
  * Resumes only with an existing image and mapfile.
  * Image, BitLocker mapper, and NTFS filesystem are attached read-only.
  * NVMe reproduction reads only from an unmounted source forced host-read-only and writes evidence outside the source.
  * Preserved kernel logs can be classified without touching the source device.
  * User-data copy writes only to the explicit destination root.
  * Diagnostic terminal summaries are viewport-bounded; verbose evidence goes to files.
USAGE
}

main() {
  local command=${1:-help}
  [ $# -eq 0 ] || shift
  case "$command" in
    inventory) cmd_inventory "$@";;
    protect-source) cmd_protect_source "$@";;
    mount-destination) cmd_mount_destination "$@";;
    verify-workdir) cmd_verify_workdir "$@";;
    start-image) cmd_start_image "$@";;
    resume-image) cmd_resume_image "$@";;
    image-status) cmd_image_status "$@";;
    capture-checkpoint) cmd_capture_checkpoint "$@";;
    attach-image) cmd_attach_image "$@";;
    open-bitlocker) cmd_open_bitlocker "$@";;
    mount-ntfs) cmd_mount_ntfs "$@";;
    audit-user-data) cmd_audit_user_data "$@";;
    copy-user-data) cmd_copy_user_data "$@";;
    cleanup) cmd_cleanup "$@";;
    nvme-baseline) cmd_nvme_baseline "$@";;
    nvme-classify-log) cmd_nvme_classify_log "$@";;
    nvme-read-repro) cmd_nvme_read_repro "$@";;
    qr-catalog) cmd_qr_catalog "$@";;
    forensics-qr-catalog) cmd_forensics_qr_catalog "$@";;
    help|-h|--help) usage;;
    version|--version) printf '%s %s\n' "$PROGRAM" "$VERSION";;
    *) die "unknown command: $command";;
  esac
}

main "$@"
