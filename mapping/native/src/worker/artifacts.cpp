#include "artifacts.hpp"
#include "../common/path_util.hpp"
#include "../common/string_util.hpp"
#include <fstream>
#include <sstream>

static std::string HtmlEncodePre(const std::string& s) {
  std::string o;
  for (unsigned char c : s) {
    if (c == '&')
      o += "&amp;";
    else if (c == '<')
      o += "&lt;";
    else if (c == '>')
      o += "&gt;";
    else
      o += static_cast<char>(c);
  }
  return o;
}

static std::string CsvEscape(const std::wstring& cell) {
  std::string u8 = WideToUtf8(cell);
  bool need = false;
  for (char c : u8) {
    if (c == '"' || c == ',' || c == '\r' || c == '\n') {
      need = true;
      break;
    }
  }
  if (!need) return u8;
  std::string o = "\"";
  for (char c : u8) {
    if (c == '"') o += "\"\"";
    else o += c;
  }
  o += '"';
  return o;
}

static std::string Bom() {
  return std::string("\xEF\xBB\xBF");
}

void WritePreflightCsv(const std::wstring& path, const std::wstring& computer, const std::wstring& tsIso,
                       const std::vector<std::wstring>& beforeUnc,
                       const std::vector<std::wstring>& desiredLower) {
  std::ostringstream oss;
  oss << Bom();
  oss << "SnapshotTime,ComputerName,Type,Target,PresentNow,InDesired,Notes\r\n";
  for (const auto& u : beforeUnc) {
    bool inDesired = false;
    for (const auto& d : desiredLower)
      if (_wcsicmp(u.c_str(), d.c_str()) == 0) inDesired = true;
    oss << CsvEscape(tsIso) << ',' << CsvEscape(computer) << ",UNC," << CsvEscape(u) << ",true,"
        << (inDesired ? "true" : "false") << ",\r\n";
  }
  for (const auto& q : desiredLower) {
    bool present = false;
    for (const auto& u : beforeUnc)
      if (_wcsicmp(u.c_str(), q.c_str()) == 0) present = true;
    if (!present) {
      oss << CsvEscape(tsIso) << ',' << CsvEscape(computer) << ",UNC," << CsvEscape(q) << ",false,true,"
          << CsvEscape(L"(planned add)") << "\r\n";
    }
  }
  WriteWholeFileUtf8(path, oss.str(), false);
}

void WriteResultsCsv(const std::wstring& path, const std::vector<ResultRow>& rows) {
  std::ostringstream oss;
  oss << Bom();
  oss << "Timestamp,ComputerName,Type,Target,Driver,Port,Status\r\n";
  for (const auto& r : rows) {
    oss << CsvEscape(r.timestamp) << ',' << CsvEscape(r.computer) << ',' << CsvEscape(r.type) << ','
        << CsvEscape(r.target) << ',' << CsvEscape(r.driver) << ',' << CsvEscape(r.port) << ','
        << CsvEscape(r.status) << "\r\n";
  }
  WriteWholeFileUtf8(path, oss.str(), false);
}

void WriteResultsHtml(const std::wstring& path, const std::wstring& title, const std::vector<ResultRow>& rows,
                      bool listOnlyMode, const std::wstring& logPathOptional) {
  std::ostringstream oss;
  oss << "<!DOCTYPE html><html><head><meta charset=\"utf-8\"/><title>" << WideToUtf8(title)
      << "</title>\n<style>body{font-family:Segoe UI,Arial;background:#101014;color:#ececf1;padding:20px}\n";
  oss << "table{border-collapse:collapse;width:100%}th,td{border:1px solid #2a2a33;padding:6px 8px;font-size:12px}\n";
  oss << "th{background:#171720}tr:nth-child(even){background:#0f0f16}</style></head><body>\n";
  oss << "<h2>" << WideToUtf8(title) << "</h2>\n";
  if (listOnlyMode)
    oss << "<h2>Current Printers (UNC + Local)</h2>\n";
  else
    oss << "<h2>Per-Target Detail</h2>\n";
  oss << "<table><tr><th>Timestamp</th><th>Type</th><th>Target</th><th>Driver</th><th>Port</th><th>Status</th></tr>\n";
  for (const auto& r : rows) {
    oss << "<tr><td>" << WideToUtf8(r.timestamp) << "</td><td>" << WideToUtf8(r.type) << "</td><td>"
        << WideToUtf8(r.target) << "</td><td>" << WideToUtf8(r.driver) << "</td><td>" << WideToUtf8(r.port)
        << "</td><td>" << WideToUtf8(r.status) << "</td></tr>\n";
  }
  oss << "</table>\n";
  if (!logPathOptional.empty() && FileExists(logPathOptional)) {
    std::ifstream in(WideToUtf8(logPathOptional), std::ios::binary);
    if (in) {
      std::string content((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
      oss << "<h2>Run Log</h2><pre>" << HtmlEncodePre(content) << "</pre>\n";
    }
  }
  oss << "</body></html>\n";
  WriteWholeFileUtf8(path, oss.str(), true);
}
