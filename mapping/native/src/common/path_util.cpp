#include "path_util.hpp"
#define WIN32_LEAN_AND_MEAN
#include <Shlwapi.h>
#include <Windows.h>
#include <fstream>

#pragma comment(lib, "Shlwapi.lib")

std::wstring JoinPath(const std::wstring& a, const std::wstring& b) {
  if (a.empty()) return b;
  if (a.back() == L'\\' || a.back() == L'/') return a + b;
  return a + L"\\" + b;
}

bool EnsureDirectory(const std::wstring& path) {
  DWORD attr = GetFileAttributesW(path.c_str());
  if (attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY)) return true;
  return CreateDirectoryW(path.c_str(), nullptr) != FALSE ||
         GetLastError() == ERROR_ALREADY_EXISTS;
}

bool EnsureDirectoryRecursive(const std::wstring& path) {
  if (path.empty()) return false;
  DWORD attr = GetFileAttributesW(path.c_str());
  if (attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY)) return true;
  int e = static_cast<int>(SHCreateDirectoryExW(nullptr, path.c_str(), nullptr));
  return e == ERROR_SUCCESS || e == ERROR_ALREADY_EXISTS;
}

bool WriteWholeFileUtf8(const std::wstring& path, const std::string& utf8Body, bool bom) {
  HANDLE h = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (h == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  bool ok = true;
  if (bom) {
    const unsigned char bomBytes[] = {0xEF, 0xBB, 0xBF};
    ok = WriteFile(h, bomBytes, 3, &written, nullptr) != FALSE;
  }
  if (ok && !utf8Body.empty()) {
    ok = WriteFile(h, utf8Body.data(), static_cast<DWORD>(utf8Body.size()), &written, nullptr) != FALSE;
  }
  CloseHandle(h);
  return ok;
}

bool AppendLogLineUtf8(const std::wstring& path, const std::string& line) {
  HANDLE h = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ, nullptr, OPEN_ALWAYS,
                         FILE_ATTRIBUTE_NORMAL, nullptr);
  if (h == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  std::string chunk = line;
  if (chunk.empty() || chunk.back() != '\n') chunk.push_back('\n');
  BOOL ok = WriteFile(h, chunk.data(), static_cast<DWORD>(chunk.size()), &written, nullptr);
  CloseHandle(h);
  return ok != FALSE;
}

bool FileExists(const std::wstring& path) {
  DWORD a = GetFileAttributesW(path.c_str());
  return a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY);
}
