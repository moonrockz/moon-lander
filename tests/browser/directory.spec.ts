import type { Page } from "@playwright/test";
import { expect, test } from "./persistent";

type Tree = Record<string, string>;

async function run(page: Page, input: any) {
  return page.evaluate(input => (globalThis as any).landerRun(input), input);
}
async function paths(page: Page): Promise<string[]> {
  return (await (await page.request.get(new URL("/stats", page.url()).href)).json()).paths;
}
/** Create a real OPFS directory for the test. A path that ends in "/" is an empty directory. */
async function opfs(page: Page, tree: Tree, name = "project") {
  await page.evaluate(async ({ tree, name }) => {
    const root = await navigator.storage.getDirectory();
    await root.removeEntry(name, { recursive: true }).catch(() => {});
    const top = await root.getDirectoryHandle(name, { create: true });
    for (const [path, text] of Object.entries(tree)) {
      const parts = path.split("/");
      const file = parts.pop()!;
      let dir = top;
      for (const part of parts) dir = await dir.getDirectoryHandle(part, { create: true });
      if (file === "") continue;
      const writable = await (await dir.getFileHandle(file, { create: true })).createWritable();
      await writable.write(text);
      await writable.close();
    }
    (globalThis as any).testHandles = { ...((globalThis as any).testHandles ?? {}), [name]: top };
  }, { tree, name });
}
/** The complete OPFS content below the origin root, as path and text pairs. */
async function snapshot(page: Page) {
  return page.evaluate(async () => {
    const out: string[] = [];
    async function walk(dir: FileSystemDirectoryHandle, prefix: string) {
      for await (const [name, entry] of (dir as any).entries() as AsyncIterable<[string, FileSystemHandle]>) {
        if (entry.kind === "directory") { out.push(prefix + name + "/"); await walk(entry as FileSystemDirectoryHandle, prefix + name + "/"); }
        else out.push(prefix + name + "=" + await (await (entry as FileSystemFileHandle).getFile()).text());
      }
    }
    await walk(await navigator.storage.getDirectory(), "");
    return out.sort();
  });
}
function directory(root = "/workspace", handle = "project") { return { kind: "directory", root, handle }; }
function hosted(page: Page) {
  return { base: new URL("/defaults/", page.url()).href, root: "/defaults", manifest: { version: 1, files: ["acme.toml"] } };
}

const project: Tree = {
  "acme.toml": "[server]\nhost = 'directory'\nport = 8080\n",
  "acme.local.toml": "[server]\nport = 9090\n",
  "src/main.mbt": "fn main { }\n",
  "data/unrelated.toml": "[server]\nhost = 'unrelated'\n",
  "empty/": "",
};

test.beforeEach(async ({ page }) => {
  await page.goto("/");
  expect(await page.evaluate(() => typeof (globalThis as any).landerRun)).toBe("function");
  // Record writes, creation options, reads, pickers and permission requests.
  await page.evaluate(() => {
    const log: string[] = [];
    (globalThis as any).handleCalls = log;
    const spy = (proto: any, method: string, describe: (args: any[]) => string) => {
      const original = proto?.[method];
      if (typeof original !== "function") return;
      proto[method] = function (this: any, ...args: any[]) { log.push(`${method}:${describe(args)}`); return original.apply(this, args); };
    };
    const option = (args: any[]) => `${args[0]}${args[1]?.create ? ":create" : ""}`;
    spy(FileSystemDirectoryHandle.prototype, "getDirectoryHandle", option);
    spy(FileSystemDirectoryHandle.prototype, "getFileHandle", option);
    spy(FileSystemDirectoryHandle.prototype, "removeEntry", args => args[0]);
    spy(FileSystemFileHandle.prototype, "getFile", () => "");
    spy(FileSystemFileHandle.prototype, "createWritable", () => "");
    spy((globalThis as any).FileSystemHandle?.prototype, "requestPermission", () => "");
    spy((globalThis as any).FileSystemHandle?.prototype, "queryPermission", () => "");
    for (const picker of ["showDirectoryPicker", "showOpenFilePicker", "showSaveFilePicker"]) spy(globalThis, picker, () => "");
  });
});
async function calls(page: Page): Promise<string[]> {
  return page.evaluate(() => (globalThis as any).handleCalls.splice(0));
}
function writes(log: string[]) {
  return log.filter(call => call.includes(":create") || /^(removeEntry|createWritable|requestPermission|queryPermission|show)/.test(call));
}

test("a real directory handle answers listings and lazy reads like a selected-file mount", async ({ page }) => {
  await opfs(page, project);
  const before = await snapshot(page);
  await calls(page);
  const input = {
    cwd: "/workspace/src", sources: [{ conventions: "acme", workspace: 0 }], vars: { HOME: "/outside" }, platform: "Linux",
    overrides: { server: { name: "override" } }, keys: ["server.host", "server.port", "server.name"], statuses: true, bind: true,
  };
  const live = await run(page, { ...input, mounts: [directory()] });
  expect(live.values).toEqual({ "server.host": "directory", "server.port": "9090", "server.name": "override" });
  expect(live.origins).toEqual({
    "server.host": ["/workspace/acme.toml"], "server.port": ["/workspace/acme.local.toml"], "server.name": ["none"],
  });
  expect(live.statuses).toEqual(["/workspace/acme.toml Loaded", "/workspace/acme.local.toml Loaded", "none NotFound", "none Loaded"]);
  const log = await calls(page);
  expect(log.filter(call => call === "getFile:")).toHaveLength(2);
  expect(writes(log)).toEqual([]);
  // The same files as a selected-file mount give the same observations.
  await page.setInputFiles("#files", Object.entries(project).filter(([path]) => !path.endsWith("/")).map(([path, text]) => ({
    name: path.replaceAll("/", "_"), mimeType: "text/plain", buffer: Buffer.from(text),
  })));
  const selected = { kind: "files", root: "/workspace", selector: "#files", paths: Object.keys(project).filter(path => !path.endsWith("/")).map(path => [path.replaceAll("/", "_"), path]) };
  expect(await run(page, { ...input, mounts: [selected] })).toEqual(live);
  for (const [path, listing] of [
    ["/workspace", "acme.local.toml,acme.toml,data,empty,src"], ["/workspace/empty", ""], ["/workspace/src", "main.mbt"],
    ["/workspace/absent", "missing-descendant"],
  ]) {
    expect((await run(page, { mounts: [directory()], mode: "listing", path, keys: ["listing"] })).values.listing, path).toBe(listing);
  }
  expect(writes(await calls(page))).toEqual([]);
  expect(await snapshot(page)).toEqual(before);
});

test("missing and wrong-kind entries are absent and names match exactly", async ({ page }) => {
  await opfs(page, { "acme.toml/": "", "src": "not a directory\n", "nested/main.mbt": "" });
  const before = await snapshot(page);
  await calls(page);
  expect(await run(page, { mounts: [directory()], sources: ["acme.toml"] })).toEqual({ error: "FileNotFound", path: "/workspace/acme.toml" });
  expect(await run(page, { mounts: [directory()], sources: ["missing/acme.toml"] })).toEqual({ error: "FileNotFound", path: "/workspace/missing/acme.toml" });
  expect((await run(page, { mounts: [directory()], mode: "listing", path: "/workspace/src", keys: ["listing"] })).values.listing).toBe("missing-descendant");
  expect(writes(await calls(page))).toEqual([]);
  expect(await snapshot(page)).toEqual(before);
  // Some host file systems behind OPFS ignore case. Names must still match exactly.
  await opfs(page, { "Acme.toml": "[server]\nhost = 'case'\n", "nested/main.mbt": "", "dir/other.toml": "[server]\nhost = 'dir'\n" });
  const exact = await snapshot(page);
  await calls(page);
  expect((await run(page, { mounts: [directory()], sources: ["Acme.toml"], keys: ["server.host"] })).values["server.host"]).toBe("case");
  expect(await run(page, { mounts: [directory()], sources: ["acme.toml"] })).toEqual({ error: "FileNotFound", path: "/workspace/acme.toml" });
  expect((await run(page, { mounts: [directory()], sources: ["dir/other.toml"], keys: ["server.host"] })).values["server.host"]).toBe("dir");
  expect(await run(page, { mounts: [directory()], sources: ["DIR/other.toml"] })).toEqual({ error: "FileNotFound", path: "/workspace/DIR/other.toml" });
  const discovered = await run(page, { mounts: [directory()], cwd: "/workspace/nested", sources: [{ conventions: "acme", workspace: 0 }], keys: ["server.host"] });
  expect(discovered.error).toBe("KeyNotFound");
  expect(writes(await calls(page))).toEqual([]);
  expect(await snapshot(page)).toEqual(exact);
});

test("a second load sees changed content and the first configuration stays unchanged", async ({ page }) => {
  await opfs(page, { "acme.toml": "[server]\nhost = 'first'\nport = 1\n" });
  await page.evaluate(() => {
    (globalThis as any).betweenLoads = async () => {
      const dir = (globalThis as any).testHandles.project as FileSystemDirectoryHandle;
      const writable = await (await dir.getFileHandle("acme.toml")).createWritable();
      await writable.write("[server]\nhost = 'second'\nport = 2\n");
      await writable.close();
    };
  });
  const result = await run(page, { mounts: [directory()], sources: ["acme.toml"], keys: ["server.host", "server.port"], between: true });
  expect(result.values).toEqual({ "server.host": "first", "server.port": "1" });
  expect(result.first_after).toEqual(result.values);
  expect(result.second).toEqual({ "server.host": "second", "server.port": "2" });
});

test("loading never creates directories or files", async ({ page }) => {
  await opfs(page, { "src/main.mbt": "" });
  const before = await snapshot(page);
  await calls(page);
  for (const input of [
    { sources: ["missing.toml"] }, { sources: ["deep/missing/acme.toml"] }, { mode: "listing", path: "/workspace/absent", keys: ["listing"] },
    { cwd: "/workspace/src", sources: [{ conventions: "acme", workspace: 0 }] },
  ]) await run(page, { mounts: [directory()], ...input });
  const log = await calls(page);
  expect(log.some(call => call.startsWith("getDirectoryHandle"))).toBe(true);
  expect(writes(log)).toEqual([]);
  expect(await snapshot(page)).toEqual(before);
});

test("denied and revoked handle operations raise PermissionDenied without fallback", async ({ page }) => {
  await opfs(page, project);
  await page.evaluate(() => {
    const real = (globalThis as any).testHandles.project as FileSystemDirectoryHandle;
    const fail = (name: string) => Promise.reject(new DOMException("handle-secret", name));
    // Controlled error injection. These fixtures do not test native picker UI.
    const wrap = (dir: any, state: { revoked: boolean; name: string; getFile?: string }): any => ({
      kind: "directory", name: dir.name,
      getDirectoryHandle: async (name: string, options: any) => state.revoked ? fail(state.name) : wrap(await dir.getDirectoryHandle(name, options), state),
      getFileHandle: async (name: string, options: any) => {
        if (state.revoked) return fail(state.name);
        const file = await dir.getFileHandle(name, options);
        return { kind: "file", name, getFile: () => state.getFile ? fail(state.getFile) : file.getFile() };
      },
      entries: async function* () {
        if (state.revoked) throw new DOMException("handle-secret", state.name);
        yield* dir.entries();
        state.revoked = (globalThis as any).revokeAfterListing ?? false;
      },
    });
    const denied = (name: string) => ({
      kind: "directory", name: "denied",
      getDirectoryHandle: () => fail(name), getFileHandle: () => fail(name),
      entries: async function* () { throw new DOMException("handle-secret", name); },
    });
    (globalThis as any).testHandles = {
      ...(globalThis as any).testHandles,
      denied: denied("NotAllowedError"), security: denied("SecurityError"), broken: denied("InvalidStateError"),
      revoked: wrap(real, { revoked: false, name: "NotAllowedError" }),
      unreadable: wrap(real, { revoked: false, name: "NotAllowedError", getFile: "NotAllowedError" }),
      partial: { kind: "directory", getDirectoryHandle: () => fail("NotAllowedError"), getFileHandle: () => fail("NotAllowedError") },
    };
  });
  await calls(page);
  const before = (await paths(page)).length;
  for (const [handle, error] of [["denied", "PermissionDenied"], ["security", "PermissionDenied"], ["broken", "Io"]]) {
    const result = await run(page, { mounts: [hosted(page), directory("/workspace", handle)], sources: ["/defaults/acme.toml", "/workspace/acme.toml"] });
    expect(result, handle).toEqual({ error, operation: "read", path: "/workspace/acme.toml" });
    expect(JSON.stringify(result)).not.toContain("handle-secret");
  }
  // The hosted mount answered only its own file. No other mount or store replaced the denied read.
  expect((await paths(page)).slice(before)).toEqual(["/defaults/acme.toml", "/defaults/acme.toml", "/defaults/acme.toml"]);
  expect(await run(page, { mounts: [directory("/workspace", "unreadable")], sources: ["acme.toml"] }))
    .toEqual({ error: "PermissionDenied", operation: "read", path: "/workspace/acme.toml" });
  await page.evaluate(() => { (globalThis as any).revokeAfterListing = true; });
  const revoked = await run(page, { mounts: [directory("/workspace", "revoked")], cwd: "/workspace/src", sources: [{ conventions: "acme", workspace: 0 }] });
  expect(revoked.error).toBe("PermissionDenied");
  expect(revoked.operation).toBe("list");
  expect(revoked.path).toMatch(/^\/workspace\/src\//);
  expect(await run(page, { mounts: [directory("/workspace", "partial")], sources: ["acme.toml"] }))
    .toEqual({ error: "Unsupported", operation: "read", path: "/workspace/acme.toml" });
  expect(writes(await calls(page))).toEqual([]);
});

test("directory limits and abort stop handle operations", async ({ page }) => {
  await opfs(page, project);
  const listing = { mounts: [directory()], mode: "listing", path: "/workspace", keys: ["listing"] };
  expect((await run(page, { ...listing, limits: { entries: 5 } })).values.listing).toBe("acme.local.toml,acme.toml,data,empty,src");
  expect(await run(page, { ...listing, limits: { entries: 4 } })).toEqual({ error: "LimitExceeded", operation: "list", path: "/workspace", limit: "entries" });
  expect(await run(page, { mounts: [directory()], sources: ["acme.toml"], limits: { bytes: 8 } }))
    .toEqual({ error: "LimitExceeded", operation: "read", path: "/workspace/acme.toml", limit: "bytes" });
  expect((await run(page, { mounts: [directory()], sources: ["acme.toml", "data/unrelated.toml"], limits: { entries: 1 } })).limit).toBe("entries");
  const aborted = await page.evaluate(async input => {
    const controller = new AbortController();
    const signal = controller.signal;
    const listeners = new Set<unknown>();
    const add = signal.addEventListener.bind(signal), remove = signal.removeEventListener.bind(signal);
    signal.addEventListener = ((type: string, listener: any, options: any) => { if (type === "abort") listeners.add(listener); add(type, listener, options); }) as any;
    signal.removeEventListener = ((type: string, listener: any, options: any) => { if (type === "abort") listeners.delete(listener); remove(type, listener, options); }) as any;
    (globalThis as any).testSignal = signal;
    let calls = 0;
    (globalThis as any).testHandles.pending = {
      kind: "directory", getDirectoryHandle: () => new Promise(() => {}), getFileHandle: () => new Promise(() => {}),
      entries: async function* () { calls++; await new Promise(() => {}); },
    };
    try {
      const pending = (globalThis as any).landerRun(input);
      setTimeout(() => controller.abort(), 50);
      return { result: await pending, calls, listeners: listeners.size };
    } finally { delete (globalThis as any).testSignal; }
  }, { mounts: [directory("/workspace", "pending")], sources: ["acme.toml", "next.toml"] });
  expect(aborted).toEqual({ result: { error: "Aborted", operation: "load", path: "/workspace/acme.toml" }, calls: 1, listeners: 0 });
});

test("the consumer detects picker support and loads a supplied handle headlessly", async ({ page }) => {
  await page.goto("/example");
  expect(await page.evaluate(() => typeof (globalThis as any).loadDirectoryServer)).toBe("function");
  await opfs(page, { "acme.toml": "[server]\nhost = 'handle'\n", "src/main.mbt": "" });
  const support = await page.evaluate(() => (globalThis as any).browserCapabilities());
  expect(support).toEqual(await page.evaluate(() => ({
    directoryPicker: typeof (globalThis as any).showDirectoryPicker === "function",
    directoryInput: "webkitdirectory" in HTMLInputElement.prototype,
    originPrivateStorage: typeof navigator.storage?.getDirectory === "function",
  })));
  expect(support.directoryInput).toBe(true);
  expect(support.originPrivateStorage).toBe(true);
  const base = new URL("/defaults/", page.url()).href;
  const loaded = await page.evaluate(base => (globalThis as any).loadDirectoryServer((globalThis as any).testHandles.project, base), base);
  expect(loaded).toBe("handle:7070 from /workspace/acme.toml");
  // Without a native picker, the selected-file fallback still works.
  await page.evaluate(() => { delete (globalThis as any).showDirectoryPicker; });
  expect((await page.evaluate(() => (globalThis as any).browserCapabilities())).directoryPicker).toBe(false);
  await page.setInputFiles("#files", [{ name: "acme.toml", mimeType: "text/plain", buffer: Buffer.from("[server]\nhost = 'fallback'\n") }]);
  expect(await page.evaluate(base => (globalThis as any).loadSelectedServer((document.querySelector("#files") as HTMLInputElement).files, base), base))
    .toBe("fallback:7070 from /workspace/acme.toml");
});
