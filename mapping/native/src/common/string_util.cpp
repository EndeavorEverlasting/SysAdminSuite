#include "string_util.hpp"
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <chrono>
#include <ctime>
#include <cwctype>
#include <iomanip>
#include <sstream>

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return {};
  int n = MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  if (n <= 0) return {};
  std::wstring w(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), w.data(), n);
  return w;
}

std::string WideToUtf8(const std::wstring& w) {
  if (w.empty()) return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), nullptr, 0, nullptr, nullptr);
  if (n <= 0) return {};
  std::string u8(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), u8.data(), n, nullptr, nullptr);
  return u8;
}

std::wstring Trim(const std::wstring& s) {
  size_t a = 0, b = s.size();
  while (a < b && (s[a] == L' ' || s[a] == L'\t' || s[a] == L'\r' || s[a] == L'\n')) ++a;
  while (b > a && (s[b - 1] == L' ' || s[b - 1] == L'\t' || s[b - 1] == L'\r' || s[b - 1] == L'\n')) --b;
  return s.substr(a, b - a);
}

void SplitCommaList(const std::wstring& in, std::vector<std::wstring>& out) {
  std::wstring cur;
  for (wchar_t c : in) {
    if (c == L',') {
      std::wstring t = Trim(cur);
      if (!t.empty()) out.push_back(t);
      cur.clear();
    } else
      cur.push_back(c);
  }
  std::wstring t = Trim(cur);
  if (!t.empty()) out.push_back(t);
}

std::wstring ToLower(std::wstring s) {
  for (auto& c : s) c = static_cast<wchar_t>(towlower(c));
  return s;
}

std::wstring GetEnvW(const wchar_t* name) {
  wchar_t buf[32768];
  DWORD n = GetEnvironmentVariableW(name, buf, static_cast<DWORD>(std::size(buf)));
  if (n == 0 || n >= std::size(buf)) return {};
  return std::wstring(buf, n);
}

std::wstring LocalTimestampFolder() {
  SYSTEMTIME st{};
  GetLocalTime(&st);
  wchar_t buf[32];
  swprintf_s(buf, L"%04u%02u%02u-%02u%02u%02u", static_cast<unsigned>(st.wYear),
             static_cast<unsigned>(st.wMonth), static_cast<unsigned>(st.wDay),
             static_cast<unsigned>(st.wHour), static_cast<unsigned>(st.wMinute),
             static_cast<unsigned>(st.wSecond));
  return buf;
}

std::wstring Iso8601Local() {
  SYSTEMTIME st{};
  GetLocalTime(&st);
  wchar_t buf[64];
  swprintf_s(buf, L"%04u-%02u-%02uT%02u:%02u:%02u", static_cast<unsigned>(st.wYear),
             static_cast<unsigned>(st.wMonth), static_cast<unsigned>(st.wDay),
             static_cast<unsigned>(st.wHour), static_cast<unsigned>(st.wMinute),
             static_cast<unsigned>(st.wSecond));
  return buf;
}
