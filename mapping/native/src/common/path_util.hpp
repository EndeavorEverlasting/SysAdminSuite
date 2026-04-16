#pragma once
#include <string>

std::wstring JoinPath(const std::wstring& a, const std::wstring& b);
bool EnsureDirectory(const std::wstring& path);
bool EnsureDirectoryRecursive(const std::wstring& path);
bool WriteWholeFileUtf8(const std::wstring& path, const std::string& utf8Body, bool bom = false);
bool AppendLogLineUtf8(const std::wstring& path, const std::string& line);
bool FileExists(const std::wstring& path);
