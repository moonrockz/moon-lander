import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

// Keep the result data-only at the FFI boundary. MoonBit turns an error result
// into a raised error, rather than letting a JS exception escape its handlers.
type Reply =
  | { kind: "missing" }
  | { kind: "file"; text: string }
  | { kind: "directory"; names: string[]; kinds: string[] }
  | { kind: "error"; error: string };

// The kind of the file at a path. Tests give one that fails as a locked file does.
export type Inspect = (path: string) => { isFile(): boolean; isDirectory(): boolean };

function absent(error: unknown): boolean {
  const code = (error as NodeJS.ErrnoException).code;
  return code === "ENOENT" || code === "ENOTDIR";
}

function kind(path: string, inspect: Inspect): string {
  try {
    const stat = inspect(path);
    return stat.isFile() ? "file" : stat.isDirectory() ? "directory" : "other";
  } catch (error) {
    if (absent(error)) return "missing";
    throw error;
  }
}

// The kind of a listed entry. An entry that the system cannot inspect, such as
// a file that another process locks, is "inaccessible", so it does not stop the
// listing. The load reads it only when it is a candidate, and that read reports
// the error. An entry that no longer exists, or a link that points nowhere, is
// "missing". Only a system error, which has an errno and a syscall, makes an
// entry inaccessible; another error, such as ERR_INVALID_ARG_TYPE, passes out.
function entryKind(path: string, inspect: Inspect): string {
  try {
    return kind(path, inspect);
  } catch (error) {
    const { errno, syscall } = error as NodeJS.ErrnoException;
    if (typeof errno === "number" && typeof syscall === "string") return "inaccessible";
    throw error;
  }
}

// Follow links, as the native adapter does.
const stat: Inspect = path => statSync(path);

export function answer(path: string, listing: boolean): Reply {
  return answerWith(path, listing, stat);
}

export function answerWith(path: string, listing: boolean, inspect: Inspect): Reply {
  try {
    if (kind(path, inspect) !== (listing ? "directory" : "file")) {
      return { kind: "missing" };
    }
    if (!listing) return { kind: "file", text: readFileSync(path, "utf8") };
    const names: string[] = [];
    const kinds: string[] = [];
    for (const name of readdirSync(path).sort()) { // Includes hidden entries.
      const entry = entryKind(join(path, name), inspect);
      if (entry === "missing") continue;
      names.push(name);
      kinds.push(entry);
    }
    return { kind: "directory", names, kinds };
  } catch (error) {
    // A file can disappear between stat and read. Record the absence as well.
    if (absent(error)) return { kind: "missing" };
    const message = String(error);
    return {
      kind: "error",
      error: process.platform === "win32" ? message.replaceAll("\\", "/") : message,
    };
  }
}
