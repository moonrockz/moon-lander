import type { Page } from "@playwright/test";
import { clearStorage, expect, test } from "./persistent";

async function run(page: Page, input: any) {
  return page.evaluate(input => (globalThis as any).landerRun(input), input);
}
async function ops(page: Page, ...ops: any[]) {
  return run(page, { mode: "store", ops });
}
async function calls(page: Page): Promise<string[]> {
  return page.evaluate(() => (globalThis as any).storageCalls.splice(0));
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
function store(name = "app", root = "/state") { return { kind: "store", name, root }; }
const write = (path: string, text: string, name = "app", root = "/state") => ({ op: "write", name, root, path, text });
const remove = (path: string, name = "app") => ({ op: "remove", name, path });
const acme = (host: string) => `[server]\nhost = '${host}'\n`;

/** Record storage access, writes, pickers and other storage APIs. */
async function spy(page: Page) {
  await page.evaluate(() => {
    const log: string[] = [];
    (globalThis as any).storageCalls = log;
    const wrap = (proto: any, method: string, describe: (args: any[]) => string = () => "") => {
      const original = proto?.[method];
      if (typeof original !== "function") return;
      proto[method] = function (this: any, ...args: any[]) { log.push(`${method}:${describe(args)}`); return original.apply(this, args); };
    };
    wrap(StorageManager.prototype, "getDirectory");
    wrap(FileSystemDirectoryHandle.prototype, "getDirectoryHandle", args => `${args[0]}${args[1]?.create ? ":create" : ""}`);
    wrap(FileSystemDirectoryHandle.prototype, "getFileHandle", args => `${args[0]}${args[1]?.create ? ":create" : ""}`);
    wrap(FileSystemDirectoryHandle.prototype, "removeEntry", args => args[0]);
    wrap(FileSystemFileHandle.prototype, "createWritable");
    wrap(Storage.prototype, "getItem", args => args[0]);
    wrap(Storage.prototype, "setItem", args => args[0]);
    wrap(IDBFactory.prototype, "open", args => args[0]);
  });
}
function changes(log: string[]) {
  return log.filter(call => call.includes(":create") || /^(removeEntry|createWritable|getItem|setItem|open)/.test(call));
}

test.beforeEach(async ({ page }) => {
  await page.goto("/");
  expect(await page.evaluate(() => typeof (globalThis as any).landerRun)).toBe("function");
  await clearStorage(page);
  await spy(page);
});

test("an explicit store saves text, survives reload and mounts at its virtual root", async ({ page }) => {
  for (const [name, root] of [["app", "relative"], ["app", "/state/"], ["app", ""], ["", "/state"], ["a/b", "/state"], ["..", "/state"], [".", "/state"], ["a\\b", "/state"]]) {
    expect((await ops(page, { op: "open", name, root }))[0].error, `${name} ${root}`).toBe("InvalidPath");
  }
  expect(await calls(page)).toEqual([]);
  expect(await snapshot(page)).toEqual([]);
  expect(await ops(page, { op: "open" }, write("acme.toml", acme("saved")))).toEqual([["app", "/state", "/state"], "written"]);
  expect(changes(await calls(page))).toEqual(["getDirectoryHandle:moon-lander:create", "getDirectoryHandle:app:create",
    "getDirectoryHandle:moon-lander:create", "getDirectoryHandle:app:create", "getFileHandle:acme.toml:create", "createWritable:"]);
  await page.reload();
  expect(await page.evaluate(() => typeof (globalThis as any).landerRun)).toBe("function");
  const loaded = await run(page, { mounts: [store()], sources: ["/state/acme.toml"], keys: ["server.host"] });
  expect(loaded.values["server.host"]).toBe("saved");
  expect(loaded.origins["server.host"]).toEqual(["/state/acme.toml"]);
  expect(loaded.reports).toEqual(["/state/acme.toml"]);
  const restored = await run(page, { mounts: [store("app", "/restored")], sources: ["/restored/acme.toml"], keys: ["server.host"] });
  expect(restored.origins["server.host"]).toEqual(["/restored/acme.toml"]);
  expect(await snapshot(page)).toEqual(["moon-lander/", "moon-lander/app/", "moon-lander/app/acme.toml=" + acme("saved")]);
});

test("namespaces are independent and relative paths stay inside the store", async ({ page }) => {
  expect(await ops(page, write("acme.toml", acme("alpha"), "alpha"), write("acme.toml", acme("beta"), "beta"), write("nested/dir/acme.toml", acme("nested"), "alpha")))
    .toEqual(["written", "written", "written"]);
  const before = await snapshot(page);
  for (const path of ["../beta/acme.toml", "/acme.toml", "a//b", "./acme.toml", "a\\b", ""]) {
    expect((await ops(page, write(path, "x", "alpha")))[0].error, path).toBe("InvalidPath");
    expect((await ops(page, remove(path, "alpha")))[0].error, path).toBe("InvalidPath");
  }
  expect(await snapshot(page)).toEqual(before);
  expect(await ops(page, remove("nested", "alpha"))).toEqual([{ error: "Io", operation: "remove", path: "/state/nested" }]);
  expect(await ops(page, remove("acme.toml", "alpha"), remove("acme.toml", "alpha"), remove("ACME.toml", "beta"))).toEqual([true, false, false]);
  const beta = await run(page, { mounts: [store("beta")], sources: ["acme.toml"], keys: ["server.host"] });
  expect(beta.values["server.host"]).toBe("beta");
  expect(await run(page, { mounts: [store("alpha")], sources: ["acme.toml"] })).toEqual({ error: "FileNotFound", path: "/state/acme.toml" });
  expect((await run(page, { mounts: [store("alpha")], sources: ["nested/dir/acme.toml"], keys: ["server.host"] })).values["server.host"]).toBe("nested");
});

test("loads never write, and one builder merges hosted defaults, a selected workspace and stored overrides", async ({ page }) => {
  const hosted = { base: new URL("/defaults/", page.url()).href, root: "/defaults", manifest: { version: 1, files: ["acme.toml"] } };
  await page.setInputFiles("#files", [{ name: "acme.toml", mimeType: "text/plain", buffer: Buffer.from("[server]\nhost = 'selected'\nname = 'workspace'\n") }]);
  const workspace = { kind: "files", root: "/workspace", selector: "#files", paths: [["acme.toml", "acme.toml"]] };
  // URL and selected-file loads create no OPFS namespace.
  await run(page, { mounts: [hosted, workspace], cwd: "/workspace", sources: ["/defaults/acme.toml", { conventions: "acme", workspace: 1 }] });
  expect(await snapshot(page)).toEqual([]);
  expect(await ops(page, write("acme.toml", "[server]\nport = 9999\nname = 'stored'\n"))).toEqual(["written"]);
  const before = await snapshot(page);
  await calls(page);
  const merged = await run(page, {
    mounts: [hosted, workspace, store()], cwd: "/workspace",
    sources: ["/defaults/acme.toml", { conventions: "acme", workspace: 1 }, { file: "/state/acme.toml", priority: 500 }],
    keys: ["server.host", "server.port", "server.name"], bind: true, statuses: true,
  });
  expect(merged.bound).toEqual({ host: "selected", port: 9999 });
  expect(merged.values["server.name"]).toBe("stored");
  expect(merged.origins).toEqual({
    "server.host": ["/workspace/acme.toml"], "server.port": ["/state/acme.toml"], "server.name": ["/state/acme.toml"],
  });
  expect(merged.statuses).toEqual(["/defaults/acme.toml Loaded", "/workspace/acme.toml Loaded", "none NotFound", "none NotFound", "/state/acme.toml Loaded"]);
  // Opening the store mount is the only storage creation; the load itself writes nothing.
  expect(changes(await calls(page))).toEqual(["getDirectoryHandle:moon-lander:create", "getDirectoryHandle:app:create"]);
  expect(await snapshot(page)).toEqual(before);
});

test("storage failures are typed and never fall back to other storage", async ({ page }) => {
  expect(await ops(page, write("acme.toml", acme("original")))).toEqual(["written"]);
  await calls(page);
  const inject = async (setup: string, op: any) => page.evaluate(async ({ setup, op }) => {
    const restore: (() => void)[] = [];
    const patch = (target: any, key: string, value: unknown) => {
      const saved = Object.getOwnPropertyDescriptor(target, key);
      Object.defineProperty(target, key, { configurable: true, writable: true, value });
      restore.push(() => saved ? Object.defineProperty(target, key, saved) : delete target[key]);
    };
    const fail = (name: string) => () => Promise.reject(new DOMException("storage-secret", name));
    const writable = (globalThis as any).FileSystemWritableFileStream?.prototype;
    if (setup === "no-opfs") patch(StorageManager.prototype, "getDirectory", undefined);
    if (setup === "private") patch(StorageManager.prototype, "getDirectory", fail("UnknownError"));
    if (setup === "blocked") patch(StorageManager.prototype, "getDirectory", fail("SecurityError"));
    if (setup === "denied") patch(FileSystemDirectoryHandle.prototype, "getFileHandle", fail("NotAllowedError"));
    if (setup === "no-writable") patch(FileSystemFileHandle.prototype, "createWritable", undefined);
    if (setup === "quota") patch(writable, "write", fail("QuotaExceededError"));
    // A close that rejects without releasing the stream; the adapter must abort it.
    if (setup === "close") patch(writable, "close", fail("InvalidStateError"));
    try { return await (globalThis as any).landerRun({ mode: "store", ops: [op] }); }
    finally { for (const undo of restore.reverse()) undo(); }
  }, { setup, op });
  for (const [setup, op, error] of [
    ["no-opfs", { op: "open" }, { error: "Unsupported", operation: "open_store", path: "/state" }],
    ["private", { op: "open" }, { error: "Unsupported", operation: "open_store", path: "/state" }],
    ["blocked", { op: "open" }, { error: "PermissionDenied", operation: "open_store", path: "/state" }],
    ["denied", write("acme.toml", acme("denied")), { error: "PermissionDenied", operation: "write_text", path: "/state/acme.toml" }],
    ["no-writable", write("acme.toml", acme("unsupported")), { error: "Unsupported", operation: "write_text", path: "/state/acme.toml" }],
    ["quota", write("acme.toml", acme("quota")), { error: "LimitExceeded", operation: "write_text", path: "/state/acme.toml", limit: "quota" }],
    ["close", write("acme.toml", acme("close")), { error: "Io", operation: "write_text", path: "/state/acme.toml" }],
  ] as const) {
    const result = await inject(setup, op);
    expect(result, setup).toEqual([error]);
    expect(JSON.stringify(result)).not.toContain("storage-secret");
    // No failed save is reported as success, and the stored text is unchanged.
    const loaded = await run(page, { mounts: [store()], sources: ["acme.toml"], keys: ["server.host"] });
    expect(loaded.values["server.host"], setup).toBe("original");
    // A failed first save leaves no new file.
    if (op.op === "write") {
      const fresh = await inject(setup, write("new.toml", acme(setup)));
      expect(fresh, setup).toEqual([{ ...error, path: "/state/new.toml" }]);
      expect(await run(page, { mounts: [store()], sources: ["new.toml"] }), setup).toEqual({ error: "FileNotFound", path: "/state/new.toml" });
    }
  }
  // The failed close released the file: the next save succeeds.
  expect(await ops(page, write("acme.toml", acme("after")))).toEqual(["written"]);
  expect((await run(page, { mounts: [store()], sources: ["acme.toml"], keys: ["server.host"] })).values["server.host"]).toBe("after");
  expect((await calls(page)).filter(call => /^(getItem|setItem|open)/.test(call))).toEqual([]);
});

const conflict = { error: "InvalidPath", operation: "write_text", reason: "the host maps the name to an entry with another exact name" };

/** The stored value of `server.host` in one relative file of the `app` store. */
async function host(page: Page, path: string) {
  return (await run(page, { mounts: [store()], sources: [path], keys: ["server.host"] })).values["server.host"];
}

/** Whether this host resolves `ACME.toml` to the stored `acme.toml`. */
async function folds(page: Page) {
  return page.evaluate(async () => {
    const owned = await (await navigator.storage.getDirectory()).getDirectoryHandle("moon-lander");
    const app = await owned.getDirectoryHandle("app");
    try { await app.getFileHandle("ACME.toml"); return true; } catch { return false; }
  });
}

test("a write never replaces an entry with another exact name on this host", async ({ page }) => {
  expect(await ops(page, write("acme.toml", acme("original")), write("nested/acme.toml", acme("nested")))).toEqual(["written", "written"]);
  const before = await snapshot(page);
  const folding = await folds(page);
  const result = await ops(page, write("ACME.toml", acme("other")), write("Nested/acme.toml", acme("other")));
  if (folding) {
    // WebKit on a case-insensitive host, such as macOS.
    expect(result).toEqual([conflict, conflict]);
    expect(await snapshot(page)).toEqual(before);
  } else {
    expect(result).toEqual(["written", "written"]);
    expect(await snapshot(page)).toEqual([...before, "moon-lander/app/ACME.toml=" + acme("other"),
      "moon-lander/app/Nested/", "moon-lander/app/Nested/acme.toml=" + acme("other")].sort());
  }
  expect(await host(page, "acme.toml")).toBe("original");
  expect(await host(page, "nested/acme.toml")).toBe("nested");
});

test("a write rejects a case variant when the host resolves names without case", async ({ page }) => {
  expect(await ops(page, write("acme.toml", acme("original")), write("nested/acme.toml", acme("nested")))).toEqual(["written", "written"]);
  const before = await snapshot(page);
  await calls(page);
  // Resolve a name to an existing entry that differs only in case, as WebKit does
  // on a case-insensitive macOS file system. This makes the case run in every engine.
  await page.evaluate(() => {
    const proto = FileSystemDirectoryHandle.prototype as any;
    const saved = { file: proto.getFileHandle, directory: proto.getDirectoryHandle };
    (globalThis as any).restoreCase = () => Object.assign(proto, { getFileHandle: saved.file, getDirectoryHandle: saved.directory });
    const fold = (original: any) => async function (this: FileSystemDirectoryHandle, name: string, options?: { create?: boolean }) {
      for await (const [entry] of (this as any).entries() as AsyncIterable<[string, FileSystemHandle]>) {
        if (entry !== name && entry.toLowerCase() === name.toLowerCase()) return original.call(this, entry, { create: false });
      }
      return original.call(this, name, options);
    };
    proto.getFileHandle = fold(saved.file);
    proto.getDirectoryHandle = fold(saved.directory);
  });
  try {
    expect(await ops(page, write("ACME.toml", acme("other")), write("Nested/acme.toml", acme("other")), write("nested/ACME.toml", acme("other"))))
      .toEqual([conflict, conflict, conflict]);
    // No variant write changed or removed an entry.
    expect(await snapshot(page)).toEqual(before);
    expect(changes(await calls(page)).filter(call => /^(removeEntry|createWritable)/.test(call))).toEqual([]);
    // Exact names and new names still write.
    expect(await ops(page, write("acme.toml", acme("exact")), write("new.toml", acme("new")))).toEqual(["written", "written"]);
  } finally {
    await page.evaluate(() => (globalThis as any).restoreCase());
  }
  expect(await snapshot(page)).toEqual(["moon-lander/", "moon-lander/app/", "moon-lander/app/acme.toml=" + acme("exact"),
    "moon-lander/app/nested/", "moon-lander/app/nested/acme.toml=" + acme("nested"), "moon-lander/app/new.toml=" + acme("new")]);
  expect(await host(page, "nested/acme.toml")).toBe("nested");
});
