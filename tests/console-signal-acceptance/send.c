// Test-only sender: deliver a stop signal to a child process.
// Kinds as in hosting/console: 1 Interrupt, 2 Terminate, 3 Quit.

#include <stdint.h>

#ifdef _WIN32

#include <windows.h>

// The child starts in its own process group (moonbitlang/async spawns it with
// CREATE_NEW_PROCESS_GROUP), so the group id is its pid. Windows sends only
// CTRL_BREAK_EVENT to one process group: CTRL_C_EVENT goes to every process on
// the console, and CTRL_CLOSE_EVENT cannot be sent by a program.
int32_t lander_test_send_signal(int32_t pid, int32_t kind) {
  if (kind != 3) {
    return -2;
  }
  return GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, (DWORD)pid)
           ? 0
           : (int32_t)GetLastError();
}

#else

#include <signal.h>
#include <sys/types.h>

int32_t lander_test_send_signal(int32_t pid, int32_t kind) {
  int sig = kind == 1 ? SIGINT : kind == 2 ? SIGTERM : kind == 3 ? SIGQUIT : 0;
  if (sig == 0) {
    return -2;
  }
  return kill((pid_t)pid, sig) == 0 ? 0 : -1;
}

#endif
