#include "common/json_util.hpp"
#include "common/string_util.hpp"
#include "worker/result_rows.hpp"
#include <gtest/gtest.h>
#include <string>

TEST(JsonEscape, EscapesQuotesAndBackslash) {
  EXPECT_EQ(JsonEscape(R"(say "hi")"), R"(say \"hi\")");
  EXPECT_EQ(JsonEscape(R"(a\b)"), R"(a\\b)");
}

TEST(JsonEscape, EscapesControlChars) {
  EXPECT_EQ(JsonEscape(std::string("a\nb")), "a\\nb");
  EXPECT_EQ(JsonEscape(std::string("a\tb")), "a\\tb");
}

TEST(BuildStatusJson, ContainsCoreFieldsAndBool) {
  JsonDataMap data;
  JsonValue v;
  v.kind = JsonValue::String;
  v.str = "PC01";
  data["ComputerName"] = v;
  JsonValue flag;
  flag.kind = JsonValue::Bool;
  flag.b = true;
  data["ListOnly"] = flag;

  std::string json = BuildStatusJson(L"2026-01-15T10:00:00", L"Running", L"Startup", L"ok", data);
  EXPECT_NE(json.find("\"State\":\"Running\""), std::string::npos);
  EXPECT_NE(json.find("\"ListOnly\":true"), std::string::npos);
  EXPECT_NE(json.find("\"ComputerName\":\"PC01\""), std::string::npos);
}

TEST(StringUtil, TrimWhitespace) {
  EXPECT_EQ(Trim(L"  x  "), L"x");
  EXPECT_EQ(Trim(L""), L"");
}

TEST(StringUtil, SplitCommaList) {
  std::vector<std::wstring> out;
  SplitCommaList(L"a, b ,c", out);
  ASSERT_EQ(out.size(), 3u);
  EXPECT_EQ(out[0], L"a");
  EXPECT_EQ(out[1], L"b");
  EXPECT_EQ(out[2], L"c");
}

TEST(StringUtil, ToLower) {
  EXPECT_EQ(ToLower(L"AbC"), L"abc");
}

TEST(BuildResultRows, PlanOnlyPlannedAdd) {
  std::vector<std::wstring> before = {L"\\\\srv\\old"};
  std::vector<std::wstring> after = {L"\\\\srv\\old"};
  std::vector<std::wstring> desired = {L"\\\\srv\\new"};
  std::vector<std::wstring> remove;
  std::vector<LocalPrinterInfo> locals;

  auto rows = BuildResultRows(L"HOST", L"T", before, after, desired, remove, true, false, locals);
  bool found = false;
  for (const auto& r : rows) {
    if (r.type == L"UNC" && r.target == L"\\\\srv\\new" && r.status == L"PlannedAdd") found = true;
  }
  EXPECT_TRUE(found);
}

TEST(BuildResultRows, AddedNowWhenNotPlanOnly) {
  std::vector<std::wstring> before = {L"\\\\srv\\a"};
  std::vector<std::wstring> after = {L"\\\\srv\\a", L"\\\\srv\\b"};
  std::vector<std::wstring> desired = {L"\\\\srv\\b"};
  std::vector<std::wstring> remove;
  std::vector<LocalPrinterInfo> locals;

  auto rows = BuildResultRows(L"HOST", L"T", before, after, desired, remove, false, false, locals);
  bool found = false;
  for (const auto& r : rows) {
    if (r.target == L"\\\\srv\\b" && r.status == L"AddedNow") found = true;
  }
  EXPECT_TRUE(found);
}

TEST(BuildResultRows, LocalPrinterPresentAfter) {
  std::vector<std::wstring> before, after, desired, remove;
  LocalPrinterInfo lp;
  lp.name = L"PDF";
  lp.driver = L"drv";
  lp.port = L"PORT1";
  std::vector<LocalPrinterInfo> locals = {lp};

  auto rows = BuildResultRows(L"H", L"T", before, after, desired, remove, false, false, locals);
  ASSERT_FALSE(rows.empty());
  const auto& last = rows.back();
  EXPECT_EQ(last.type, L"LOCAL");
  EXPECT_EQ(last.target, L"PDF");
  EXPECT_EQ(last.status, L"PresentAfter");
}
