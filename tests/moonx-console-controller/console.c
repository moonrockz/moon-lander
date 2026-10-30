// Test-only Windows console topology and event delivery. No production launcher
// or payload uses this code. MoonBit async owns ordinary I/O and process waits.
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif
#include "moonbit.h"
#include <stdint.h>

#ifdef _WIN32
#include <windows.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

static PROCESS_INFORMATION owned_process;

static WCHAR *copy_text(moonbit_string_t text, int32_t length) {
  WCHAR *result = (WCHAR *)calloc((size_t)length + 1, sizeof(WCHAR));
  if (result) memcpy(result, text, (size_t)length * sizeof(WCHAR));
  return result;
}

// Standard Windows argv quoting, including trailing backslashes before a quote.
static WCHAR *quoted(WCHAR *out, const WCHAR *text, int32_t length) {
  *out++ = L'"';
  int32_t slashes = 0;
  for (int32_t i = 0; i < length; i++) {
    WCHAR c = text[i];
    if (c == L'\\') { slashes++; continue; }
    int32_t count = c == L'"' ? slashes * 2 + 1 : slashes;
    while (count-- > 0) *out++ = L'\\';
    *out++ = c;
    slashes = 0;
  }
  while (slashes-- > 0) { *out++ = L'\\'; *out++ = L'\\'; }
  *out++ = L'"';
  return out;
}

int32_t lander_moonx_console_start(
  moonbit_string_t runner, int32_t runner_len,
  moonbit_string_t wasm, int32_t wasm_len,
  moonbit_string_t node, int32_t node_len,
  moonbit_string_t owner, int32_t owner_len,
  int32_t mode
) {
  int32_t baseline = mode & 1;
  int32_t grouped = mode & 2;
  int32_t payload = mode & 4;
  WCHAR *exe = copy_text(baseline ? node : runner, baseline ? node_len : runner_len);
  size_t capacity = ((size_t)runner_len + wasm_len + node_len + owner_len) * 2 + 64;
  WCHAR *command = (WCHAR *)calloc(capacity, sizeof(WCHAR));
  if (!exe || !command) { free(exe); free(command); SetLastError(ERROR_NOT_ENOUGH_MEMORY); return 0; }
  WCHAR *end = quoted(command, exe, baseline ? node_len : runner_len);
  if (!baseline) {
    *end++ = L' ';
    end = quoted(end, (const WCHAR *)wasm, wasm_len);
    if (payload) {
      const WCHAR *arguments = L" -- --payload --ignore-break";
      size_t length = wcslen(arguments);
      memcpy(end, arguments, length * sizeof(WCHAR)); end += length;
    } else {
      memcpy(end, L" -- ", 4 * sizeof(WCHAR)); end += 4;
      end = quoted(end, (const WCHAR *)node, node_len);
    }
  }
  if (!payload) {
    *end++ = L' ';
    end = quoted(end, (const WCHAR *)owner, owner_len);
  }
  *end = 0;

  HANDLE handles[3] = {NULL, NULL, NULL};
  DWORD ids[3] = {STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE};
  HANDLE original[3] = {GetStdHandle(STD_INPUT_HANDLE), GetStdHandle(STD_OUTPUT_HANDLE), GetStdHandle(STD_ERROR_HANDLE)};
  DWORD error = ERROR_SUCCESS;
  // The async test runner creates a process group that can inherit an ignored
  // Ctrl-C attribute. Start from a fresh ordinary controller console, restore
  // its redirected pipes, and clear that inherited attribute before creating
  // the target, which inherits this isolated console. No stock executable is
  // patched. Only targeted Ctrl-Break cases create a new process group.
  FreeConsole();
  if (!AllocConsole()) { error = GetLastError(); goto done; }
  for (int i = 0; i < 3; i++) SetStdHandle(ids[i], original[i]);
  if (!SetConsoleCtrlHandler(NULL, FALSE)) { error = GetLastError(); goto done; }
  for (int i = 0; i < 3; i++) {
    if (!DuplicateHandle(GetCurrentProcess(), GetStdHandle(ids[i]), GetCurrentProcess(),
                         &handles[i], 0, TRUE, DUPLICATE_SAME_ACCESS)) {
      error = GetLastError(); goto done;
    }
  }
  SIZE_T bytes = 0;
  InitializeProcThreadAttributeList(NULL, 1, 0, &bytes);
  LPPROC_THREAD_ATTRIBUTE_LIST attributes = (LPPROC_THREAD_ATTRIBUTE_LIST)HeapAlloc(GetProcessHeap(), 0, bytes);
  if (!attributes) { error = ERROR_NOT_ENOUGH_MEMORY; goto done; }
  if (!InitializeProcThreadAttributeList(attributes, 1, 0, &bytes)) {
    error = GetLastError(); HeapFree(GetProcessHeap(), 0, attributes); goto done;
  }
  if (!UpdateProcThreadAttribute(attributes, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                                 handles, sizeof(handles), NULL, NULL)) {
    error = GetLastError();
  } else {
    STARTUPINFOEXW startup;
    ZeroMemory(&startup, sizeof(startup));
    startup.StartupInfo.cb = sizeof(startup);
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    startup.StartupInfo.wShowWindow = SW_HIDE;
    startup.StartupInfo.hStdInput = handles[0];
    startup.StartupInfo.hStdOutput = handles[1];
    startup.StartupInfo.hStdError = handles[2];
    startup.lpAttributeList = attributes;
    ZeroMemory(&owned_process, sizeof(owned_process));
    DWORD flags = CREATE_UNICODE_ENVIRONMENT |
                  EXTENDED_STARTUPINFO_PRESENT | CREATE_SUSPENDED;
    if (grouped) flags |= CREATE_NEW_PROCESS_GROUP;
    if (!CreateProcessW(exe, command, NULL, NULL, TRUE, flags, NULL, NULL,
                        &startup.StartupInfo, &owned_process)) error = GetLastError();
  }
  DeleteProcThreadAttributeList(attributes);
  HeapFree(GetProcessHeap(), 0, attributes);
done:
  FreeConsole();
  for (int i = 0; i < 3; i++) SetStdHandle(ids[i], original[i]);
  for (int i = 0; i < 3; i++) if (handles[i]) CloseHandle(handles[i]);
  free(exe); free(command);
  SetLastError(error);
  return error ? 0 : (int32_t)owned_process.dwProcessId;
}

int32_t lander_moonx_console_resume(void) {
  return ResumeThread(owned_process.hThread) == (DWORD)-1 ? (int32_t)GetLastError() : 0;
}

int32_t lander_moonx_console_event(int32_t kind) {
  FreeConsole();
  if (!AttachConsole(owned_process.dwProcessId)) return (int32_t)GetLastError();
  // Ignore the broadcast only in this controller. The independently created
  // target console process keeps its ordinary Ctrl-C behavior.
  SetConsoleCtrlHandler(NULL, TRUE);
  BOOL ok = GenerateConsoleCtrlEvent(kind == 0 ? CTRL_C_EVENT : CTRL_BREAK_EVENT,
                                    kind == 0 ? 0 : owned_process.dwProcessId);
  DWORD error = ok ? ERROR_SUCCESS : GetLastError();
  FreeConsole();
  SetConsoleCtrlHandler(NULL, FALSE);
  return (int32_t)error;
}

int32_t lander_moonx_console_error(void) { return (int32_t)GetLastError(); }

int32_t lander_moonx_process_running(int32_t pid) {
  HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, (DWORD)pid);
  if (!process) return GetLastError() == ERROR_INVALID_PARAMETER ? 0 : -(int32_t)GetLastError();
  DWORD state = WaitForSingleObject(process, 0);
  CloseHandle(process);
  return state == WAIT_OBJECT_0 ? 0 : state == WAIT_TIMEOUT ? 1 : -1;
}

void lander_moonx_console_close(void) {
  if (owned_process.hProcess) {
    // Emergency fixture cleanup only. Successful proof waited and checked the
    // real owned parent and Node child before reaching this cleanup path.
    if (WaitForSingleObject(owned_process.hProcess, 0) == WAIT_TIMEOUT)
      TerminateProcess(owned_process.hProcess, 1);
    CloseHandle(owned_process.hProcess);
    CloseHandle(owned_process.hThread);
    ZeroMemory(&owned_process, sizeof(owned_process));
  }
}
#else
int32_t lander_moonx_console_start(moonbit_string_t a, int32_t al, moonbit_string_t b, int32_t bl,
  moonbit_string_t c, int32_t cl, moonbit_string_t d, int32_t dl, int32_t baseline) { return 0; }
int32_t lander_moonx_console_resume(void) { return -1; }
int32_t lander_moonx_console_event(int32_t kind) { return -1; }
int32_t lander_moonx_console_error(void) { return -1; }
int32_t lander_moonx_process_running(int32_t pid) { return -1; }
void lander_moonx_console_close(void) {}
#endif
