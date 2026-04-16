#pragma once
#include <string>
#include <vector>

std::wstring Utf8ToWide(const std::string& utf8);
std::string WideToUtf8(const std::wstring& w);

std::wstring Trim(const std::wstring& s);
void SplitCommaList(const std::wstring& in, std::vector<std::wstring>& out);
std::wstring ToLower(std::wstring s);

std::wstring GetEnvW(const wchar_t* name);
std::wstring LocalTimestampFolder();
std::wstring Iso8601Local();
