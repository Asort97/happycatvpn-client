#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <clocale>
#include <mbctype.h>

#include "flutter_window.h"
#include "utils.h"

namespace {
bool ContainsNonAscii(const std::wstring& value) {
  for (const wchar_t ch : value) {
    if (ch > 0x7F) {
      return true;
    }
  }
  return false;
}

std::wstring GetExecutableDirectory() {
  wchar_t buffer[MAX_PATH];
  const DWORD length = ::GetModuleFileNameW(nullptr, buffer, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return L"";
  }
  std::wstring path(buffer, length);
  const size_t last_separator = path.find_last_of(L"\\/");
  if (last_separator == std::wstring::npos) {
    return L"";
  }
  return path.substr(0, last_separator);
}

std::wstring GetExecutablePath() {
  wchar_t buffer[MAX_PATH];
  const DWORD length = ::GetModuleFileNameW(nullptr, buffer, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return L"";
  }
  return std::wstring(buffer, length);
}

void EnsureUtf8Locale() {
  std::setlocale(LC_ALL, ".UTF-8");
  _setmbcp(CP_UTF8);
}

bool MaybeRelaunchWithShortExePath(const wchar_t* command_line) {
  if (::GetEnvironmentVariableW(L"HAPPYCAT_RELAUNCHED", nullptr, 0) != 0) {
    return false;
  }

  const std::wstring exe_path = GetExecutablePath();
  if (exe_path.empty() || !ContainsNonAscii(exe_path)) {
    return false;
  }

  wchar_t short_path[MAX_PATH];
  const DWORD short_length =
      ::GetShortPathNameW(exe_path.c_str(), short_path, MAX_PATH);
  if (short_length == 0 || short_length >= MAX_PATH) {
    return false;
  }

  const std::wstring short_path_string(short_path, short_length);
  const size_t last_separator = short_path_string.find_last_of(L"\\/");
  const wchar_t* short_working_dir = nullptr;
  std::wstring short_working_dir_storage;
  if (last_separator != std::wstring::npos) {
    short_working_dir_storage = short_path_string.substr(0, last_separator);
    short_working_dir = short_working_dir_storage.c_str();
  }

  ::SetEnvironmentVariableW(L"HAPPYCAT_RELAUNCHED", L"1");

  std::wstring child_cmdline = L"\"";
  child_cmdline += short_path;
  child_cmdline += L"\"";
  if (command_line != nullptr && command_line[0] != L'\0') {
    child_cmdline += L" ";
    child_cmdline += command_line;
  }

  STARTUPINFOW si;
  ::ZeroMemory(&si, sizeof(si));
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi;
  ::ZeroMemory(&pi, sizeof(pi));

  std::wstring cmdline_mutable = child_cmdline;
  const BOOL ok = ::CreateProcessW(
      short_path,
      &cmdline_mutable[0],
      nullptr,
      nullptr,
      FALSE,
      0,
      nullptr,
      short_working_dir,
      &si,
      &pi);

  if (!ok) {
    return false;
  }

  ::CloseHandle(pi.hThread);
  ::CloseHandle(pi.hProcess);
  return true;
}

void SetSafeWorkingDirectory() {
  const std::wstring executable_dir = GetExecutableDirectory();
  if (executable_dir.empty()) {
    return;
  }

  // Some Flutter/CRT path conversions may still rely on the current ANSI code
  // page and choke on non-ASCII paths. Prefer an ASCII-only 8.3 path when
  // available.
  wchar_t short_path[MAX_PATH];
  const DWORD short_length =
      ::GetShortPathNameW(executable_dir.c_str(), short_path, MAX_PATH);
  if (short_length != 0 && short_length < MAX_PATH) {
    ::SetCurrentDirectoryW(short_path);
    return;
  }

  ::SetCurrentDirectoryW(executable_dir.c_str());
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (MaybeRelaunchWithShortExePath(command_line)) {
    return EXIT_SUCCESS;
  }

  EnsureUtf8Locale();
  SetSafeWorkingDirectory();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"happycat_vpnclient", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
