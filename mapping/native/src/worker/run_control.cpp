#include "run_control.hpp"
#include "../common/path_util.hpp"
#include "../common/string_util.hpp"
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <fstream>

bool IsStopRequested(const std::wstring& stopSignalPath, bool alreadyRequested) {
  if (alreadyRequested) return true;
  if (stopSignalPath.empty() || !FileExists(stopSignalPath)) return false;
  return true;
}

void ExportWorkerStatus(const std::wstring& statusPath, const std::wstring& state, const std::wstring& stage,
                        const std::wstring& message, const JsonDataMap& data) {
  if (statusPath.empty()) return;
  std::wstring parent = statusPath;
  size_t slash = parent.find_last_of(L"\\/");
  if (slash != std::wstring::npos) {
    parent = parent.substr(0, slash);
    EnsureDirectory(parent);
  }
  std::wstring gen = Iso8601Local();
  std::string json = BuildStatusJson(gen, state, stage, message, data);
  WriteWholeFileUtf8(statusPath, json, true);
}
