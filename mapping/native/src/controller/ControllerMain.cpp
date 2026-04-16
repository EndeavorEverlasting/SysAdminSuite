#include "../common/json_util.hpp"
#include "../common/path_util.hpp"
#include "../common/string_util.hpp"
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <algorithm>
#include <atomic>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <vector>

static std::atomic_bool g_stop{false};
static BOOL WINAPI ConsoleCtrlHandler(DWORD) {
  g_stop = true;
  return TRUE;
}

static std::wstring JoinAdminShare(const std::wstring& computer, const std::wstring& subPath) {
  std::wstring p = subPath;
  if (p.size() >= 2 && p[1] == L':') {
    wchar_t d = p[0];
    if ((d >= L'A' && d <= L'Z') || (d >= L'a' && d <= L'z')) p = p.substr(2);
  }
  while (!p.empty() && (p[0] == L'\\' || p[0] == L'/')) p = p.substr(1);
  return L"\\\\" + computer + L"\\C$\\" + p;
}

static std::wstring GetExeDir() {
  wchar_t buf[MAX_PATH];
  DWORD n = GetModuleFileNameW(nullptr, buf, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) return L".";
  std::wstring full(buf, n);
  size_t slash = full.find_last_of(L"\\/");
  if (slash == std::wstring::npos) return L".";
  return full.substr(0, slash);
}

static std::wstring DefaultSessionRoot() {
  wchar_t cwd[MAX_PATH];
  GetCurrentDirectoryW(MAX_PATH, cwd);
  std::wstring root = cwd;
  SYSTEMTIME st{};
  GetLocalTime(&st);
  wchar_t stamp[32];
  swprintf_s(stamp, L"SysAdminSuite-Session-%04u%02u%02u-%02u%02u%02u", static_cast<unsigned>(st.wYear),
             static_cast<unsigned>(st.wMonth), static_cast<unsigned>(st.wDay),
             static_cast<unsigned>(st.wHour), static_cast<unsigned>(st.wMinute),
             static_cast<unsigned>(st.wSecond));
  return JoinPath(root, stamp);
}

static void FileTimeAddOneMinute(SYSTEMTIME& st) {
  FILETIME ft{};
  SystemTimeToFileTime(&st, &ft);
  ULARGE_INTEGER uli{};
  uli.LowPart = ft.dwLowDateTime;
  uli.HighPart = ft.dwHighDateTime;
  uli.QuadPart += 60ULL * 10'000'000ULL;
  ft.dwLowDateTime = uli.LowPart;
  ft.dwHighDateTime = uli.HighPart;
  FileTimeToSystemTime(&ft, &st);
}

static bool FormatSchTasksDateTime(const SYSTEMTIME& st, std::wstring& dateOut, std::wstring& timeOut) {
  wchar_t dbuf[128]{};
  wchar_t tbuf[32]{};
  if (GetDateFormatW(LOCALE_USER_DEFAULT, DATE_SHORTDATE, &st, nullptr, dbuf, static_cast<int>(std::size(dbuf))) == 0)
    return false;
  if (GetTimeFormatW(LOCALE_USER_DEFAULT, TIME_NOTIMEMARKER | TIME_FORCE24HOURFORMAT, &st, nullptr, tbuf,
                     static_cast<int>(std::size(tbuf))) == 0)
    return false;
  dateOut = dbuf;
  timeOut = tbuf;
  return true;
}

static int RunCmdCapture(const std::wstring& cmdline, std::wstring& output) {
  HANDLE rOut = nullptr, wOut = nullptr;
  SECURITY_ATTRIBUTES sa{};
  sa.nLength = sizeof(sa);
  sa.bInheritHandle = TRUE;
  if (!CreatePipe(&rOut, &wOut, &sa, 0)) return -1;
  SetHandleInformation(rOut, HANDLE_FLAG_INHERIT, 0);
  STARTUPINFOW si{};
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESTDHANDLES;
  si.hStdOutput = wOut;
  si.hStdError = wOut;
  si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  PROCESS_INFORMATION pi{};
  std::wstring mutableLine = L"cmd.exe /c " + cmdline;
  BOOL ok = CreateProcessW(nullptr, mutableLine.data(), nullptr, nullptr, TRUE, CREATE_NO_WINDOW, nullptr, nullptr, &si,
                           &pi);
  CloseHandle(wOut);
  if (!ok) {
    CloseHandle(rOut);
    return -1;
  }
  char buf[4096];
  DWORD n = 0;
  output.clear();
  while (ReadFile(rOut, buf, sizeof(buf) - 1, &n, nullptr) && n > 0) {
    buf[n] = 0;
    output += Utf8ToWide(std::string(buf, buf + n));
  }
  CloseHandle(rOut);
  WaitForSingleObject(pi.hProcess, INFINITE);
  DWORD code = 1;
  GetExitCodeProcess(pi.hProcess, &code);
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  return static_cast<int>(code);
}

static void AppendLog(const std::wstring& path, const std::wstring& line) {
  std::wstring ts = Iso8601Local();
  std::wstring full = L"[" + ts + L"] " + line + L"\r\n";
  HANDLE h = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                         nullptr);
  if (h == INVALID_HANDLE_VALUE) return;
  std::string u8 = WideToUtf8(full);
  DWORD w = 0;
  WriteFile(h, u8.data(), static_cast<DWORD>(u8.size()), &w, nullptr);
  CloseHandle(h);
  std::wcout << full;
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
static void PushInt(JsonDataMap& m, const char* k, int n) {
  JsonValue v;
  v.kind = JsonValue::String;
  v.str = std::to_string(n);
  m[k] = v;
}

struct Options {
  std::vector<std::wstring> computers;
  std::wstring computerFile;
  std::wstring localWorkerPath;
  std::wstring sessionRoot;
  std::wstring remoteBase = L"C:\\ProgramData\\SysAdminSuite\\Mapping";
  std::wstring taskName = L"SysAdminSuite_PrinterMap";
  int maxWaitSeconds = 45;
  std::wstring workerArgs;
  std::wstring stopSignalPath;
  std::wstring statusPath;
};

static bool ArgEq(const wchar_t* a, const wchar_t* b) {
  return _wcsicmp(a, b) == 0;
}

static bool ParseOpts(int argc, wchar_t** argv, Options& o) {
  o.localWorkerPath = JoinPath(GetExeDir(), L"SysAdminSuite.Mapping.Worker.exe");
  o.sessionRoot = DefaultSessionRoot();
  for (int i = 1; i < argc; ++i) {
    const wchar_t* a = argv[i];
    if (ArgEq(a, L"-Computer") || ArgEq(a, L"-Computers")) {
      if (i + 1 >= argc) return false;
      std::vector<std::wstring> chunk;
      SplitCommaList(argv[++i], chunk);
      for (auto& c : chunk)
        if (!Trim(c).empty()) o.computers.push_back(Trim(c));
      continue;
    }
    if (ArgEq(a, L"-ComputerFile")) {
      if (i + 1 >= argc) return false;
      o.computerFile = argv[++i];
      continue;
    }
    if (ArgEq(a, L"-LocalWorkerPath")) {
      if (i + 1 >= argc) return false;
      o.localWorkerPath = argv[++i];
      continue;
    }
    if (ArgEq(a, L"-SessionRoot")) {
      if (i + 1 >= argc) return false;
      o.sessionRoot = argv[++i];
      continue;
    }
    if (ArgEq(a, L"-RemoteBase")) {
      if (i + 1 >= argc) return false;
      o.remoteBase = argv[++i];
      continue;
    }
    if (ArgEq(a, L"-TaskName")) {
      if (i + 1 >= argc) return false;
      o.taskName = argv[++i];
      continue;
    }
    if (ArgEq(a, L"-MaxWaitSeconds")) {
      if (i + 1 >= argc) return false;
      o.maxWaitSeconds = _wtoi(argv[++i]);
      continue;
    }
    if (ArgEq(a, L"-WorkerArgs")) {
      if (i + 1 >= argc) return false;
      o.workerArgs = argv[++i];
      continue;
    }
    if (ArgEq(a, L"-StopSignalPath")) {
      if (i + 1 >= argc) return false;
      o.stopSignalPath = argv[++i];
      continue;
    }
    if (ArgEq(a, L"-StatusPath")) {
      if (i + 1 >= argc) return false;
      o.statusPath = argv[++i];
      continue;
    }
    return false;
  }
  return true;
}

static void LoadComputerFile(const std::wstring& path, std::vector<std::wstring>& out) {
  std::ifstream in(std::filesystem::path(path));
  std::string line;
  while (std::getline(in, line)) {
    std::wstring w = Trim(Utf8ToWide(line));
    if (w.empty() || w[0] == L'#') continue;
    out.push_back(w);
  }
}

static bool CopyFileOverwrite(const std::wstring& src, const std::wstring& dst) {
  return CopyFileW(src.c_str(), dst.c_str(), FALSE) != FALSE;
}

static std::wstring FindLatestLogDir(const std::wstring& adminLogs) {
  std::wstring pattern = JoinPath(adminLogs, L"*");
  WIN32_FIND_DATAW fd{};
  HANDLE h = FindFirstFileW(pattern.c_str(), &fd);
  if (h == INVALID_HANDLE_VALUE) return {};
  std::wstring best;
  do {
    if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && wcscmp(fd.cFileName, L".") != 0 &&
        wcscmp(fd.cFileName, L"..") != 0) {
      if (best.empty() || wcscmp(fd.cFileName, best.c_str()) > 0) {
        best = fd.cFileName;
      }
    }
  } while (FindNextFileW(h, &fd));
  FindClose(h);
  if (best.empty()) return {};
  return JoinPath(adminLogs, best);
}

static bool InvokeHost(const Options& opt, const std::wstring& computer, const std::wstring& controllerLog,
                       int& success, int& fail) {
  std::wstring remoteWorkerRel = JoinPath(opt.remoteBase, L"SysAdminSuite.Mapping.Worker.exe");
  std::wstring remoteLogs = JoinPath(opt.remoteBase, L"logs");
  std::wstring adminBase = JoinAdminShare(computer, opt.remoteBase);
  std::wstring adminLogs = JoinAdminShare(computer, remoteLogs);
  std::wstring adminWorker = JoinAdminShare(computer, remoteWorkerRel);
  std::wstring adminStop = JoinAdminShare(computer, JoinPath(opt.remoteBase, L"Stop.json"));
  std::wstring adminStatus = JoinAdminShare(computer, JoinPath(opt.remoteBase, L"status.json"));

  AppendLog(controllerLog, L"==== [" + computer + L"] Begin ====");
  if (!EnsureDirectoryRecursive(adminBase)) {
    AppendLog(controllerLog, L"[" + computer + L"] ERROR creating remote folders.");
    fail++;
    return false;
  }
  EnsureDirectoryRecursive(adminLogs);

  DeleteFileW(adminStop.c_str());
  DeleteFileW(adminStatus.c_str());

  if (!CopyFileOverwrite(opt.localWorkerPath, adminWorker)) {
    AppendLog(controllerLog, L"[" + computer + L"] ERROR copying worker exe -> " + adminWorker);
    fail++;
    return false;
  }
  AppendLog(controllerLog, L"[" + computer + L"] Copied worker -> " + adminWorker);

  SYSTEMTIME st{};
  GetLocalTime(&st);
  FileTimeAddOneMinute(st);
  std::wstring stDate, stTime;
  if (!FormatSchTasksDateTime(st, stDate, stTime)) {
    AppendLog(controllerLog, L"[" + computer + L"] ERROR formatting schedule time.");
    fail++;
    return false;
  }

  std::wstring remoteExeFull = JoinPath(opt.remoteBase, L"SysAdminSuite.Mapping.Worker.exe");
  std::wstring trValue = remoteExeFull;
  if (!opt.workerArgs.empty()) trValue += L" " + opt.workerArgs;
  std::wstring createCmd = L"schtasks /Create /S " + computer + L" /RU SYSTEM /SC ONCE /SD \"" + stDate + L"\" /ST \"" +
                           stTime + L"\" /TN \"" + opt.taskName + L"\" /TR \"" + trValue + L"\" /RL HIGHEST /F";
  std::wstring out;
  int code = RunCmdCapture(createCmd, out);
  AppendLog(controllerLog, L"[" + computer + L"] schtasks /Create output:\n" + out);
  if (code != 0) {
    AppendLog(controllerLog, L"[" + computer + L"] ERROR creating task. ExitCode=" + std::to_wstring(code));
    fail++;
    return false;
  }

  std::wstring runCmd = L"schtasks /Run /S " + computer + L" /TN \"" + opt.taskName + L"\"";
  code = RunCmdCapture(runCmd, out);
  AppendLog(controllerLog, L"[" + computer + L"] schtasks /Run output:\n" + out);
  if (code != 0) {
    AppendLog(controllerLog, L"[" + computer + L"] ERROR running task. ExitCode=" + std::to_wstring(code));
    fail++;
    return false;
  }

  int maxWait = (std::max)(5, opt.maxWaitSeconds);
  int waited = 0;
  std::wstring latest;
  while (waited < maxWait) {
    if (g_stop.load()) break;
    latest = FindLatestLogDir(adminLogs);
    if (!latest.empty()) break;
    Sleep(3000);
    waited += 3;
  }

  std::wstring hostOut = JoinPath(opt.sessionRoot, computer);
  if (!latest.empty()) {
    EnsureDirectoryRecursive(hostOut);
    std::wstring pattern = JoinPath(latest, L"*");
    WIN32_FIND_DATAW fd{};
    HANDLE fh = FindFirstFileW(pattern.c_str(), &fd);
    if (fh != INVALID_HANDLE_VALUE) {
      do {
        if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
          std::wstring src = JoinPath(latest, fd.cFileName);
          std::wstring dst = JoinPath(hostOut, fd.cFileName);
          CopyFileOverwrite(src, dst);
        }
      } while (FindNextFileW(fh, &fd));
      FindClose(fh);
    }
    if (FileExists(adminStatus)) CopyFileOverwrite(adminStatus, JoinPath(hostOut, L"Worker.Status.json"));
    AppendLog(controllerLog, L"[" + computer + L"] Collected artifacts -> " + hostOut);
    GetFileAttributesW(latest.c_str());
    WIN32_FIND_DATAW fd2{};
    HANDLE fh2 = FindFirstFileW((JoinPath(latest, L"*")).c_str(), &fd2);
    if (fh2 != INVALID_HANDLE_VALUE) {
      do {
        if (!(fd2.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
          DeleteFileW(JoinPath(latest, fd2.cFileName).c_str());
        }
      } while (FindNextFileW(fh2, &fd2));
      FindClose(fh2);
    }
    RemoveDirectoryW(latest.c_str());
  } else {
    AppendLog(controllerLog, L"[" + computer + L"] No artifacts detected after " + std::to_wstring(maxWait) +
                                L" seconds.");
  }

  std::wstring delOut;
  RunCmdCapture(L"schtasks /Delete /S " + computer + L" /TN \"" + opt.taskName + L"\" /F", delOut);
  DeleteFileW(adminStop.c_str());
  AppendLog(controllerLog, L"[" + computer + L"] Deleted task " + opt.taskName);
  AppendLog(controllerLog, L"==== [" + computer + L"] End ====");
  success++;
  return true;
}

int wmain(int argc, wchar_t** argv) {
  Options opt;
  if (!ParseOpts(argc, argv, opt)) {
    std::wcerr << L"SysAdminSuite.Mapping.Controller\n";
    std::wcerr << L"Usage: -Computer host1,host2 | -ComputerFile path [options]\n";
    std::wcerr << L"  -LocalWorkerPath -SessionRoot -RemoteBase -TaskName -MaxWaitSeconds\n";
    std::wcerr << L"  -WorkerArgs \"...\"  -StopSignalPath -StatusPath\n";
    return 2;
  }

  if (!opt.computerFile.empty()) LoadComputerFile(opt.computerFile, opt.computers);
  if (opt.computers.empty()) {
    std::wcerr << L"No computers specified.\n";
    return 2;
  }

  if (!FileExists(opt.localWorkerPath)) {
    std::wcerr << L"Local worker not found: " << opt.localWorkerPath << L"\n";
    return 2;
  }

  SetConsoleCtrlHandler(ConsoleCtrlHandler, TRUE);

  EnsureDirectoryRecursive(opt.sessionRoot);
  std::wstring controllerLog = JoinPath(opt.sessionRoot, L"controller-log.txt");
  std::wstring localStop = opt.stopSignalPath.empty() ? JoinPath(opt.sessionRoot, L"Stop.json") : opt.stopSignalPath;
  std::wstring localStatus =
      opt.statusPath.empty() ? JoinPath(opt.sessionRoot, L"Controller.Status.json") : opt.statusPath;

  AppendLog(controllerLog, Iso8601Local() + L" Session start -> " + opt.sessionRoot);

  int success = 0, fail = 0;
  for (const auto& c : opt.computers) {
    if (g_stop.load()) break;
    InvokeHost(opt, c, controllerLog, success, fail);
  }

  AppendLog(controllerLog, L"Session complete. Success: " + std::to_wstring(success) + L"  Failed: " +
                              std::to_wstring(fail) + L"  Hosts total: " + std::to_wstring(opt.computers.size()));

  JsonDataMap data;
  PushStr(data, "SessionRoot", opt.sessionRoot);
  PushStr(data, "ControllerLog", controllerLog);
  PushStr(data, "StopSignalPath", localStop);
  PushBool(data, "StopRequested", g_stop.load());
  PushStr(data, "CurrentHost", L"");
  PushInt(data, "SuccessCount", success);
  PushInt(data, "FailCount", fail);
  PushInt(data, "HostsTotal", static_cast<int>(opt.computers.size()));
  std::string json = BuildStatusJson(Iso8601Local(), L"Completed", L"Complete", L"Controller session finalized.", data);
  WriteWholeFileUtf8(localStatus, json, true);

  return fail > 0 ? 1 : 0;
}
