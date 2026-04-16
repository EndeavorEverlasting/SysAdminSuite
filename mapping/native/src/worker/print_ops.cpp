#include "print_ops.hpp"
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

#pragma comment(lib, "Shell32.lib")

static bool RunProcess(const std::wstring& app, const std::wstring& cmdline) {
  STARTUPINFOW si{};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi{};
  std::wstring mutableLine = cmdline;
  BOOL ok = CreateProcessW(app.empty() ? nullptr : app.c_str(), mutableLine.data(), nullptr, nullptr, FALSE,
                           CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi);
  if (!ok) return false;
  WaitForSingleObject(pi.hProcess, INFINITE);
  DWORD code = 1;
  GetExitCodeProcess(pi.hProcess, &code);
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  return code == 0;
}

bool RunRundll32PrintUi(const std::wstring& verbGaOrGd, const std::wstring& uncLower) {
  wchar_t sysDir[MAX_PATH];
  GetSystemDirectoryW(sysDir, static_cast<UINT>(std::size(sysDir)));
  std::wstring rundll = std::wstring(sysDir) + L"\\rundll32.exe";
  std::wstring unc = uncLower;
  std::wstring cmd = L"\"" + rundll + L"\" printui.dll,PrintUIEntry " + verbGaOrGd + L" /n \"" + unc + L"\"";
  return RunProcess(L"", cmd);
}

bool RunGpUpdateComputer() {
  wchar_t sysDir[MAX_PATH];
  GetSystemDirectoryW(sysDir, static_cast<UINT>(std::size(sysDir)));
  std::wstring gp = std::wstring(sysDir) + L"\\gpupdate.exe";
  std::wstring cmd = L"\"" + gp + L"\" /target:computer /force";
  return RunProcess(L"", cmd);
}

bool RestartSpoolerService() {
  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (!scm) return false;
  SC_HANDLE svc = OpenServiceW(scm, L"Spooler", SERVICE_START | SERVICE_STOP | SERVICE_QUERY_STATUS);
  if (!svc) {
    CloseServiceHandle(scm);
    return false;
  }
  SERVICE_STATUS_PROCESS ssp{};
  DWORD bytes = 0;
  ControlService(svc, SERVICE_CONTROL_STOP, reinterpret_cast<LPSERVICE_STATUS>(&ssp));
  for (int i = 0; i < 30; ++i) {
    Sleep(200);
    if (!QueryServiceStatusEx(svc, SC_STATUS_PROCESS_INFO, reinterpret_cast<LPBYTE>(&ssp), sizeof(ssp), &bytes))
      break;
    if (ssp.dwCurrentState == SERVICE_STOPPED) break;
  }
  BOOL st = StartServiceW(svc, 0, nullptr);
  CloseServiceHandle(svc);
  CloseServiceHandle(scm);
  return st != FALSE;
}
