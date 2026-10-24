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
static int32_t moonlander_console_exit_code(int32_t kind) {
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

#ifdef _WIN32

#include <windows.h>

static volatile LONG moonlander_console_kind = 0;

static BOOL WINAPI moonlander_console_on_event(DWORD event) {
  LONG kind;
  switch (event) {
  case CTRL_C_EVENT:
    kind = 1;
    break;
  case CTRL_CLOSE_EVENT:
    kind = 2;
    break;
  case CTRL_BREAK_EVENT:
    kind = 3;
    break;
  default:
    return FALSE;
  }
  if (InterlockedCompareExchange(&moonlander_console_kind, kind, 0) != 0) {
    ExitProcess((UINT)moonlander_console_exit_code(kind));
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

#else

#include <signal.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t moonlander_console_kind = 0;

static void moonlander_console_on_signal(int sig) {
  int32_t kind = sig == SIGINT ? 1 : sig == SIGTERM ? 2 : sig == SIGQUIT ? 3 : 0;
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
