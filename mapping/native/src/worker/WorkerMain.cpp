#include "../common/json_util.hpp"
#include "../common/path_util.hpp"
#include "../common/string_util.hpp"
#include "artifacts.hpp"
#include "default_printer_task.hpp"
#include "print_ops.hpp"
#include "printers.hpp"
#include "registry_unc.hpp"
#include "result_rows.hpp"
#include "run_control.hpp"
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <atomic>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <vector>

#pragma comment(lib, "Advapi32.lib")

static std::atomic_bool g_stop{false};
static BOOL WINAPI ConsoleCtrlHandler(DWORD) {
  g_stop = true;
  return TRUE;
}

static void PushStr(JsonDataMap& m, const char* k, const std::wstring& w) {
  JsonValue v;
  v.kind = JsonValue::String;
  v.str = WideToUtf8(w);
  m[k] = v;
}
static void PushBool(JsonDataMap& m, const char* k, bool b) {
  JsonValue v;
  v.kind = JsonValue::Bool;
  v.b = b;
  m[k] = v;
}
static void PushStrArr(JsonDataMap& m, const char* k, const std::vector<std::wstring>& arr) {
  JsonValue v;
  v.kind = JsonValue::Array;
  for (const auto& s : arr) v.arr.push_back(WideToUtf8(s));
  m[k] = v;
}

static bool IsElevatedAdmin() {
  BOOL is = FALSE;
  SID_IDENTIFIER_AUTHORITY NtAuthority = SECURITY_NT_AUTHORITY;
  PSID AdminGroup = nullptr;
  if (!AllocateAndInitializeSid(&NtAuthority, 2, SECURITY_BUILTIN_DOMAIN_RID, DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0,
                                  0, &AdminGroup))
    return false;
  CheckTokenMembership(nullptr, AdminGroup, &is);
  FreeSid(AdminGroup);
  return is != FALSE;
}

static bool SpoolerServiceExists() {
  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (!scm) return false;
  SC_HANDLE svc = OpenServiceW(scm, L"Spooler", SERVICE_QUERY_STATUS);
  bool ok = svc != nullptr;
  if (svc) CloseServiceHandle(svc);
  CloseServiceHandle(scm);
  return ok;
}

static void ReadQueuesFile(const std::wstring& path, std::vector<std::wstring>& out) {
  std::ifstream in(std::filesystem::path(path));
  if (!in) return;
  std::string line;
  while (std::getline(in, line)) {
    std::wstring w = Utf8ToWide(line);
    w = Trim(w);
    if (w.empty() || w[0] == L'#') continue;
    out.push_back(ToLower(w));
  }
}

static bool ArgEquals(const wchar_t* a, const wchar_t* b) {
  return _wcsicmp(a, b) == 0;
}

static void PrintUsage() {
  std::wcerr << L"SysAdminSuite.Mapping.Worker — machine-wide printer mapping\n";
  std::wcerr << L"Usage: SysAdminSuite.Mapping.Worker [options]\n";
  std::wcerr << L"  -ListOnly -Preflight -PlanOnly -PruneNotInList -RestartSpoolerIfNeeded\n";
  std::wcerr << L"  -OutputRoot <path>\n";
  std::wcerr << L"  -Queues <unc,unc>  (repeatable)  -QueuesFile <path>\n";
  std::wcerr << L"  -RemoveQueues <unc,...>  -RemoveQueuesFile <path>\n";
  std::wcerr << L"  -DefaultQueue <unc>\n";
  std::wcerr << L"  -StopSignalPath <path>  -StatusPath <path>\n";
}

struct Options {
  bool listOnly = false;
  bool planOnly = false;
  bool preflight = false;
  bool pruneNotInList = false;
  bool restartSpooler = false;
  bool enableUndoRedo = false;
  std::wstring outputRoot = L"C:\\ProgramData\\SysAdminSuite\\Mapping";
  std::vector<std::wstring> queues;
  std::wstring queuesFile;
  std::vector<std::wstring> removeQueues;
  std::wstring removeQueuesFile;
  std::wstring defaultQueue;
  std::wstring stopSignalPath;
  std::wstring statusPath;
};

static bool ParseOptions(int argc, wchar_t** argv, Options& o) {
  for (int i = 1; i < argc; ++i) {
    const wchar_t* a = argv[i];
    if (ArgEquals(a, L"-?") || ArgEquals(a, L"/?") || ArgEquals(a, L"--help") || ArgEquals(a, L"-help")) return false;
    if (ArgEquals(a, L"-ListOnly") || ArgEquals(a, L"/ListOnly")) {
      o.listOnly = true;
      continue;
    }
    if (ArgEquals(a, L"-PlanOnly") || ArgEquals(a, L"/PlanOnly")) {
      o.planOnly = true;
      continue;
    }
    if (ArgEquals(a, L"-Preflight") || ArgEquals(a, L"/Preflight")) {
      o.preflight = true;
      continue;
    }
    if (ArgEquals(a, L"-PruneNotInList") || ArgEquals(a, L"/PruneNotInList")) {
      o.pruneNotInList = true;
      continue;
    }
    if (ArgEquals(a, L"-RestartSpoolerIfNeeded") || ArgEquals(a, L"/RestartSpoolerIfNeeded")) {
      o.restartSpooler = true;
      continue;
    }
    if (ArgEquals(a, L"-EnableUndoRedo") || ArgEquals(a, L"/EnableUndoRedo")) {
      o.enableUndoRedo = true;
      continue;
    }
#define TAKEVAL(name)                                                                                                  \
  do {                                                                                                                 \
    if (i + 1 >= argc) return false;                                                                                   \
    o.name = argv[++i];                                                                                                \
  } while (0)
    if (ArgEquals(a, L"-OutputRoot") || ArgEquals(a, L"/OutputRoot")) {
      TAKEVAL(outputRoot);
      continue;
    }
    if (ArgEquals(a, L"-Queues") || ArgEquals(a, L"/Queues")) {
      if (i + 1 >= argc) return false;
      std::vector<std::wstring> chunk;
      SplitCommaList(argv[++i], chunk);
      o.queues.insert(o.queues.end(), chunk.begin(), chunk.end());
      continue;
    }
    if (ArgEquals(a, L"-QueuesFile") || ArgEquals(a, L"/QueuesFile")) {
      TAKEVAL(queuesFile);
      continue;
    }
    if (ArgEquals(a, L"-RemoveQueues") || ArgEquals(a, L"/RemoveQueues")) {
      if (i + 1 >= argc) return false;
      SplitCommaList(argv[++i], o.removeQueues);
      continue;
    }
    if (ArgEquals(a, L"-RemoveQueuesFile") || ArgEquals(a, L"/RemoveQueuesFile")) {
      TAKEVAL(removeQueuesFile);
      continue;
    }
    if (ArgEquals(a, L"-DefaultQueue") || ArgEquals(a, L"/DefaultQueue")) {
      TAKEVAL(defaultQueue);
      continue;
    }
    if (ArgEquals(a, L"-StopSignalPath") || ArgEquals(a, L"/StopSignalPath")) {
      TAKEVAL(stopSignalPath);
      continue;
    }
    if (ArgEquals(a, L"-StatusPath") || ArgEquals(a, L"/StatusPath")) {
      TAKEVAL(statusPath);
      continue;
    }
#undef TAKEVAL
    std::wcerr << L"Unknown argument: " << a << L"\n";
    return false;
  }
  return true;
}

static void LogLine(const std::wstring& logPath, bool doLog, const std::wstring& line) {
  std::wstring ts = Iso8601Local();
  std::wstring full = L"[" + ts + L"] " + line;
  std::wcout << full << L"\n";
  if (doLog && !logPath.empty()) {
    AppendLogLineUtf8(logPath, WideToUtf8(full));
  }
}

int wmain(int argc, wchar_t** argv) {
  Options opt;
  if (!ParseOptions(argc, argv, opt)) {
    PrintUsage();
    return 2;
  }

  if (opt.enableUndoRedo) {
    std::wcerr << L"[WARN] -EnableUndoRedo is not supported by the native worker; continuing without undo capture.\n";
  }

  SetConsoleCtrlHandler(ConsoleCtrlHandler, TRUE);

  std::vector<std::wstring> desired = opt.queues;
  for (auto& q : desired) q = ToLower(Trim(q));
  if (!opt.queuesFile.empty()) ReadQueuesFile(opt.queuesFile, desired);

  std::vector<std::wstring> removeList;
  for (const auto& r : opt.removeQueues) removeList.push_back(ToLower(Trim(r)));
  if (!opt.removeQueuesFile.empty()) ReadQueuesFile(opt.removeQueuesFile, removeList);

  if (!opt.defaultQueue.empty()) opt.defaultQueue = ToLower(Trim(opt.defaultQueue));

  bool doIo = opt.listOnly || opt.planOnly || !desired.empty() || !removeList.empty() || !opt.defaultQueue.empty();

  std::wstring outDir, logPath, preflightCsv, resultsCsv, htmlPath;
  if (doIo) {
    std::wstring logsRoot = JoinPath(opt.outputRoot, L"logs");
    EnsureDirectory(opt.outputRoot);
    EnsureDirectory(logsRoot);
    std::wstring stamp = LocalTimestampFolder();
    outDir = JoinPath(logsRoot, stamp);
    EnsureDirectory(outDir);
    logPath = JoinPath(outDir, L"Run.log");
    preflightCsv = JoinPath(outDir, L"Preflight.csv");
    resultsCsv = JoinPath(outDir, L"Results.csv");
    htmlPath = JoinPath(outDir, L"Results.html");
  }

  std::wstring stopPath = opt.stopSignalPath.empty() ? JoinPath(opt.outputRoot, L"Stop.json") : opt.stopSignalPath;
  std::wstring statusPath = opt.statusPath.empty() ? JoinPath(opt.outputRoot, L"status.json") : opt.statusPath;

  std::wstring computer = GetEnvW(L"COMPUTERNAME");
  if (computer.empty()) computer = L"UNKNOWN";

  auto exportStatus = [&](const std::wstring& state, const std::wstring& stage, const std::wstring& msg) {
    JsonDataMap data;
    PushStr(data, "ComputerName", computer);
    PushStr(data, "OutputRoot", opt.outputRoot);
    PushStr(data, "OutputDirectory", outDir);
    PushStr(data, "LogPath", logPath);
    PushStr(data, "ResultsPath", resultsCsv);
    PushStr(data, "HtmlPath", htmlPath);
    PushStr(data, "PreflightPath", preflightCsv);
    PushStr(data, "StopSignalPath", stopPath);
    PushBool(data, "StopRequested", g_stop.load());
    PushBool(data, "EnableUndoRedo", false);
    PushStr(data, "UndoRedoLogPath", L"");
    PushStrArr(data, "DesiredQueues", desired);
    PushStrArr(data, "RemoveQueues", removeList);
    PushBool(data, "ListOnly", opt.listOnly);
    PushBool(data, "PlanOnly", opt.planOnly);
    ExportWorkerStatus(statusPath, state, stage, msg, data);
  };

  LogLine(logPath, doIo, L"=== Printer Map start (" + computer + L") ===");
  if (doIo) LogLine(logPath, doIo, L"Artifacts -> " + outDir);
  exportStatus(L"Running", L"Startup", L"Worker initialized.");

  if (opt.preflight) {
    if (!SpoolerServiceExists()) {
      std::wcerr << L"Spooler service not found.\n";
      return 1;
    }
    LogLine(logPath, doIo, L"Spooler: present");
    if (!IsElevatedAdmin()) LogLine(logPath, doIo, L"WARN: Not elevated; machine-wide actions may fail.");
  }

  std::vector<std::wstring> beforeUnc = GetGlobalUncConnectionsLowercase();
  std::vector<LocalPrinterInfo> beforeLocal = EnumLocalPrinters();

  std::wstring tsIso = Iso8601Local();
  if (doIo) {
    WritePreflightCsv(preflightCsv, computer, tsIso, beforeUnc, desired);
  }
  exportStatus(L"Running", L"Preflight", L"Preflight snapshot captured.");

  if (opt.listOnly) {
    std::vector<ResultRow> rows;
    for (const auto& u : beforeUnc) {
      ResultRow r;
      r.timestamp = tsIso;
      r.computer = computer;
      r.type = L"UNC";
      r.target = u;
      r.status = L"PresentNow";
      rows.push_back(std::move(r));
    }
    for (const auto& p : beforeLocal) {
      ResultRow r;
      r.timestamp = tsIso;
      r.computer = computer;
      r.type = L"LOCAL";
      r.target = p.name;
      r.driver = p.driver;
      r.port = p.port;
      r.status = L"PresentNow";
      rows.push_back(std::move(r));
    }
    if (doIo) {
      WriteResultsCsv(resultsCsv, rows);
      WriteResultsHtml(htmlPath, L"Printer Mappings - " + computer + L" (ListOnly)", rows, true, logPath);
      LogLine(logPath, doIo, L"Artifacts written.");
    }
    exportStatus(L"Completed", L"ListOnly", L"ListOnly inventory completed.");
    LogLine(logPath, doIo, L"=== Completed (ListOnly) ===");
    return 0;
  }

  bool changed = false;
  if (opt.planOnly) {
    LogLine(logPath, doIo, L"PLAN-ONLY mode; no changes executed.");
    exportStatus(L"Running", L"PlanOnly", L"Plan-only mode; no changes executed.");
  } else {
    for (const auto& u : desired) {
      if (IsStopRequested(stopPath, g_stop.load())) {
        LogLine(logPath, doIo, L"Stop requested; skipping remaining adds.");
        break;
      }
      bool present = false;
      for (const auto& b : beforeUnc)
        if (b == u) present = true;
      if (!present) {
        if (RunRundll32PrintUi(L"/ga", u)) {
          LogLine(logPath, doIo, L"ADD (/ga) -> " + u);
          changed = true;
        }
      } else {
        LogLine(logPath, doIo, L"SKIP add; already present -> " + u);
      }
    }
    for (const auto& u : removeList) {
      if (IsStopRequested(stopPath, g_stop.load())) break;
      if (RunRundll32PrintUi(L"/gd", u)) {
        LogLine(logPath, doIo, L"REMOVE (/gd) -> " + u);
        changed = true;
      }
    }
    if (!g_stop.load() && opt.pruneNotInList && !desired.empty()) {
      std::vector<std::wstring> cur = GetGlobalUncConnectionsLowercase();
      for (const auto& u : cur) {
        if (IsStopRequested(stopPath, g_stop.load())) break;
        bool inDes = false;
        for (const auto& d : desired)
          if (d == u) inDes = true;
        if (!inDes) {
          if (RunRundll32PrintUi(L"/gd", u)) {
            LogLine(logPath, doIo, L"PRUNE (/gd) -> " + u);
            changed = true;
          }
        }
      }
    }
    if (!g_stop.load() && !opt.defaultQueue.empty()) {
      if (RegisterSetDefaultPrinterOnce(opt.defaultQueue))
        LogLine(logPath, doIo, L"Registered one-shot default printer task for " + opt.defaultQueue);
      else
        LogLine(logPath, doIo, L"WARN: Failed to register default-printer scheduled task.");
    }
    if (!g_stop.load()) {
      RunGpUpdateComputer();
      LogLine(logPath, doIo, L"gpupdate /target:computer /force completed");
    }
    if (!g_stop.load() && changed && opt.restartSpooler) {
      if (RestartSpoolerService())
        LogLine(logPath, doIo, L"Spooler restarted.");
      else
        LogLine(logPath, doIo, L"WARN: Spooler restart failed.");
    }
  }

  std::vector<std::wstring> afterUnc = GetGlobalUncConnectionsLowercase();
  std::vector<LocalPrinterInfo> afterLocal = EnumLocalPrinters();

  std::wstring ts2 = Iso8601Local();
  std::vector<ResultRow> rows =
      BuildResultRows(computer, ts2, beforeUnc, afterUnc, desired, removeList, opt.planOnly, opt.pruneNotInList, afterLocal);
  if (doIo) {
    WriteResultsCsv(resultsCsv, rows);
    WriteResultsHtml(htmlPath, L"Printer Mapping Results - " + computer, rows, false, logPath);
    LogLine(logPath, doIo, L"Artifacts written.");
  }

  std::wstring finalState = g_stop.load() ? L"Stopped" : L"Completed";
  std::wstring finalMsg =
      g_stop.load() ? L"Stop requested; partial artifacts emitted." : L"Worker completed successfully.";
  exportStatus(finalState, L"Complete", finalMsg);
  LogLine(logPath, doIo, L"=== Completed ===");
  return 0;
}
