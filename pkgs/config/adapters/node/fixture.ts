// Test-only fixture setup. This entry point never enters the library bundle.
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, chmodSync, statSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";

export function tempDir(): string {
  const dir = mkdtempSync(join(tmpdir(), "lander-host-"));
  return process.platform === "win32" ? dir.replaceAll("\\", "/") : dir;
}
export function write(path: string, text: string): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, text);
}
export function removeDir(path: string): void {
  rmSync(path, { recursive: true });
}
export function mkdir(path: string, permission: number): void {
  mkdirSync(path, { mode: permission });
}
export function chmod(path: string, permission: number): void {
  chmodSync(path, permission);
}
export function symlink(target: string, path: string): void {
  symlinkSync(target, path);
}
// A stat with injected faults: a path in `locked` fails as a file that another
// process holds open fails on Windows (EBUSY), a path in `vanished` is gone, and
// a path in `broken` throws an error that is not a system error.
export function faultyStat(locked: string[], vanished: string[], broken: string[]) {
  return (path: string) => {
    const slashed = process.platform === "win32" ? path.replaceAll("\\", "/") : path;
    if (locked.includes(slashed)) {
      const error: NodeJS.ErrnoException = new Error(`EBUSY: resource busy or locked, stat '${path}'`);
      error.code = "EBUSY";
      error.errno = -4082;
      error.syscall = "stat";
      error.path = path;
      throw error;
    }
    if (broken.includes(slashed)) {
      const error: NodeJS.ErrnoException = new TypeError(`injected fault for ${path}`);
      error.code = "ERR_INVALID_ARG_TYPE";
      throw error;
    }
    return statSync(vanished.includes(slashed) ? `${path}.vanished` : path);
  };
}
