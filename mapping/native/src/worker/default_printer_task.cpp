#include "default_printer_task.hpp"
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <comdef.h>
#include <taskschd.h>

#pragma comment(lib, "taskschd.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")

bool RegisterSetDefaultPrinterOnce(const std::wstring& uncQueueLower) {
  HRESULT co = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  bool didCoInit = (co == S_OK);
  if (FAILED(co) && co != RPC_E_CHANGED_MODE) return false;

  ITaskService* service = nullptr;
  HRESULT hr =
      CoCreateInstance(CLSID_TaskScheduler, nullptr, CLSCTX_INPROC_SERVER, IID_ITaskService, (void**)&service);
  if (FAILED(hr) || !service) {
    if (didCoInit) CoUninitialize();
    return false;
  }
  hr = service->Connect(_variant_t(), _variant_t(), _variant_t(), _variant_t());
  if (FAILED(hr)) {
    service->Release();
    if (didCoInit) CoUninitialize();
    return false;
  }

  ITaskFolder* root = nullptr;
  hr = service->GetFolder(_bstr_t(L"\\"), &root);
  if (FAILED(hr) || !root) {
    service->Release();
    if (didCoInit) CoUninitialize();
    return false;
  }
  root->DeleteTask(_bstr_t(L"SetDefaultPrinterOnce"), 0);

  ITaskDefinition* task = nullptr;
  hr = service->NewTask(0, &task);
  if (FAILED(hr) || !task) {
    root->Release();
    service->Release();
    if (didCoInit) CoUninitialize();
    return false;
  }

  IPrincipal* principal = nullptr;
  if (SUCCEEDED(task->get_Principal(&principal)) && principal) {
    principal->put_UserId(_bstr_t(L"BUILTIN\\Users"));
    principal->put_LogonType(TASK_LOGON_GROUP);
    principal->put_RunLevel(TASK_RUNLEVEL_HIGHEST);
    principal->Release();
  }

  ITaskSettings* settings = nullptr;
  if (SUCCEEDED(task->get_Settings(&settings)) && settings) {
    settings->put_DisallowStartIfOnBatteries(VARIANT_FALSE);
    settings->put_StopIfGoingOnBatteries(VARIANT_FALSE);
    settings->Release();
  }

  ITriggerCollection* triggers = nullptr;
  hr = task->get_Triggers(&triggers);
  if (SUCCEEDED(hr) && triggers) {
    ITrigger* trig = nullptr;
    if (SUCCEEDED(triggers->Create(TASK_TRIGGER_LOGON, &trig)) && trig) trig->Release();
    triggers->Release();
  }

  IActionCollection* actions = nullptr;
  hr = task->get_Actions(&actions);
  if (FAILED(hr) || !actions) {
    task->Release();
    root->Release();
    service->Release();
    if (didCoInit) CoUninitialize();
    return false;
  }

  IAction* action = nullptr;
  hr = actions->Create(TASK_ACTION_EXEC, &action);
  actions->Release();
  if (FAILED(hr) || !action) {
    task->Release();
    root->Release();
    service->Release();
    if (didCoInit) CoUninitialize();
    return false;
  }

  IExecAction* exec = nullptr;
  hr = action->QueryInterface(__uuidof(IExecAction), reinterpret_cast<void**>(&exec));
  action->Release();
  if (FAILED(hr) || !exec) {
    task->Release();
    root->Release();
    service->Release();
    if (didCoInit) CoUninitialize();
    return false;
  }

  wchar_t sysDir[MAX_PATH];
  GetSystemDirectoryW(sysDir, static_cast<UINT>(std::size(sysDir)));
  std::wstring cmdExe = std::wstring(sysDir) + L"\\cmd.exe";
  std::wstring rd = std::wstring(sysDir) + L"\\rundll32.exe";
  std::wstring inner = L"\"" + rd + L"\" printui.dll,PrintUIEntry /in /n \"" + uncQueueLower + L"\" & \"" + rd +
                       L"\" printui.dll,PrintUIEntry /y /n \"" + uncQueueLower + L"\"";
  std::wstring args = L"/d /s /c \"" + inner + L"\"";

  exec->put_Path(_bstr_t(cmdExe.c_str()));
  exec->put_Arguments(_bstr_t(args.c_str()));
  exec->Release();

  IRegisteredTask* registered = nullptr;
  hr = root->RegisterTaskDefinition(_bstr_t(L"SetDefaultPrinterOnce"), task, TASK_CREATE_OR_UPDATE,
                                    _variant_t(L"BUILTIN\\Users"), _variant_t(), TASK_LOGON_GROUP,
                                    _variant_t(L""), &registered);
  if (registered) registered->Release();
  task->Release();
  root->Release();
  service->Release();
  if (didCoInit) CoUninitialize();
  return SUCCEEDED(hr);
}
