// Spike-only boundary, linked into the unpublished browser fixture.
// The public mount API is implemented by task group 2.
export async function fetchText(url: string, signal: AbortSignal) {
  try {
    const response = await fetch(url, { signal, credentials: "omit", redirect: "error" });
    if (!response.ok) return { kind: "http", text: "", status: response.status };
    return { kind: "file", text: await response.text(), status: response.status };
  } catch {
    return { kind: "io", text: "", status: 0 };
  }
}
