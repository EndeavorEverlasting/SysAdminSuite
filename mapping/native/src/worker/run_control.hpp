#pragma once
#include "../common/json_util.hpp"
#include <string>

bool IsStopRequested(const std::wstring& stopSignalPath, bool alreadyRequested);

void ExportWorkerStatus(const std::wstring& statusPath, const std::wstring& state, const std::wstring& stage,
                        const std::wstring& message, const JsonDataMap& data);
