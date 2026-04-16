#pragma once
#include <map>
#include <string>
#include <vector>

std::string JsonEscape(const std::string& s);

struct JsonValue {
  enum Kind { String, Array, Bool } kind = String;
  std::string str;
  std::vector<std::string> arr;
  bool b = false;
};

using JsonDataMap = std::map<std::string, JsonValue>;

std::string BuildStatusJson(const std::wstring& generatedAtIso, const std::wstring& state,
                            const std::wstring& stage, const std::wstring& message,
                            const JsonDataMap& data);
