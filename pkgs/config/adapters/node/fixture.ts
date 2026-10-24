// Test-only fixture setup. This entry point never enters the library bundle.
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, chmodSync } from "node:fs";
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
