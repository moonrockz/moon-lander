type Reply = { kind: string; text: string; size: number; status: number };

export function supported(): boolean {
  return typeof fetch === "function" && typeof AbortController === "function" &&
    typeof TextDecoder === "function" && typeof TextEncoder === "function";
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
  if (!supported()) return { kind: "unsupported", text: "", size: 0, status: 0 };
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
