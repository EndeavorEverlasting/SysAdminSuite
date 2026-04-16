#pragma once
#include "printers.hpp"
#include "result_rows.hpp"
#include <string>
#include <vector>

void WritePreflightCsv(const std::wstring& path, const std::wstring& computer, const std::wstring& tsIso,
                       const std::vector<std::wstring>& beforeUnc,
                       const std::vector<std::wstring>& desiredLower);

void WriteResultsCsv(const std::wstring& path, const std::vector<ResultRow>& rows);

void WriteResultsHtml(const std::wstring& path, const std::wstring& title, const std::vector<ResultRow>& rows,
                      bool listOnlyMode, const std::wstring& logPathOptional);
