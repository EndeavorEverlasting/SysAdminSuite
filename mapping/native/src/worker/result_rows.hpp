#pragma once
#include "printers.hpp"
#include <string>
#include <vector>

struct ResultRow {
  std::wstring timestamp;
  std::wstring computer;
  std::wstring type;  // UNC or LOCAL
  std::wstring target;
  std::wstring driver;
  std::wstring port;
  std::wstring status;
};

std::vector<ResultRow> BuildResultRows(
    const std::wstring& computer, const std::wstring& timestampIso,
    const std::vector<std::wstring>& beforeUnc, const std::vector<std::wstring>& afterUnc,
    const std::vector<std::wstring>& desiredUncLower, const std::vector<std::wstring>& removeListLower,
    bool planOnly, bool pruneNotInList, const std::vector<LocalPrinterInfo>& afterLocal);
