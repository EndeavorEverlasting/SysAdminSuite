#include "registry_unc.hpp"
#include "../common/string_util.hpp"
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <algorithm>

#pragma comment(lib, "Advapi32.lib")

static std::wstring RegReadSz(HKEY key, const wchar_t* value) {
  wchar_t buf[4096];
  DWORD sz = sizeof(buf);
  DWORD type = 0;
  LONG e = RegQueryValueExW(key, value, nullptr, &type, reinterpret_cast<LPBYTE>(buf), &sz);
  if (e != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ)) return {};
  return std::wstring(buf, sz / sizeof(wchar_t) - 1);
}

std::vector<std::wstring> GetGlobalUncConnectionsLowercase() {
  std::vector<std::wstring> out;
  const wchar_t* sub =
      L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Print\\Connections";
  HKEY hKey = nullptr;
  if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, sub, 0, KEY_READ | KEY_WOW64_64KEY, &hKey) != ERROR_SUCCESS) {
    return out;
  }
  wchar_t name[256];
  DWORD idx = 0;
  while (true) {
    DWORD nameLen = static_cast<DWORD>(std::size(name));
    FILETIME ft{};
    LONG e = RegEnumKeyExW(hKey, idx++, name, &nameLen, nullptr, nullptr, nullptr, &ft);
    if (e == ERROR_NO_MORE_ITEMS) break;
    if (e != ERROR_SUCCESS) continue;
    HKEY hSub = nullptr;
    if (RegOpenKeyExW(hKey, name, 0, KEY_READ, &hSub) != ERROR_SUCCESS) continue;
    std::wstring server = RegReadSz(hSub, L"Server");
    std::wstring printer = RegReadSz(hSub, L"Printer");
    RegCloseKey(hSub);
    if (server.empty() || printer.empty()) continue;
    std::wstring unc = L"\\\\" + server + L"\\" + printer;
    out.push_back(ToLower(std::move(unc)));
  }
  RegCloseKey(hKey);
  std::sort(out.begin(), out.end());
  out.erase(std::unique(out.begin(), out.end()), out.end());
  return out;
}
