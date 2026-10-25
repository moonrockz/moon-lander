// Signal listeners of the js console driver (openspec add-host-lifecycle, D7).
// Only node:* imports. scripts/build-node-adapter.mbtx bundles this entry point
// into pkgs/hosting/console/node.generated.js.mbt.
import process from "node:process";

// Signal kinds, shared with console.mbt: 0 none, 1 Interrupt, 2 Terminate,
// 3 Quit.
type Kind = 1 | 2 | 3;

// Node.js gives the Windows console events as SIGINT (Ctrl-C), SIGBREAK
// (Ctrl-Break) and SIGHUP (console close).
const posixSignals: ReadonlyArray<[NodeJS.Signals, Kind]> = [
  ["SIGINT", 1],
  ["SIGTERM", 2],
  ["SIGQUIT", 3],
];
const windowsSignals: ReadonlyArray<[NodeJS.Signals, Kind]> = [
  ["SIGINT", 1],
  ["SIGHUP", 2],
  ["SIGBREAK", 3],
];

const exitCodes: Record<Kind, number> = { 1: 130, 2: 143, 3: 131 };

export interface SignalListeners {
  // The kind of the first signal, or 0 before a signal.
  kind(): number;
  // Remove the listeners. Later signals get the default Node.js behavior.
  remove(): void;
}

// Install one listener for each handled signal of this platform. The first
// signal records its kind. A second signal ends the process at once with the
// exit code of the second signal.
export function installSignals(): SignalListeners {
  let first = 0;
  const table = process.platform === "win32" ? windowsSignals : posixSignals;
  const listeners = table.map(([name, kind]): [NodeJS.Signals, () => void] => {
    const listener = () => {
      if (first !== 0) process.exit(exitCodes[kind]);
      first = kind;
    };
    process.on(name, listener);
    return [name, listener];
  });
  return {
    kind: () => first,
    remove() {
      for (const [name, listener] of listeners) process.off(name, listener);
    },
  };
}

// Set the exit code of a graceful end. Node.js exits with it when the event loop
// is empty, after it writes the output that is still in a pipe.
export function setExitCode(code: number): void {
  process.exitCode = code;
}
