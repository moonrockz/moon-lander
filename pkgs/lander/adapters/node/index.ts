import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

// Keep the result data-only at the FFI boundary. MoonBit turns an error result
// into a raised error, rather than letting a JS exception escape its handlers.
type Reply = {
  kind: "missing" | "file" | "directory" | "error";
  text?: string;
  names?: string[];
  kinds?: string[];
  error?: string;
};

function absent(error: unknown): boolean {
  const code = (error as NodeJS.ErrnoException).code;
  return code === "ENOENT" || code === "ENOTDIR";
}

function kind(path: string): string {
  try {
    const stat = statSync(path); // Follow links, as the native adapter does.
    return stat.isFile() ? "file" : stat.isDirectory() ? "directory" : "other";
  } catch (error) {
    if (absent(error)) return "missing";
    throw error;
  }
}

export function answer(path: string, listing: boolean): Reply {
  try {
    if (kind(path) !== (listing ? "directory" : "file")) {
      return { kind: "missing" };
    }
    if (!listing) return { kind: "file", text: readFileSync(path, "utf8") };
    const names = readdirSync(path).sort(); // Includes hidden entries.
    return { kind: "directory", names, kinds: names.map(name => kind(join(path, name))) };
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
