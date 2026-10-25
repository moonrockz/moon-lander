// Native signal stub of the console driver (openspec add-host-lifecycle, D7).
//
// The first SIGINT, SIGTERM or SIGQUIT (CTRL_C_EVENT, CTRL_CLOSE_EVENT or
// CTRL_BREAK_EVENT on Windows) stores which signal arrived. A second one ends
// the process at once, inside the handler, with the exit code of the second
// signal, so it works while the program runs code that never yields. The
// handler does only async-signal-safe work.

#include <stdint.h>

// Signal kinds, shared with console.mbt: 0 none, 1 Interrupt, 2 Terminate,
// 3 Quit.
int32_t moonlander_console_exit_code(int32_t kind) {
  switch (kind) {
  case 1:
    return 130;
  case 2:
    return 143;
  case 3:
    return 131;
  default:
    return 1;
  }
}

// The Windows console event numbers. They are fixed by the Windows API, so the
// mapping below is the same function on every platform, and its unit test runs
// on every platform.
#define MOONLANDER_CTRL_C_EVENT 0
#define MOONLANDER_CTRL_BREAK_EVENT 1
#define MOONLANDER_CTRL_CLOSE_EVENT 2

// The kind of a Windows console event, or 0 for an event that the driver does
// not handle.
int32_t moonlander_console_kind_of_event(int32_t event) {
  switch (event) {
  case MOONLANDER_CTRL_C_EVENT:
    return 1;
  case MOONLANDER_CTRL_CLOSE_EVENT:
    return 2;
  case MOONLANDER_CTRL_BREAK_EVENT:
    return 3;
  default:
    return 0;
  }
}

#ifdef _WIN32

#include <windows.h>

// The build fails if the Windows API numbers differ from the numbers above.
typedef char moonlander_console_event_numbers[
    (CTRL_C_EVENT == MOONLANDER_CTRL_C_EVENT &&
     CTRL_BREAK_EVENT == MOONLANDER_CTRL_BREAK_EVENT &&
     CTRL_CLOSE_EVENT == MOONLANDER_CTRL_CLOSE_EVENT) ? 1 : -1];

static volatile LONG moonlander_console_kind = 0;

static BOOL WINAPI moonlander_console_on_event(DWORD event) {
  LONG kind = moonlander_console_kind_of_event((int32_t)event);
  if (kind == 0) {
    return FALSE;
  }
  if (InterlockedCompareExchange(&moonlander_console_kind, kind, 0) != 0) {
    // As _exit on POSIX: no DLL detach and no C runtime cleanup, which could
    // wait for a lock that the main thread holds.
    TerminateProcess(GetCurrentProcess(), (UINT)moonlander_console_exit_code(kind));
  }
  if (event == CTRL_CLOSE_EVENT) {
    // Windows ends the process when this handler returns. Wait, so the stop
    // phase can run until the process exits or the system time limit ends.
    Sleep(INFINITE);
  }
  return TRUE;
}

int32_t moonlander_console_install(void) {
  // A process that starts in a new process group ignores CTRL_C_EVENT until it
  // turns normal processing back on.
  SetConsoleCtrlHandler(NULL, FALSE);
  return SetConsoleCtrlHandler(moonlander_console_on_event, TRUE) ? 0 : -1;
}

int32_t moonlander_console_signal_kind(void) {
  return (int32_t)InterlockedCompareExchange(&moonlander_console_kind, 0, 0);
}

// The POSIX signal numbers are not used on Windows.
int32_t moonlander_console_kind_of_signal(int32_t sig) {
  (void)sig;
  return 0;
}

#else

#include <signal.h>
#include <string.h>
#include <unistd.h>

// The kind of a POSIX signal, or 0 for a signal that the driver does not
// handle.
int32_t moonlander_console_kind_of_signal(int32_t sig) {
  return sig == SIGINT ? 1 : sig == SIGTERM ? 2 : sig == SIGQUIT ? 3 : 0;
}

static volatile sig_atomic_t moonlander_console_kind = 0;

static void moonlander_console_on_signal(int sig) {
  int32_t kind = moonlander_console_kind_of_signal(sig);
  if (kind == 0) {
    return;
  }
  if (moonlander_console_kind != 0) {
    _exit(moonlander_console_exit_code(kind));
  }
  moonlander_console_kind = kind;
}

int32_t moonlander_console_install(void) {
  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = moonlander_console_on_signal;
  action.sa_flags = SA_RESTART;
  sigemptyset(&action.sa_mask);
  sigaddset(&action.sa_mask, SIGINT);
  sigaddset(&action.sa_mask, SIGTERM);
  sigaddset(&action.sa_mask, SIGQUIT);
  if (sigaction(SIGINT, &action, NULL) != 0 ||
      sigaction(SIGTERM, &action, NULL) != 0 ||
      sigaction(SIGQUIT, &action, NULL) != 0) {
    return -1;
  }
  return 0;
}

int32_t moonlander_console_signal_kind(void) {
  return (int32_t)moonlander_console_kind;
}

#endif
