#include "json_util.hpp"
#include "string_util.hpp"
#include <cstdio>
#include <sstream>

std::string JsonEscape(const std::string& s) {
  std::string o;
  o.reserve(s.size() + 8);
  for (unsigned char c : s) {
    switch (c) {
      case '"': o += "\\\""; break;
      case '\\': o += "\\\\"; break;
      case '\b': o += "\\b"; break;
      case '\f': o += "\\f"; break;
      case '\n': o += "\\n"; break;
      case '\r': o += "\\r"; break;
      case '\t': o += "\\t"; break;
      default:
        if (c < 0x20) {
          char buf[7];
          snprintf(buf, sizeof(buf), "\\u%04x", c);
          o += buf;
        } else
          o += static_cast<char>(c);
    }
  }
  return o;
}

static void EmitJsonValue(std::ostringstream& oss, const JsonValue& v) {
  if (v.kind == JsonValue::Bool) {
    oss << (v.b ? "true" : "false");
  } else if (v.kind == JsonValue::String) {
    oss << '"' << JsonEscape(v.str) << '"';
  } else {
    oss << '[';
    for (size_t i = 0; i < v.arr.size(); ++i) {
      if (i) oss << ',';
      oss << '"' << JsonEscape(v.arr[i]) << '"';
    }
    oss << ']';
  }
}

std::string BuildStatusJson(const std::wstring& generatedAtIso, const std::wstring& state,
                            const std::wstring& stage, const std::wstring& message,
                            const JsonDataMap& data) {
  std::ostringstream oss;
  oss << '{';
  oss << "\"GeneratedAt\":\"" << JsonEscape(WideToUtf8(generatedAtIso)) << "\",";
  oss << "\"State\":\"" << JsonEscape(WideToUtf8(state)) << "\",";
  oss << "\"Stage\":\"" << JsonEscape(WideToUtf8(stage)) << "\",";
  oss << "\"Message\":\"" << JsonEscape(WideToUtf8(message)) << "\",";
  oss << "\"Data\":{";
  bool first = true;
  for (const auto& kv : data) {
    if (!first) oss << ',';
    first = false;
    oss << '"' << JsonEscape(kv.first) << "\":";
    EmitJsonValue(oss, kv.second);
  }
  oss << '}';
  oss << '}';
  return oss.str();
}
