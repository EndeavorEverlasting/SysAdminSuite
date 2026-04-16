#include "printers.hpp"
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <Winspool.h>
#include <algorithm>

#pragma comment(lib, "Winspool.lib")

std::vector<LocalPrinterInfo> EnumLocalPrinters() {
  std::vector<LocalPrinterInfo> out;
  DWORD needed = 0, returned = 0;
  EnumPrintersW(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, nullptr, 2, nullptr, 0, &needed, &returned);
  if (needed == 0) return out;
  std::vector<BYTE> buf(needed);
  if (!EnumPrintersW(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, nullptr, 2, buf.data(), needed, &needed,
                     &returned))
    return out;
  auto* pi = reinterpret_cast<PRINTER_INFO_2W*>(buf.data());
  for (DWORD i = 0; i < returned; ++i) {
    LocalPrinterInfo lp;
    if (pi[i].pPrinterName) lp.name = pi[i].pPrinterName;
    if (pi[i].pDriverName) lp.driver = pi[i].pDriverName;
    if (pi[i].pPortName) lp.port = pi[i].pPortName;
    out.push_back(std::move(lp));
  }
  std::sort(out.begin(), out.end(), [](const LocalPrinterInfo& a, const LocalPrinterInfo& b) {
    return _wcsicmp(a.name.c_str(), b.name.c_str()) < 0;
  });
  return out;
}
