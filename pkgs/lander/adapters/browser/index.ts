type Reply = { kind: string; text: string; size: number; status: number; names?: string[]; directories?: boolean[] };

const failure = (kind: string): Reply => ({ kind, text: "", size: 0, status: 0 });

/** Required Web APIs for one backend: "urls", "files" or "directory". */
export function supported(backend = "urls"): boolean {
  if (typeof AbortController !== "function" || typeof TextEncoder !== "function") return false;
  if (backend === "files" || backend === "directory") return typeof Blob === "function" && typeof Blob.prototype.text === "function";
  return typeof fetch === "function" && typeof TextDecoder === "function";
}

/**
 * Classify a rejected Web API call. Exception text is never returned. A missing
 * entry or a wrong entry kind is absent only where the caller allows it.
 */
function classify(error: unknown, absent = false): string {
  const name = (error as { name?: unknown } | null)?.name;
  if (name === "NotAllowedError" || name === "SecurityError") return "permission";
  if (absent && (name === "NotFoundError" || name === "TypeMismatchError")) return "missing";
  return "io";
}

/**
 * Run Web API work that cannot be aborted. Race it against both signals, ignore
 * a late result and remove the listeners. A rejection becomes a classified reply.
 */
async function guarded(
  signal: AbortSignal, taskSignal: AbortSignal, absent: boolean, work: () => Promise<Reply>,
): Promise<Reply> {
  if (signal.aborted || taskSignal.aborted) return failure("aborted");
  let release = () => {};
  const aborted = new Promise<Reply>(resolve => {
    const abort = () => resolve(failure("aborted"));
    signal.addEventListener("abort", abort, { once: true });
    taskSignal.addEventListener("abort", abort, { once: true });
    release = () => {
      signal.removeEventListener("abort", abort);
      taskSignal.removeEventListener("abort", abort);
    };
  });
  try {
    const done = Promise.resolve().then(work).catch(error => failure(classify(error, absent)));
    return await Promise.race([done, aborted]);
  } finally { release(); }
}

/** Check a known size, read the text, then check its UTF-8 size. */
async function text(file: File, budget: number): Promise<Reply> {
  if (file.size > budget) return failure("limit");
  const text = await file.text();
  const size = new TextEncoder().encode(text).length;
  return size > budget ? failure("limit") : { kind: "file", text, size, status: 0 };
}

/** Read one selected File. File.text() is called only for a requested path. */
export async function readFile(
  file: File, budget: number, signal: AbortSignal, taskSignal: AbortSignal,
): Promise<Reply> {
  if (!supported("files")) return failure("unsupported");
  return guarded(signal, taskSignal, false, () => text(file, budget));
}

/**
 * Resolve directory segments below a caller-supplied handle, one at a time and
 * with create: false. This never opens a picker or requests permission. The
 * MoonBit loader first checks each name against an exact, budgeted listing,
 * because an engine can resolve a name without case on some host file systems.
 */
async function directory(handle: FileSystemDirectoryHandle, segments: string[]): Promise<FileSystemDirectoryHandle> {
  let current = handle;
  for (const segment of segments) current = await current.getDirectoryHandle(segment, { create: false });
  return current;
}

function usable(handle: FileSystemDirectoryHandle): boolean {
  return supported("directory") && typeof handle?.getDirectoryHandle === "function" &&
    typeof handle.getFileHandle === "function" && typeof (handle as any).entries === "function";
}

/**
 * List the direct children of a relative directory ("" is the handle itself).
 * Stop the enumeration as soon as it has more than `limit` children.
 */
export async function listDirectory(
  handle: FileSystemDirectoryHandle, relative: string, limit: number, signal: AbortSignal, taskSignal: AbortSignal,
): Promise<Reply> {
  if (!usable(handle)) return failure("unsupported");
  return guarded(signal, taskSignal, true, async () => {
    const dir = await directory(handle, relative === "" ? [] : relative.split("/"));
    const names: string[] = [], directories: boolean[] = [];
    for await (const [name, entry] of (dir as any).entries() as AsyncIterable<[string, FileSystemHandle]>) {
      if (signal.aborted || taskSignal.aborted) return failure("aborted");
      if (names.length >= limit) return failure("limit");
      names.push(name);
      directories.push(entry.kind === "directory");
    }
    return { kind: "listing", text: "", size: 0, status: 0, names, directories };
  });
}

/** Read the text of a relative file below a caller-supplied handle. */
export async function readDirectoryFile(
  handle: FileSystemDirectoryHandle, relative: string, budget: number, signal: AbortSignal, taskSignal: AbortSignal,
): Promise<Reply> {
  if (!usable(handle)) return failure("unsupported");
  return guarded(signal, taskSignal, true, async () => {
    const segments = relative.split("/");
    const name = segments.pop()!;
    const dir = await directory(handle, segments);
    const file = await (await dir.getFileHandle(name, { create: false })).getFile();
    // Errors after the entry is found are not absence.
    return text(file, budget).catch(error => failure(classify(error)));
  });
}

export function normalizeBase(base: string): string {
  try {
    const url = new URL(base);
    return /^(https?):\/\//i.test(base) && !base.includes("?") && !base.includes("#") &&
      !url.username && !url.password && url.pathname.endsWith("/") ? url.href : "";
  } catch { return ""; }
}

/** Only the Web API boundary. Manifest, namespace and load policy are MoonBit. */
export async function read(
  base: string, relative: string, budget: number,
  signal: AbortSignal, taskSignal: AbortSignal,
): Promise<Reply> {
  if (!supported("urls")) return failure("unsupported");
  const controller = new AbortController();
  const abort = () => controller.abort();
  let response: Response | undefined;
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  let result: Reply = { kind: "io", text: "", size: 0, status: 0 };
  let complete = false;
  signal.addEventListener("abort", abort, { once: true });
  taskSignal.addEventListener("abort", abort, { once: true });
  if (signal.aborted || taskSignal.aborted) abort();
  try {
    const url = new URL(relative.split("/").map(encodeURIComponent).join("/"), base);
    response = await fetch(url, { credentials: "omit", redirect: "error", signal: controller.signal });
    if (response.status === 404) result.kind = "missing";
    else if (!response.ok) result = { ...result, kind: "http", status: response.status };
    else {
      const length = response.headers.get("Content-Length");
      if (length !== null && /^\d+$/.test(length) && Number(length) > budget) {
        result.kind = "limit";
      } else if (!response.body) {
        result = { ...result, kind: "file" };
        complete = true;
      } else {
        reader = response.body.getReader();
        const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
        const parts: string[] = [];
        let size = 0;
        while (true) {
          const chunk = await reader.read();
          if (controller.signal.aborted) { result.kind = "aborted"; break; }
          if (chunk.done) {
            parts.push(decoder.decode());
            const text = parts.join("");
            const actual = new TextEncoder().encode(text).length;
            result = actual > budget ? { ...result, kind: "limit" } : { kind: "file", text, size: actual, status: response.status };
            complete = result.kind === "file";
            break;
          }
          size += chunk.value.byteLength;
          if (size > budget) { result.kind = "limit"; break; }
          parts.push(decoder.decode(chunk.value, { stream: true }));
        }
      }
    }
  } catch {
    result = { kind: controller.signal.aborted ? "aborted" : "io", text: "", size: 0, status: 0 };
  } finally {
    if (!complete) {
      // Abort the transport even if cancel() rejects. A live stream must stop
      // before lock release, and a cleanup error must not replace the cause.
      controller.abort();
      try {
        if (reader) await reader.cancel();
        else if (response?.body) await response.body.cancel();
      } catch { /* Continue remaining cleanup, preserving result. */ }
    }
    if (reader) {
      try { reader.releaseLock(); }
      catch {
        if (complete) { controller.abort(); result = { kind: "io", text: "", size: 0, status: 0 }; }
      }
    }
    signal.removeEventListener("abort", abort);
    taskSignal.removeEventListener("abort", abort);
  }
  return result;
}
