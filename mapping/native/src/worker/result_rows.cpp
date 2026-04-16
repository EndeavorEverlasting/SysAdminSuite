#include "result_rows.hpp"
#include "../common/string_util.hpp"
#include <algorithm>

static bool VecContainsI(const std::vector<std::wstring>& v, const std::wstring& x) {
  for (const auto& s : v)
    if (_wcsicmp(s.c_str(), x.c_str()) == 0) return true;
  return false;
}

static void AddUnique(std::vector<std::wstring>* u, const std::wstring& x) {
  for (const auto& s : *u)
    if (s == x) return;
  u->push_back(x);
}

std::vector<ResultRow> BuildResultRows(const std::wstring& computer, const std::wstring& timestampIso,
                                       const std::vector<std::wstring>& beforeUnc,
                                       const std::vector<std::wstring>& afterUnc,
                                       const std::vector<std::wstring>& desiredUncLower,
                                       const std::vector<std::wstring>& removeListLower, bool planOnly,
                                       bool pruneNotInList, const std::vector<LocalPrinterInfo>& afterLocal) {
  std::vector<std::wstring> universe;
  for (const auto& s : beforeUnc) AddUnique(&universe, s);
  for (const auto& s : afterUnc) AddUnique(&universe, s);
  for (const auto& s : desiredUncLower) AddUnique(&universe, s);
  for (const auto& s : removeListLower) AddUnique(&universe, s);
  std::sort(universe.begin(), universe.end());

  std::vector<ResultRow> rows;
  for (const auto& u : universe) {
    ResultRow r;
    r.timestamp = timestampIso;
    r.computer = computer;
    r.type = L"UNC";
    r.target = u;
    r.driver.clear();
    r.port.clear();

    bool inBefore = VecContainsI(beforeUnc, u);
    bool inAfter = VecContainsI(afterUnc, u);
    bool inDesired = VecContainsI(desiredUncLower, u);
    bool inRemove = VecContainsI(removeListLower, u);

    if (planOnly) {
      if (inDesired && !inBefore)
        r.status = L"PlannedAdd";
      else if (inRemove || (pruneNotInList && !desiredUncLower.empty() && !inDesired && inBefore))
        r.status = L"PlannedRemove";
      else if (inAfter)
        r.status = L"PresentAfter";
      else if (inBefore)
        r.status = L"GoneAfter";
      else
        r.status = L"NotPresent";
    } else {
      if (inAfter && !inBefore)
        r.status = L"AddedNow";
      else if (!inAfter && inBefore)
        r.status = L"RemovedNow";
      else if (inAfter)
        r.status = L"PresentAfter";
      else
        r.status = L"NotPresent";
    }
    rows.push_back(std::move(r));
  }

  for (const auto& p : afterLocal) {
    ResultRow r;
    r.timestamp = timestampIso;
    r.computer = computer;
    r.type = L"LOCAL";
    r.target = p.name;
    r.driver = p.driver;
    r.port = p.port;
    r.status = L"PresentAfter";
    rows.push_back(std::move(r));
  }

  return rows;
}
