// Console streams and log files of the js logging runtime
// (openspec add-console-and-rolling-file-logging, D2). The pinned
// moonbitlang/async has no js implementation of fs or stdio, so this adapter
// does the I/O over node:* modules only. scripts/build-node-adapter.mbtx
// bundles it into pkgs/logging-hosting-async/runtime/node.generated.js.mbt.
//
// Each operation gives a data-only reply. An error is the text in `error`,
// and an empty text is success, so no JS exception escapes into MoonBit.
import process from "node:process";
import { lstat, mkdir, open, readdir, unlink } from "node:fs/promises";
import type { FileHandle } from "node:fs/promises";

function text(error: unknown): string {
  const message = String(error);
  // A Windows path in an error uses "/" like the native adapter.
  const shown = process.platform === "win32" ? message.replaceAll("\\", "/") : message;
  return shown.length === 0 ? "unknown error" : shown;
}

type Stream = typeof process.stdout;

function stream(fd: number): Stream {
  return fd === 1 ? process.stdout : process.stderr;
}

// A write error also comes as an "error" event. Without a listener, Node.js
// would end the process. The write callback reports the error.
const quiet = new WeakSet<Stream>();
function guard(target: Stream): void {
  if (quiet.has(target)) return;
  quiet.add(target);
  target.on("error", () => {});
}

// Write `value` to standard output (1) or standard error (2). Resolve after
// the stream callback, that is, after the OS accepted the bytes.
export function writeStream(fd: number, value: string): Promise<string> {
  const target = stream(fd);
  guard(target);
  return new Promise(resolve => {
    try {
      target.write(value, "utf8", error => resolve(error ? text(error) : ""));
    } catch (error) {
      resolve(text(error));
    }
  });
}

// What the stream is: "color" or "plain" for a terminal, "redirected" for a
// file or pipe, or "unknown" when the runtime cannot tell.
export function streamKind(fd: number): string {
  const target = stream(fd) as Stream & { hasColors?: () => boolean };
  if (target.isTTY === true) {
    if (typeof target.hasColors !== "function") return "unknown";
    return target.hasColors() ? "color" : "plain";
  }
  if (target.isTTY === false || target.isTTY === undefined) return "redirected";
  return "unknown";
}

export interface Done { error: string }

export async function makeDirectory(path: string): Promise<Done> {
  try {
    await mkdir(path, { recursive: true });
    return { error: "" };
  } catch (error) {
    return { error: text(error) };
  }
}

// Create the file at `path` only when no file is there (exclusive create).
// After the create succeeds, the caller owns the file, also when the close of
// the empty file fails, so that it deletes the file at its own close.
export async function createExclusive(path: string): Promise<Done> {
  let handle: FileHandle;
  try {
    handle = await open(path, "wx");
  } catch (error) {
    return { error: text(error) };
  }
  await handle.close().catch(() => {});
  return { error: "" };
}

export async function removeFile(path: string): Promise<Done> {
  try {
    await unlink(path);
    return { error: "" };
  } catch (error) {
    return { error: text(error) };
  }
}

export interface Opened { error: string; handle: FileHandle | null; size: number }

// Open `path` to append, and create it when it is missing. Never truncate.
export async function openAppend(path: string): Promise<Opened> {
  try {
    const handle = await open(path, "a");
    try {
      const { size } = await handle.stat();
      return { error: "", handle, size };
    } catch (error) {
      await handle.close().catch(() => {});
      return { error: text(error), handle: null, size: 0 };
    }
  } catch (error) {
    return { error: text(error), handle: null, size: 0 };
  }
}

export interface Written { error: string; written: number }

// Write all bytes of `value`. On an error, `written` gives the bytes that the
// OS accepted before it, so a partial write is visible.
export async function writeFile(handle: FileHandle, value: string): Promise<Written> {
  const bytes = Buffer.from(value, "utf8");
  let offset = 0;
  try {
    while (offset < bytes.length) {
      const { bytesWritten } = await handle.write(bytes, offset, bytes.length - offset);
      offset += bytesWritten;
    }
    return { error: "", written: offset };
  } catch (error) {
    return { error: text(error), written: offset };
  }
}

export async function closeFile(handle: FileHandle): Promise<Done> {
  try {
    await handle.close();
    return { error: "" };
  } catch (error) {
    return { error: text(error) };
  }
}

export interface Listing { error: string; names: string[]; sizes: number[]; regular: boolean[] }

// The entries of `path` with their size, and whether each is a regular file.
// Links are not followed, so a link is never a regular file. An entry that
// disappears while the listing runs is left out.
export async function listDirectory(path: string): Promise<Listing> {
  try {
    const names: string[] = [];
    const sizes: number[] = [];
    const regular: boolean[] = [];
    for (const name of (await readdir(path)).sort()) {
      try {
        const stat = await lstat(`${path}/${name}`);
        names.push(name);
        sizes.push(stat.size);
        regular.push(stat.isFile());
      } catch (error) {
        const code = (error as NodeJS.ErrnoException).code;
        if (code === "ENOENT") continue;
        names.push(name);
        sizes.push(0);
        regular.push(false);
      }
    }
    return { error: "", names, sizes, regular };
  } catch (error) {
    return { error: text(error), names: [], sizes: [], regular: [] };
  }
}
