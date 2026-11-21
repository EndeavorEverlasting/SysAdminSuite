#!/usr/bin/env python3
"""Run a supported local antivirus and emit privacy-bounded evidence."""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable
from uuid import uuid4
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
QUEUE = Path("evidence/antivirus-queue")
ACTIONS = {
    "NO_PROVIDER": "REVIEW_PROVIDER_AVAILABILITY",
    "DISCOVERY_FAILED": "DIAGNOSE_PROVIDER_DISCOVERY",
    "UNSUPPORTED_PROVIDER": "ADD_DOCUMENTED_PROVIDER_ADAPTER",
    "VENDOR_SCHEDULER_REQUIRED": "CONFIGURE_VENDOR_SCHEDULER",
    "UNSUPPORTED_HOST": "USE_NATIVE_SUPPORTED_HOST",
    "SCAN_INTERRUPTED": "REVIEW_INTERRUPTED_SCAN",
    "SCAN_FAILED": "DIAGNOSE_PROVIDER_EXECUTION",
    "SCAN_TIMEOUT": "REVIEW_SCAN_TIMEOUT",
    "SCAN_UNCONFIRMED": "VERIFY_PROVIDER_COMPLETION",
    "SCAN_INCOMPLETE": "REVIEW_SCAN_COVERAGE",
    "DETECTION_REPORTED": "REVIEW_DETECTIONS_WITH_LOCAL_SCANNER",
}


@dataclass(frozen=True)
class Scanner:
    provider: str
    command: tuple[str, ...]
    results: dict[int, str]
    working_directory: Path | None = None


def choose_scanner(os_name: str, windows_probe: str, has_file: Callable[[Path], bool], program_files: list[Path],
                   home: Path) -> tuple[Scanner | None, str]:
    if os_name == "windows":
        if windows_probe == "DEFENDER_READY":
            return Scanner("defender", (), {0: "SCAN_COMPLETED", 11: "SCAN_UNCONFIRMED"}), ""
        for base in program_files:
            for edition in ("ESET Security", "ESET Endpoint Security", "ESET Endpoint Antivirus"):
                exe = base / "ESET" / edition / "ecls.exe"
                if has_file(exe):
                    modules = exe.parent / "Modules"
                    base_args = (f"/base-dir={modules}",) if modules.is_dir() else ()
                    return Scanner("eset", (str(exe), *base_args, "/no-log-console", "/no-symlink",
                                            "/clean-mode=none", "/no-quarantine", str(home)),
                                   {0: "NO_DETECTIONS_REPORTED", 1: "DETECTION_REPORTED",
                                    10: "SCAN_INCOMPLETE", 50: "DETECTION_REPORTED"},
                                   exe.parent), ""
        if any(has_file(base / "Malwarebytes" / "Anti-Malware" / "mbam.exe")
               for base in program_files):
            return None, "VENDOR_SCHEDULER_REQUIRED"
        return None, {"REGISTERED": "UNSUPPORTED_PROVIDER", "NONE": "NO_PROVIDER"}.get(
            windows_probe, "DISCOVERY_FAILED")
    if os_name == "linux":
        for folder in (Path("/usr/bin"), Path("/usr/local/bin"), Path("/bin")):
            exe = folder / "clamscan"
            if has_file(exe):
                return Scanner("clamav", (str(exe), "--recursive", "--cross-fs=no",
                                          "--follow-dir-symlinks=0", "--follow-file-symlinks=0",
                                          "--", str(home)),
                               {0: "NO_DETECTIONS_REPORTED", 1: "DETECTION_REPORTED"}), ""
        return None, "NO_PROVIDER"
    return None, "UNSUPPORTED_HOST"


def development_candidate(status: str) -> dict[str, str] | None:
    """Reconstruct from constants. The source receipt is never copied."""
    if status not in ACTIONS or status == "DETECTION_REPORTED":
        return None
    return {
        "schema_version": "sas-antivirus-development-candidate/v1",
        "gap_code": status,
        "next_action": ACTIONS[status],
        "publication_state": "LOCAL_REVIEW_REQUIRED",
    }


HISTORY_LIMIT = 32
HISTORY_FILE = re.compile(r"run-\d{8}T\d{12}Z-[0-9a-f]{32}\.json")
SCAN_TIMEOUT_SECONDS = 7200
TASK_SOURCE = "SysAdminSuite Host Antivirus"
CRON_MARKER = " # SysAdminSuite:host-antivirus/v1"
DAYS = ("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
RECEIPT_VERSION = "sas-antivirus-receipt/v1"
TASK_NS = "http://schemas.microsoft.com/windows/2004/02/mit/task"

WINDOWS_PROBE = r"""
$ErrorActionPreference = 'Stop'
$module = Join-Path $PSHOME 'Modules\Defender\Defender.psd1'
try {
    Import-Module -Name $module -ErrorAction Stop
    $status = Defender\Get-MpComputerStatus
    if ($status.AntivirusEnabled -and $status.AMRunningMode -eq 'Normal') {
        'DEFENDER_READY'; exit 0
    }
} catch {}
try {
    if (@(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct).Count -gt 0) {
        'REGISTERED'
    } else { 'NONE' }
} catch { 'DISCOVERY_FAILED' }
"""

DEFENDER_SCAN = r"""
$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path $PSHOME 'Modules\Defender\Defender.psd1')
$before = Defender\Get-MpComputerStatus
if (-not $before.AntivirusEnabled -or $before.AMRunningMode -ne 'Normal') { exit 12 }
$requested = (Get-Date).AddSeconds(-2)
Defender\Start-MpScan -ScanType QuickScan
for ($attempt = 0; $attempt -lt 12; $attempt++) {
    $after = Defender\Get-MpComputerStatus
    if ($after.QuickScanStartTime -and $after.QuickScanEndTime -and
        $after.QuickScanStartTime -ge $requested -and
        $after.QuickScanStartTime -ne $before.QuickScanStartTime -and
        $after.QuickScanEndTime -ge $after.QuickScanStartTime -and
        $after.QuickScanEndTime -ne $before.QuickScanEndTime) { exit 0 }
    if ($attempt -lt 11) { Start-Sleep -Seconds 5 }
}
exit 11
"""


def platform_name() -> str:
    if sys.platform == "win32":
        return "windows"
    if sys.platform.startswith("linux"):
        kernel = Path("/proc/sys/kernel/osrelease").read_text(encoding="utf-8")
        return "wsl" if "microsoft" in kernel.lower() else "linux"
    return "unsupported"


def execute(command: tuple[str, ...], *, timeout: int = 30, capture: bool = False,
            input_text: str | None = None, cwd: Path | None = None,
            env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command, timeout=timeout, check=False, input=input_text, text=True,
        encoding="utf-8", errors="replace", cwd=cwd, env=env,
        stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
        stderr=subprocess.PIPE if capture else subprocess.DEVNULL,
        stdin=subprocess.DEVNULL if input_text is None else None,
        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
    )


def powershell(source: str) -> tuple[str, ...]:
    system_root = Path(os.environ["SystemRoot"])
    shell_path = Path("WindowsPowerShell") / "v1.0" / "powershell.exe"
    native_shell = system_root / "Sysnative" / shell_path
    shell = native_shell if native_shell.is_file() else system_root / "System32" / shell_path
    encoded = base64.b64encode(source.encode("utf-16-le")).decode("ascii")
    return (str(shell), "-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded)


def installed_executable(path: Path) -> bool:
    if not path.is_file() or not os.access(path, os.X_OK):
        return False
    if os.name == "nt":
        return True
    info = path.stat()
    return info.st_uid == 0 and not info.st_mode & 0o022


def discover(host: str) -> tuple[Scanner | None, str]:
    probe = ""
    program_files = []
    if host == "windows":
        result = execute(powershell(WINDOWS_PROBE), capture=True)
        if result.returncode == 0:
            probe = result.stdout.strip()
        program_files = list(dict.fromkeys(
            Path(os.environ[key]) for key in ("ProgramW6432", "ProgramFiles", "ProgramFiles(x86)")
            if os.environ.get(key) and Path(os.environ[key]).is_absolute()
        ))
    return choose_scanner(host, probe, installed_executable, program_files, Path.home())


def scan(scanner: Scanner) -> str:
    command = powershell(DEFENDER_SCAN) if scanner.provider == "defender" else scanner.command
    try:
        result = execute(command, timeout=SCAN_TIMEOUT_SECONDS, cwd=scanner.working_directory)
    except subprocess.TimeoutExpired:
        return "SCAN_TIMEOUT"
    except OSError:
        return "SCAN_FAILED"
    return scanner.results.get(result.returncode, "SCAN_FAILED")


def write_json(path: Path, payload: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix=".antivirus-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(payload, handle, sort_keys=True)
            handle.write("\n")
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def local_state() -> Path:
    if os.name == "nt":
        base = Path(os.environ.get("LOCALAPPDATA") or Path.home() / "AppData" / "Local")
    else:
        base = Path.home() / ".local" / "state"
    return base / "SysAdminSuite" / "Antivirus"


@contextmanager
def state_lock(state: Path):
    """A process-owned lock releases automatically after a crash."""
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (state / ".lock").open("a+b") as handle:
        if os.name == "nt":
            import msvcrt
            handle.seek(0)
            lock = lambda: msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            lock = lambda: fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            lock()
        except OSError:
            yield False
        else:
            yield True


def new_receipt(host: str, provider: str, status: str) -> dict[str, str]:
    return {
        "schema_version": RECEIPT_VERSION, "platform": host, "provider": provider,
        "recorded_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "status": status, "next_action": ACTIONS.get(status, "NONE"),
    }


def history_files(state: Path) -> list[Path]:
    history = state / "history"
    if history.is_symlink():
        raise OSError("Antivirus history must be stored in its private directory")
    return sorted((path for path in history.glob("run-*.json")
                   if HISTORY_FILE.fullmatch(path.name) and not path.is_symlink()), reverse=True)


def persist(state: Path, receipt: dict[str, str], *, retain: bool = True) -> None:
    if retain:
        previous = history_files(state)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        write_json(state / "history" / f"run-{stamp}-{uuid4().hex}.json", receipt)
        for old in previous[HISTORY_LIMIT - 1:]:
            old.unlink(missing_ok=True)
    write_json(state / "latest.json", receipt)


def sync_candidates(state: Path, repo: Path = ROOT) -> str:
    """Refresh the ignored checkout queue from retained local outcomes."""
    candidates = {}
    for path in history_files(state):
        try:
            receipt = json.loads(path.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            continue
        if not isinstance(receipt, dict) or receipt.get("schema_version") != RECEIPT_VERSION:
            continue
        code = receipt.get("status")
        candidate = development_candidate(code) if isinstance(code, str) else None
        if candidate:
            candidates[(QUEUE / (candidate["gap_code"].lower() + ".json")).as_posix()] = candidate
    if not candidates:
        return "NO_ACTIONABLE_GAPS"

    git = shutil.which("git")
    target = repo / QUEUE
    if not git or target.resolve() != target or not (repo / ".git").exists():
        return "SYNC_UNAVAILABLE"
    command = (git, "-C", str(repo))
    # Inherited Git plumbing variables can substitute a different checkout or index.
    env = {key: value for key, value in os.environ.items() if not key.upper().startswith("GIT_")}
    tracked = execute((*command, "ls-files", "--", QUEUE.as_posix()), capture=True, env=env)
    ignored = execute((*command, "check-ignore", "--stdin"), capture=True,
                      input_text="\n".join(candidates) + "\n", env=env)
    if (tracked.returncode or tracked.stdout or ignored.returncode or
            set(ignored.stdout.splitlines()) != set(candidates)):
        return "SYNC_UNSAFE"
    for relative, candidate in candidates.items():
        write_json(repo / relative, candidate)
    return "SYNCED_LOCAL"


def run_once(state: Path) -> tuple[dict[str, str], int]:
    with state_lock(state) as acquired:
        if not acquired:
            return {"status": "ALREADY_RUNNING"}, 0
        host = platform_name()
        latest = state / "latest.json"
        if latest.exists():
            try:
                previous = json.loads(latest.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                previous = {}
            if isinstance(previous, dict) and previous.get("status") == "RUNNING":
                persist(state, new_receipt(host, "none", "SCAN_INTERRUPTED"))

        persist(state, new_receipt(host, "none", "RUNNING"), retain=False)
        provider = "none"
        try:
            scanner, status = discover(host)
        except (OSError, KeyError, subprocess.SubprocessError):
            scanner, status = None, "DISCOVERY_FAILED"
        if scanner:
            provider = scanner.provider
            persist(state, new_receipt(host, provider, "RUNNING"), retain=False)
            status = scan(scanner)
        receipt = new_receipt(host, provider, status)
        persist(state, receipt)
        try:
            receipt["repository_sync"] = sync_candidates(state)
        except (OSError, subprocess.SubprocessError):
            receipt["repository_sync"] = "SYNC_FAILED"
        failed_sync = receipt["repository_sync"] in ("SYNC_FAILED", "SYNC_UNSAFE", "SYNC_UNAVAILABLE")
        if failed_sync:
            receipt["sync_next_action"] = "RETRY_LOCAL_QUEUE_SYNC"
        write_json(latest, receipt)
        return receipt, int(status in ACTIONS or failed_sync)


def callback(state: Path) -> tuple[str, ...]:
    return (str(Path(sys.executable).absolute()), "-I", str(Path(__file__).resolve()),
            "--state-dir", str(state), "run", "--quiet")


def cron_line(command: tuple[str, ...], day: str, at: str) -> str:
    if any(re.search(r"[%\r\n\0]", arg) for arg in command):
        raise ValueError("Path cannot be represented reliably in crontab")
    hour, minute = at.split(":")
    return (f"{int(minute)} {int(hour)} * * {DAYS.index(day)} " +
            " ".join(shlex.quote(arg) for arg in command) + " </dev/null >/dev/null 2>&1" +
            CRON_MARKER)


def scheduled_task_xml(command: tuple[str, ...], day: str, at: str) -> str:
    task = ET.Element("Task", {"xmlns": TASK_NS, "version": "1.3"})
    registration = ET.SubElement(task, "RegistrationInfo")
    ET.SubElement(registration, "Description").text = TASK_SOURCE
    triggers = ET.SubElement(task, "Triggers")
    trigger = ET.SubElement(triggers, "CalendarTrigger")
    # A local calendar boundary with no timezone offset preserves the selected wall time.
    ET.SubElement(trigger, "StartBoundary").text = f"{datetime.now().date()}T{at}:00"
    schedule = ET.SubElement(trigger, "ScheduleByWeek")
    ET.SubElement(schedule, "WeeksInterval").text = "1"
    ET.SubElement(ET.SubElement(schedule, "DaysOfWeek"), day)
    principals = ET.SubElement(task, "Principals")
    principal = ET.SubElement(principals, "Principal", {"id": "ScanUser"})
    ET.SubElement(principal, "UserId").text = "REPLACED_BY_CURRENT_SID"
    ET.SubElement(principal, "LogonType").text = "S4U"
    ET.SubElement(principal, "RunLevel").text = "LeastPrivilege"
    settings = ET.SubElement(task, "Settings")
    ET.SubElement(settings, "MultipleInstancesPolicy").text = "IgnoreNew"
    ET.SubElement(settings, "StartWhenAvailable").text = "true"
    ET.SubElement(settings, "DisallowStartIfOnBatteries").text = "true"
    ET.SubElement(settings, "StopIfGoingOnBatteries").text = "true"
    ET.SubElement(settings, "ExecutionTimeLimit").text = "PT2H15M"
    actions = ET.SubElement(task, "Actions", {"Context": "ScanUser"})
    execute_action = ET.SubElement(actions, "Exec")
    ET.SubElement(execute_action, "Command").text = command[0]
    ET.SubElement(execute_action, "Arguments").text = subprocess.list2cmdline(command[1:])
    ET.SubElement(execute_action, "WorkingDirectory").text = str(ROOT)
    return ET.tostring(task, encoding="unicode")


def apply_cron(line: str | None) -> str:
    crontab = shutil.which("crontab")
    if not crontab:
        return "SCHEDULER_UNAVAILABLE"
    env = dict(os.environ, LC_ALL="C")
    query = subprocess.run((crontab, "-l"), capture_output=True, stdin=subprocess.DEVNULL,
                           timeout=30, env=env, check=False)
    if query.returncode and not (query.returncode == 1 and b"no crontab for " in query.stderr):
        return "SCHEDULER_READ_FAILED"
    old = query.stdout if query.returncode == 0 else b""
    marker = CRON_MARKER.encode("ascii")
    # Split physical cron lines only. Preserve unrelated text byte for byte.
    updated = b"\n".join(entry for entry in old.split(b"\n")
                         if not entry.removesuffix(b"\r").endswith(marker))
    if line:
        if updated and not updated.endswith(b"\n"):
            updated += b"\n"
        updated += os.fsencode(line) + b"\n"
    if updated == old:
        return "UNCHANGED"
    write = subprocess.run((crontab, "-"), input=updated, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=30, env=env, check=False)
    if write.returncode:
        return "SCHEDULER_WRITE_FAILED"
    return "INSTALLED" if line else "REMOVED"


def apply_windows_task(xml: str | None) -> str:
    encoded = base64.b64encode((xml or "").encode("utf-8")).decode("ascii")
    setup = r"""
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$name = 'SysAdminSuite-HostAntivirus-' + $sid
$existing = Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue
if ($existing -and $existing.Description -ne 'SysAdminSuite Host Antivirus') {
    'SCHEDULER_NAME_CONFLICT'; exit 0
}
$xml = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('PAYLOAD'))
if ($xml) {
    $xml = $xml.Replace('REPLACED_BY_CURRENT_SID', $sid)
    Register-ScheduledTask -TaskName $name -TaskPath '\' -Xml $xml -Force | Out-Null
    'INSTALLED'
} elseif ($existing) {
    Unregister-ScheduledTask -TaskName $name -TaskPath '\' -Confirm:$false
    'REMOVED'
} else { 'UNCHANGED' }
""".replace("PAYLOAD", encoded)
    result = execute(powershell(setup), capture=True)
    return result.stdout.strip() if result.returncode == 0 else "SCHEDULER_WRITE_FAILED"


def manage_schedule(args: argparse.Namespace, state: Path) -> tuple[dict[str, str], int]:
    host = platform_name() if args.operation != "plan" else args.platform or platform_name()
    if host not in ("linux", "windows"):
        return {"status": "UNSUPPORTED_HOST"}, 1
    command = callback(state)
    plan = cron_line(command, args.day, args.at) if host == "linux" else scheduled_task_xml(
        command, args.day, args.at
    )
    if args.operation == "plan":
        return {"status": "PLAN_ONLY", "scheduler": host, "plan": plan}, 0
    if host == "linux":
        status = apply_cron(plan if args.operation == "install" else None)
    else:
        status = apply_windows_task(plan if args.operation == "install" else None)
    return {"status": status, "scheduler": host}, int(status not in ("INSTALLED", "REMOVED", "UNCHANGED"))


def clock_time(value: str) -> str:
    if not re.fullmatch(r"(?:[01][0-9]|2[0-3]):[0-5][0-9]", value):
        raise argparse.ArgumentTypeError("expected local time HH:MM in 24-hour format")
    return value


def private_state_path(state: Path) -> Path:
    state = state.expanduser().resolve()
    if any((parent / ".git").exists() for parent in (state, *state.parents)):
        raise ValueError("Private state must be outside Git working trees")
    for name in (".lock", "latest.json", "history"):
        if (state / name).is_symlink():
            raise ValueError("Private state cannot use symlinks")
    return state


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", type=Path, default=local_state(),
                        help="private directory outside the checkout")
    actions = parser.add_subparsers(dest="action", required=True)
    actions.add_parser("inspect", help="detect a provider without scanning")
    actions.add_parser("sync", help="retry ignored checkout queue sync")
    actions.add_parser("run", help="run one local scan").add_argument("--quiet", action="store_true")
    schedule = actions.add_parser("schedule", help="preview, install or remove one weekly job")
    schedule.add_argument("operation", choices=("plan", "install", "remove"))
    schedule.add_argument("--platform", choices=("linux", "windows"), help="preview platform only")
    schedule.add_argument("--day", choices=DAYS, default="Sunday")
    schedule.add_argument("--at", type=clock_time, default="03:30")
    args = parser.parse_args()
    try:
        state = private_state_path(args.state_dir)
        if args.action == "run":
            result, status = run_once(state)
        elif args.action == "sync":
            result = {"status": sync_candidates(state)}
            status = int(result["status"] not in ("SYNCED_LOCAL", "NO_ACTIONABLE_GAPS"))
        elif args.action == "schedule":
            if args.platform and args.operation != "plan":
                raise ValueError("Platform override is for preview only")
            result, status = manage_schedule(args, state)
        else:
            host = platform_name()
            scanner, reason = discover(host)
            result = {"platform": host, "status": "READY" if scanner else reason,
                      "provider": scanner.provider if scanner else "none"}
            status = int(scanner is None)
    except (ValueError, KeyError, OSError, subprocess.SubprocessError):
        result, status = {"status": "OPERATION_FAILED"}, 2
    if not getattr(args, "quiet", False):
        print(json.dumps(result, sort_keys=True))
    return status


if __name__ == "__main__":
    raise SystemExit(main())
