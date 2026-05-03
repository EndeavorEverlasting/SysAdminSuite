#!/usr/bin/env bash
# SysAdminSuite Bash Tutorial
# Interactive walkthrough of the four main Bash workflows.
# Usage:  bash/sas-tutorial.sh
#   or:   bash/sas-tutorial.sh --topic network|survey|audit|transport

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOPIC="${1:-}"

# ── Colours ───────────────────────────────────────────────────────────────────
BOLD='\033[1m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
RED='\033[1;31m'
DIM='\033[2m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
hr(){ printf '%s\n' "${CYAN}$(printf '─%.0s' {1..70})${RESET}"; }
section(){ echo; hr; printf "${BOLD}${BLUE}  %s${RESET}\n" "$1"; hr; echo; }
tip(){ printf "  ${YELLOW}Tip:${RESET} %s\n" "$1"; }
cmd(){ printf "  ${GREEN}\$${RESET} ${DIM}%s${RESET}\n" "$1"; }
note(){ printf "  ${MAGENTA}Note:${RESET} %s\n" "$1"; }
pause(){
  printf "\n  ${DIM}Press Enter to continue, or q+Enter to quit...${RESET} "
  local ans; IFS= read -r ans || true
  if [[ "$ans" == q ]]; then echo; echo "  Exiting tutorial."; echo; exit 0; fi
}

# ── Live-run helpers ──────────────────────────────────────────────────────────

# live_run LABEL SCRIPT_PATH [extra args...]
# Runs the script with stdout and stderr both piped to the terminal in real time.
# stderr lines are printed in dim colour; stdout lines are indented normally.
# Exit code is captured and non-zero exits are explained clearly.
live_run(){
  local label="$1"; shift
  local script_path="$1"; shift
  local extra_args=("$@")

  printf "\n"
  hr
  printf "  ${BOLD}${GREEN}Running:${RESET} ${DIM}%s %s${RESET}\n" \
    "$script_path" "${extra_args[*]:-}"
  hr
  printf "\n"

  local exit_code=0

  set +e
  # Run from REPO_ROOT so relative default output paths in each script work
  # correctly regardless of the directory the tutorial was launched from.
  # stderr goes through a live filter that adds dim colour + indentation.
  # stdout goes through a live filter that adds indentation.
  # PIPESTATUS[0] captures the exit code of the script itself.
  (cd "$REPO_ROOT" && bash "$script_path" "${extra_args[@]}") \
    2> >(while IFS= read -r line; do printf "  ${DIM}%s${RESET}\n" "$line"; done >&2) \
    | while IFS= read -r line; do printf "  %s\n" "$line"; done
  exit_code=${PIPESTATUS[0]}
  # Wait for the stderr filter subshell to flush before printing status
  wait
  set -e

  echo
  if [[ $exit_code -ne 0 ]]; then
    printf "  ${RED}${BOLD}Error:${RESET} ${RED}%s${RESET} exited with code %d.\n" "$label" "$exit_code"
    printf "\n  ${YELLOW}Common causes:${RESET}\n"
    printf "    • The target is unreachable or blocked by a firewall.\n"
    printf "    • A required tool (ping, nc, snmpget, etc.) is not installed.\n"
    printf "    • Insufficient permissions for the operation.\n"
    printf "    • The target file or workbook path is incorrect.\n"
    printf "\n  ${DIM}The tutorial will continue — this is safe to ignore.${RESET}\n"
  else
    printf "  ${GREEN}${DIM}(Done — output above; CSV also written to disk.)${RESET}\n"
  fi

  echo
  hr
  echo
}

# try_prompt LABEL SCRIPT_PATH DEFAULT_TARGET_FLAG DEFAULT_TARGET [extra args...]
# Offers y / t (custom target) / n.
# DEFAULT_TARGET_FLAG is the flag used to pass a positional or named target,
# e.g. "" for positional or "--target".
try_prompt(){
  local label="$1"; shift
  local script_path="$1"; shift
  local target_flag="$1"; shift
  local default_target="$1"; shift
  local extra_args=("$@")

  echo
  printf "  ${GREEN}${BOLD}▶ Try it now?${RESET}\n"
  printf "  ${DIM}[y]${RESET} Run against the safe default target ${BOLD}%s${RESET}\n" "$default_target"
  printf "  ${DIM}[t]${RESET} Enter a custom hostname or IP\n"
  printf "  ${DIM}[n]${RESET} Skip and continue\n"
  printf "  Your choice (y/t/n): "

  local ans; IFS= read -r ans || true
  case "$ans" in
    y|Y)
      if [[ -n "$target_flag" ]]; then
        live_run "$label" "$script_path" "$target_flag" "$default_target" "${extra_args[@]}"
      else
        live_run "$label" "$script_path" "$default_target" "${extra_args[@]}"
      fi
      ;;
    t|T)
      printf "  Enter target hostname or IP: "
      local tgt; IFS= read -r tgt || true
      tgt="${tgt#"${tgt%%[![:space:]]*}"}"   # ltrim
      tgt="${tgt%"${tgt##*[![:space:]]}"}"   # rtrim
      if [[ -z "$tgt" ]]; then
        printf "  ${YELLOW}No target entered — skipping.${RESET}\n"
      elif [[ ! "$tgt" =~ ^[A-Za-z0-9._:-]+$ ]]; then
        printf "  ${RED}Invalid target '%s'. Use a hostname, IPv4, or IPv6 address.${RESET}\n" "$tgt"
      else
        if [[ -n "$target_flag" ]]; then
          live_run "$label" "$script_path" "$target_flag" "$tgt" "${extra_args[@]}"
        else
          live_run "$label" "$script_path" "$tgt" "${extra_args[@]}"
        fi
      fi
      ;;
    *)
      printf "  ${DIM}Skipped.${RESET}\n"
      ;;
  esac
}

# ── Banner ────────────────────────────────────────────────────────────────────
banner(){
  clear 2>/dev/null || true
  echo
  printf "${CYAN}${BOLD}"
  printf '  ╔══════════════════════════════════════════════════════════════════╗\n'
  printf '  ║          SysAdminSuite — Bash Workflow Tutorial                  ║\n'
  printf '  ╚══════════════════════════════════════════════════════════════════╝\n'
  printf "${RESET}"
  echo
  printf "  All scripts are ${GREEN}read-only${RESET} unless noted otherwise.\n"
  printf "  Repo root: ${DIM}%s${RESET}\n" "$REPO_ROOT"
  echo
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. NETWORK PREFLIGHT
# ─────────────────────────────────────────────────────────────────────────────
tutorial_network(){
  section "1 of 4 — Network Preflight  (sas-network-preflight.sh)"
  printf "  Before probing or mapping printers and workstations you need to know\n"
  printf "  which hosts are reachable and which TCP ports are open.\n\n"
  printf "  ${BOLD}sas-network-preflight.sh${RESET} runs three checks per target:\n"
  printf "    • DNS / IP resolution\n"
  printf "    • ICMP ping\n"
  printf "    • TCP port sweep (default: 135, 139, 445, 3389, 515, 631, 9100)\n"
  printf "  Results are written to a CSV — no changes are made.\n"
  pause

  section "Network Preflight — Example commands"
  printf "  ${BOLD}Probe a single host:${RESET}\n"
  cmd "bash/transport/sas-network-preflight.sh 10.1.2.50"
  echo
  printf "  ${BOLD}Probe several hosts at once:${RESET}\n"
  cmd "bash/transport/sas-network-preflight.sh 10.1.2.50 10.1.2.51 10.1.2.52"
  echo
  printf "  ${BOLD}Use a target list file (one host per line):${RESET}\n"
  cmd "bash/transport/sas-network-preflight.sh --targets-file hosts.txt"
  echo
  printf "  ${BOLD}Custom port set and output path:${RESET}\n"
  cmd "bash/transport/sas-network-preflight.sh --ports 80,443,9100 --output /tmp/pf.csv 10.1.2.50"
  echo
  tip "Add --pass-thru to also print the CSV to stdout for piping into grep or awk."

  # ── Live run ──
  try_prompt \
    "sas-network-preflight.sh" \
    "bash/transport/sas-network-preflight.sh" \
    "" \
    "127.0.0.1" \
    "--ports" "80,443,22,9100" \
    "--pass-thru"

  section "Network Preflight — Reading the output"
  printf "  The CSV has these columns:\n\n"
  printf "  ${DIM}Timestamp           Target      ResolvedAddress  PingStatus  Port   PortStatus${RESET}\n"
  printf "  2026-05-03 09:14:02  10.1.2.50   10.1.2.50        Reachable   445    Open\n"
  printf "  2026-05-03 09:14:02  10.1.2.50   10.1.2.50        Reachable   9100   Open\n"
  printf "  2026-05-03 09:14:03  BADHOST      (empty)          NoPing      445    ClosedOrFiltered\n"
  echo
  printf "  ${BOLD}PingStatus${RESET} values:   Reachable | NoPing\n"
  printf "  ${BOLD}PortStatus${RESET} values:   Open | ClosedOrFiltered | NotChecked\n"
  echo
  note "Load the output CSV into the web dashboard at /dashboard/ for a visual Network tab view."
  pause
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. SURVEY — WORKSTATION & PRINTER IDENTITY
# ─────────────────────────────────────────────────────────────────────────────
tutorial_survey(){
  section "2 of 4 — Survey Workflow  (workstation & printer identity)"
  printf "  The survey step collects hardware identity from devices — serial numbers,\n"
  printf "  IP addresses, MAC addresses, and hostnames — without changing anything.\n\n"
  printf "  Three scripts are involved:\n\n"
  printf "  ${BOLD}bash/transport/sas-workstation-identity.sh${RESET}  — Workstation identity\n"
  printf "  ${BOLD}bash/transport/sas-printer-probe.sh${RESET}         — Network printer identity\n"
  printf "  ${BOLD}survey/sas-survey-targets.sh${RESET}                — Device-type dispatcher\n"
  pause

  section "Survey — Workstation identity probe"
  printf "  ${BOLD}Supported options:${RESET}\n"
  printf "    --target VALUE        Hostname or IP to probe\n"
  printf "    --targets-file PATH   File with one target per line\n"
  printf "    --output PATH         Output CSV path\n"
  printf "    --timeout SEC         Per-target timeout (default: 5)\n"
  echo
  printf "  ${BOLD}Probe a single workstation:${RESET}\n"
  cmd "bash/transport/sas-workstation-identity.sh --target WMH300OPR001"
  echo
  printf "  ${BOLD}Probe from a file and write to a custom output path:${RESET}\n"
  cmd "bash/transport/sas-workstation-identity.sh --targets-file survey/hosts.txt --output survey/output/identities.csv"
  echo
  printf "  ${BOLD}Output CSV columns:${RESET}\n"
  printf "  ${DIM}Timestamp | Target | ResolvedAddress | PingStatus | DnsName | ObservedHostName |\n"
  printf "  ObservedSerial | ObservedMACs | TransportUsed | IdentityStatus | Notes${RESET}\n"
  echo
  printf "  ${BOLD}TransportUsed${RESET} values: WMI | SSH | ARP | WMI+ARP | SSH+ARP\n"
  printf "  ${BOLD}IdentityStatus${RESET} values: IdentityCollected | ReachableNeedsApprovedIdentityTransport | UnreachableOrBlocked\n"
  echo
  tip "The script tries WMI first, then SSH, then ARP in order — whichever succeeds first wins."

  # ── Live run ──
  printf "\n  ${DIM}Note: This probe will use ARP only (WMI and SSH are disabled by default).${RESET}\n"
  try_prompt \
    "sas-workstation-identity.sh" \
    "bash/transport/sas-workstation-identity.sh" \
    "--target" \
    "127.0.0.1" \
    "--pass-thru"

  section "Survey — Printer probe"
  printf "  ${BOLD}Supported options:${RESET}\n"
  printf "    --target VALUE        Printer hostname or IP\n"
  printf "    --targets-file PATH   File with one target per line\n"
  printf "    --communities CSV     SNMP communities (default: public,private,northwell,zebra,netadmin)\n"
  printf "    --output PATH         Output CSV path\n"
  printf "    --timeout SEC         Timeout (default: 3)\n"
  printf "    --snmp-only           Skip HTTP, 9100, and ARP fallbacks\n"
  printf "    --skip-9100           Do not send raw-port / ZPL request\n"
  printf "    --pass-thru           Also print CSV to stdout\n"
  echo
  printf "  ${BOLD}Probe a printer by IP:${RESET}\n"
  cmd "bash/transport/sas-printer-probe.sh --target 10.1.3.100"
  echo
  printf "  ${BOLD}Probe a list of printer IPs:${RESET}\n"
  cmd "bash/transport/sas-printer-probe.sh --targets-file survey/printers.txt --output survey/output/printers.csv"
  echo
  printf "  ${BOLD}Output CSV columns:${RESET}\n"
  printf "  ${DIM}Timestamp | Target | ResolvedAddress | PingStatus | MAC | Serial | Source | Notes${RESET}\n"
  echo
  tip "Use --snmp-only in restricted environments where HTTP banner scraping is not approved."

  # ── Live run ──
  printf "\n  ${DIM}Note: --skip-9100 is set for safety. SNMP will likely report no data on 127.0.0.1.${RESET}\n"
  try_prompt \
    "sas-printer-probe.sh" \
    "bash/transport/sas-printer-probe.sh" \
    "--target" \
    "127.0.0.1" \
    "--skip-9100" \
    "--pass-thru"

  section "Survey — sas-survey-targets.sh dispatcher"
  printf "  The survey/ entry point normalises identifiers (hostname, MAC, serial) from\n"
  printf "  various input formats (TXT, CSV, JSON) and associates a device type.\n\n"
  printf "  ${BOLD}Supported options:${RESET}\n"
  printf "    --device-type TYPE    Cybernet | Neuron | Workstation | Unknown\n"
  printf "    --csv PATH            CSV input file\n"
  printf "    --inventory PATH      Known-devices CSV for cross-reference\n"
  printf "    --output PATH         Output manifest CSV\n"
  echo
  printf "  ${BOLD}Example — Cybernet targets from command line:${RESET}\n"
  cmd "survey/sas-survey-targets.sh --device-type Cybernet WMH300OPR001 00:11:22:33:44:55"
  echo
  printf "  ${BOLD}Example — Neuron targets from a CSV:${RESET}\n"
  cmd "survey/sas-survey-targets.sh --device-type Neuron --csv neurons.csv --inventory known_devices.csv"
  echo
  printf "  Valid device types: ${BOLD}Cybernet${RESET}  ${BOLD}Neuron${RESET}  ${BOLD}Workstation${RESET}  ${BOLD}Unknown${RESET}\n"
  echo
  note "The output manifest CSV feeds directly into the Deployment Audit step."
  pause
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. DEPLOYMENT AUDIT
# ─────────────────────────────────────────────────────────────────────────────
tutorial_audit(){
  section "3 of 4 — Deployment Audit  (sas-audit-deployments.sh)"
  printf "  The deployment audit step reads the Active Deployment Tracker workbook\n"
  printf "  (an .xlsx file) and checks every ${BOLD}Deployed = Yes${RESET} row for:\n\n"
  printf "    • Duplicate unique identifiers across deployed rows\n"
  printf "    • Same identifier appearing in different locations (location clash)\n"
  printf "    • Missing or malformed identifiers (blank, N/A, #REF!)\n"
  printf "    • Clusters of related duplicate rows\n"
  echo
  printf "  All findings are written to CSV + a summary text file. Nothing is modified.\n"
  pause

  section "Deployment Audit — Example commands"
  printf "  ${BOLD}Supported options:${RESET}\n"
  printf "    --workbook PATH                 XLSX tracker file to inspect\n"
  printf "    --sheet NAME                    Worksheet to read (default: Deployments)\n"
  printf "    --keys CSV                      Unique identifier column headers to audit\n"
  printf "    --resolution-keys CSV           Fields needed to resolve a duplicate\n"
  printf "    --output-dir PATH               Output folder (default: deployment-audit/output)\n"
  printf "    --allow-same-location-warning   Keep same-location duplicates as warnings\n"
  printf "    --pass-thru                     Print duplicate values to stdout\n"
  echo
  printf "  ${BOLD}Basic audit:${RESET}\n"
  cmd "deployment-audit/sas-audit-deployments.sh --workbook data/raw/tracker.xlsx"
  echo
  printf "  ${BOLD}Custom output folder:${RESET}\n"
  cmd "deployment-audit/sas-audit-deployments.sh --workbook data/raw/tracker.xlsx --output-dir data/outputs/audit"
  echo
  printf "  ${BOLD}Audit specific key columns:${RESET}\n"
  cmd "deployment-audit/sas-audit-deployments.sh --workbook data/raw/tracker.xlsx --keys 'Cybernet Hostname,Cybernet Serial,Cybernet MAC'"
  echo
  tip "Add --pass-thru to print the real duplicate values to stdout for quick review."

  # ── Live run — check for a sample workbook ──
  echo
  printf "  ${GREEN}${BOLD}▶ Try it now?${RESET}\n"
  local wb_found=""
  local wb_path=""
  for candidate in \
    "data/raw/tracker.xlsx" \
    "deployment-audit/sample.xlsx" \
    "data/tracker.xlsx"; do
    if [[ -f "$REPO_ROOT/$candidate" ]]; then
      wb_found="$REPO_ROOT/$candidate"
      wb_path="$candidate"
      break
    fi
  done

  if [[ -n "$wb_found" ]]; then
    printf "  ${DIM}[y]${RESET} Run audit against: ${BOLD}%s${RESET}\n" "$wb_path"
  else
    printf "  ${YELLOW}No .xlsx workbook found in the default locations.${RESET}\n"
    printf "  ${DIM}Default locations checked: data/raw/tracker.xlsx, deployment-audit/sample.xlsx, data/tracker.xlsx${RESET}\n"
  fi
  printf "  ${DIM}[p]${RESET} Enter a custom workbook path\n"
  printf "  ${DIM}[n]${RESET} Skip and continue\n"
  local choice_hint="p/n"
  if [[ -n "$wb_found" ]]; then choice_hint="y/p/n"; fi
  printf "  Your choice (%s): " "$choice_hint"

  local ans wb
  IFS= read -r ans || true
  case "$ans" in
    y|Y)
      if [[ -n "$wb_found" ]]; then
        live_run \
          "sas-audit-deployments.sh" \
          "deployment-audit/sas-audit-deployments.sh" \
          "--workbook" "$wb_path" \
          "--pass-thru"
      else
        printf "  ${YELLOW}No default workbook available — use [p] to enter a path.${RESET}\n"
      fi
      ;;
    p|P)
      printf "  Enter path to .xlsx workbook: "
      IFS= read -r wb || true
      wb="${wb#"${wb%%[![:space:]]*}"}"   # ltrim
      wb="${wb%"${wb##*[![:space:]]}"}"   # rtrim
      if [[ -z "$wb" ]]; then
        printf "  ${YELLOW}No path entered — skipping.${RESET}\n"
      elif [[ ! -f "$wb" ]]; then
        printf "  ${RED}File not found: %s${RESET}\n" "$wb"
      else
        live_run \
          "sas-audit-deployments.sh" \
          "deployment-audit/sas-audit-deployments.sh" \
          "--workbook" "$wb" \
          "--pass-thru"
      fi
      ;;
    *)
      printf "  ${DIM}Skipped.${RESET}\n"
      ;;
  esac

  section "Deployment Audit — Output files"
  printf "  The audit writes these files to the output folder:\n\n"
  printf "  ${DIM}%-45s %s${RESET}\n" "File" "Contents"
  printf "  ${DIM}%-45s %s${RESET}\n" "─────────────────────────────────────────────" "──────────────────────────────────────────"
  printf "  %-45s %s\n" "deployed_records_normalized.csv" "All Deployed=Yes rows, normalised"
  printf "  %-45s %s\n" "real_duplicate_values_deployed_yes.csv" "Identifier values that appear more than once"
  printf "  %-45s %s\n" "real_duplicate_pairs_deployed_yes.csv" "Pairs of rows sharing a duplicate identifier"
  printf "  %-45s %s\n" "real_duplicate_clusters.csv" "Clusters of all rows sharing an identifier"
  printf "  %-45s %s\n" "survey_requests_duplicate_resolution.csv" "Rows that need field resolution"
  printf "  %-45s %s\n" "ref_errors.csv" "Rows with #REF!, N/A, or blank identifiers"
  printf "  %-45s %s\n" "audit_summary.txt" "Plain-text summary of all findings"
  echo
  printf "  ${BOLD}Duplicate rule:${RESET}\n"
  printf "    A duplicate is flagged when the same identifier value appears on more\n"
  printf "    than one Deployed=Yes row ${BOLD}in different locations${RESET} (use\n"
  printf "    --allow-same-location-warning to also flag same-location repeats).\n"
  echo
  note "Load the CSV outputs into the web dashboard for a visual diff view."
  pause

  section "Deployment Audit — Quick workflow tip"
  printf "  Best practice:\n\n"
  printf "  1. Start with a basic audit — no extra flags — to see all findings\n"
  printf "  2. Open ${BOLD}audit_summary.txt${RESET} for a plain-English overview\n"
  printf "  3. Open ${BOLD}real_duplicate_clusters.csv${RESET} to find the grouped duplicate rows\n"
  printf "  4. Use ${BOLD}survey_requests_duplicate_resolution.csv${RESET} to task field techs with\n"
  printf "     collecting the missing resolution data (serial, MAC, hostname)\n"
  pause
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. TRANSPORT RECON
# ─────────────────────────────────────────────────────────────────────────────
tutorial_transport(){
  section "4 of 4 — Transport Recon  (bash/transport/)"
  printf "  The transport/ folder holds all read-only recon scripts. They are the\n"
  printf "  building blocks the survey and preflight steps are composed from.\n\n"
  printf "  ${BOLD}Available scripts:${RESET}\n"
  printf "    %-40s %s\n" "sas-network-preflight.sh" "DNS, ping, TCP port sweep"
  printf "    %-40s %s\n" "sas-workstation-identity.sh" "Workstation identity (WMI, SSH, ARP)"
  printf "    %-40s %s\n" "sas-printer-probe.sh" "Printer identity via SNMP + HTTP + ARP"
  printf "    %-40s %s\n" "sas-wmi-identity.sh" "WMI identity adapter (Windows bridge)"
  printf "    %-40s %s\n" "sas-smb-readonly-recon.sh" "SMB share inventory (read-only)"
  pause

  section "Transport Recon — SMB share recon"
  printf "  ${BOLD}sas-smb-readonly-recon.sh${RESET} inventories a Windows file share without\n"
  printf "  mounting or writing anything:\n\n"
  cmd "bash/transport/sas-smb-readonly-recon.sh --share '\\\\FILESERVER\\support' --output smb-recon.csv"
  echo
  tip "Combine with sas-network-preflight.sh — preflight first, then recon only reachable hosts."
  pause

  section "Transport Recon — Apps management"
  printf "  The ${BOLD}bash/apps/${RESET} folder covers software lifecycle on client machines:\n\n"
  printf "    %-30s %s\n" "sas-list-apps.sh" "List installed apps (registry-style CSV output)"
  printf "    %-30s %s\n" "sas-install-apps.sh" "Stage + launch installers from a manifest"
  printf "    %-30s %s\n" "sas-populate-tracker.sh" "Push install results back to the tracker"
  printf "    %-30s %s\n" "sas-stage-fileshare.sh" "Robocopy-style push to a file share"
  echo
  printf "  ${BOLD}Quick app list:${RESET}\n"
  cmd "bash/apps/sas-list-apps.sh --help"
  echo
  tip "Load the app list CSV into the dashboard Software Tracker tab for a visual view."
  pause

  section "Transport Recon — Combining scripts into a pipeline"
  printf "  A typical field session looks like this:\n\n"
  printf "  ${DIM}# Step 1 — network preflight${RESET}\n"
  cmd "bash/transport/sas-network-preflight.sh --targets-file hosts.txt --output pf.csv"
  echo
  printf "  ${DIM}# Step 2 — workstation identity for reachable hosts${RESET}\n"
  cmd "bash/transport/sas-workstation-identity.sh --targets-file hosts.txt --output identities.csv"
  echo
  printf "  ${DIM}# Step 3 — printer probe for printer IPs${RESET}\n"
  cmd "bash/transport/sas-printer-probe.sh --targets-file printers.txt --output printers.csv"
  echo
  printf "  ${DIM}# Step 4 — deployment audit on the tracker workbook${RESET}\n"
  cmd "deployment-audit/sas-audit-deployments.sh --workbook tracker.xlsx --output-dir audit-out/"
  echo
  printf "  ${DIM}# Step 5 — load the CSVs into the dashboard${RESET}\n"
  printf "  ${DIM}#          drag pf.csv, identities.csv, printers.csv onto /dashboard/${RESET}\n"
  echo
  note "All four CSVs are auto-detected by the dashboard file parser."

  # ── Live run — mini pipeline against 127.0.0.1 ──
  echo
  printf "  ${GREEN}${BOLD}▶ Try the mini pipeline now?${RESET}\n"
  printf "  This will run ${BOLD}network preflight${RESET} then ${BOLD}workstation identity${RESET}\n"
  printf "  back-to-back against a single target so you can see real output.\n"
  printf "\n"
  printf "  ${DIM}[y]${RESET} Run both steps against the safe default target ${BOLD}127.0.0.1${RESET}\n"
  printf "  ${DIM}[t]${RESET} Enter a custom hostname or IP\n"
  printf "  ${DIM}[n]${RESET} Skip and continue\n"
  printf "  Your choice (y/t/n): "

  local ans tgt
  IFS= read -r ans || true
  tgt="127.0.0.1"
  case "$ans" in
    t|T)
      printf "  Enter target hostname or IP: "
      IFS= read -r tgt || true
      tgt="${tgt#"${tgt%%[![:space:]]*}"}"   # ltrim
      tgt="${tgt%"${tgt##*[![:space:]]}"}"   # rtrim
      if [[ -z "$tgt" ]]; then
        printf "  ${YELLOW}No target entered — skipping pipeline.${RESET}\n"
        ans="n"
      elif [[ ! "$tgt" =~ ^[A-Za-z0-9._:-]+$ ]]; then
        printf "  ${RED}Invalid target '%s'. Use a hostname, IPv4, or IPv6 address.${RESET}\n" "$tgt"
        ans="n"
      fi
      ;;
  esac

  if [[ "$ans" == y || "$ans" == Y || "$ans" == t || "$ans" == T ]]; then
    printf "\n  ${BOLD}Step 1 — Network Preflight${RESET}\n"
    live_run \
      "sas-network-preflight.sh" \
      "bash/transport/sas-network-preflight.sh" \
      "$tgt" \
      "--ports" "22,80,443,445,9100" \
      "--pass-thru"

    printf "  ${BOLD}Step 2 — Workstation Identity${RESET}\n"
    live_run \
      "sas-workstation-identity.sh" \
      "bash/transport/sas-workstation-identity.sh" \
      "--target" "$tgt" \
      "--pass-thru"
  else
    printf "  ${DIM}Skipped.${RESET}\n"
  fi

  pause
}

# ─────────────────────────────────────────────────────────────────────────────
# TOPIC MENU
# ─────────────────────────────────────────────────────────────────────────────
show_menu(){
  banner
  printf "  Choose a topic:\n\n"
  printf "  ${CYAN}[1]${RESET}  Network Preflight     — DNS, ping, TCP port sweep\n"
  printf "  ${CYAN}[2]${RESET}  Survey Workflow       — Workstation & printer identity\n"
  printf "  ${CYAN}[3]${RESET}  Deployment Audit      — Tracker duplicate detection & audit\n"
  printf "  ${CYAN}[4]${RESET}  Transport Recon       — Individual transport scripts + pipeline\n"
  printf "  ${CYAN}[a]${RESET}  All topics in order\n"
  printf "  ${CYAN}[q]${RESET}  Quit\n"
  echo
  printf "  Your choice: "
  local ans; IFS= read -r ans || true
  case "$ans" in
    1|network)   tutorial_network ;;
    2|survey)    tutorial_survey ;;
    3|audit)     tutorial_audit ;;
    4|transport) tutorial_transport ;;
    a|all)       tutorial_network; tutorial_survey; tutorial_audit; tutorial_transport ;;
    q|quit)      echo; echo "  Goodbye!"; echo; exit 0 ;;
    *)
      printf "\n  ${YELLOW}Unknown choice '%s'. Please enter 1-4, a, or q.${RESET}\n\n" "$ans"
      show_menu
      return
      ;;
  esac

  # After a topic finishes, offer the menu again
  echo
  hr
  printf "\n  Topic finished. Return to the main menu? (Enter = yes, q = quit): "
  local again; IFS= read -r again || true
  if [[ "$again" == q ]]; then echo; echo "  Goodbye!"; echo; exit 0; fi
  show_menu
}

# ─────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────
case "${TOPIC:-}" in
  --topic)
    shift 2>/dev/null || true
    TOPIC="${1:-}"
    ;;
  --help|-h)
    echo "Usage: $0 [--topic network|survey|audit|transport|all]"
    exit 0
    ;;
esac

banner

case "${TOPIC:-}" in
  network)   tutorial_network ;;
  survey)    tutorial_survey ;;
  audit)     tutorial_audit ;;
  transport) tutorial_transport ;;
  all)       tutorial_network; tutorial_survey; tutorial_audit; tutorial_transport ;;
  "")        show_menu ;;
  *)
    printf "  ${YELLOW}Unknown topic '%s'.${RESET} Valid topics: network | survey | audit | transport | all\n\n" "$TOPIC"
    show_menu
    ;;
esac

echo
printf "  ${GREEN}${BOLD}Tutorial complete!${RESET}\n"
printf "  Re-run anytime:  ${DIM}bash/sas-tutorial.sh${RESET}\n\n"
