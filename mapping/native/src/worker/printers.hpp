#pragma once
#include <string>
#include <vector>

struct LocalPrinterInfo {
  std::wstring name;
  std::wstring driver;
  std::wstring port;
};

std::vector<LocalPrinterInfo> EnumLocalPrinters();
