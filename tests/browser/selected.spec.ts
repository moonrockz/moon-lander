import { expect, test, type Page } from "@playwright/test";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

type Files = Record<string, string | Buffer>;

async function run(page: Page, input: any) {
  return page.evaluate(input => (globalThis as any).landerRun(input), input);
}
async function paths(page: Page): Promise<string[]> {
  return (await (await page.request.get(new URL("/stats", page.url()).href)).json()).paths;
}
/** Put real files into a plain HTML file input of the test page. */
async function choose(page: Page, files: Files, selector = "#files") {
  await page.setInputFiles(selector, Object.entries(files).map(([name, content]) => ({
    name, mimeType: "text/plain", buffer: Buffer.isBuffer(content) ? content : Buffer.from(content),
  })));
}
/** Map each selected name to an explicit relative path in a file mount. */
function selected(paths: Record<string, string>, root = "/workspace", selector = "#files") {
  return { kind: "files", root, selector, paths: Object.entries(paths) };
}
function hosted(page: Page) {
  return { base: new URL("/defaults/", page.url()).href, root: "/defaults", manifest: { version: 1, files: ["acme.toml"] } };
}
async function reads(page: Page): Promise<string[]> {
  return page.evaluate(() => (globalThis as any).fileReads.splice(0));
}

const project = {
  "acme.toml": "[server]\nhost = 'selected'\nport = 8080\n",
  "main.mbt": "fn main { }\n",
};
const projectPaths = { "acme.toml": "acme.toml", "main.mbt": "src/main.mbt" };
const outside = { HOME: "/outside/home", ACME_HOME: "/outside/acme", XDG_CONFIG_HOME: "/outside/xdg", APPDATA: "/outside/appdata" };

test.beforeEach(async ({ page }) => {
  await page.goto("/");
  expect(await page.evaluate(() => typeof (globalThis as any).landerRun)).toBe("function");
  // Record every content read of a Blob or File. Names identify selected files.
  await page.evaluate(() => {
    const log: string[] = [];
    (globalThis as any).fileReads = log;
    for (const method of ["text", "arrayBuffer", "bytes", "stream", "slice"]) {
      const original = (Blob.prototype as any)[method];
      if (typeof original !== "function") continue;
      (Blob.prototype as any)[method] = function (this: Blob, ...args: unknown[]) {
        log.push(`${(this as File).name ?? "blob"}:${method}`);
        return original.apply(this, args);
      };
    }
  });
});

test("real file input loads a project and never reads an unrelated large file", async ({ page }) => {
  await choose(page, { ...project, "large.toml": Buffer.alloc(9 * 1024 * 1024, 0x78) });
  const mount = selected({ ...projectPaths, "large.toml": "data/large.toml" });
  const before = (await paths(page)).length;
  const result = await run(page, {
    mounts: [mount], sources: ["acme.toml"], overrides: { server: { port: 9000 } },
    keys: ["server.host", "server.port"], bind: true,
  });
  expect(result.bound).toEqual({ host: "selected", port: 9000 });
  expect(result.origins).toEqual({ "server.host": ["/workspace/acme.toml"], "server.port": ["none"] });
  expect(result.reports).toEqual(["/workspace/acme.toml", "none"]);
  expect(await reads(page)).toEqual(["acme.toml:text"]);
  for (const [path, listing] of [["/workspace", "acme.toml,data,src"], ["/workspace/data", "large.toml"], ["/workspace/absent", "missing-descendant"]]) {
    expect((await run(page, { mounts: [mount], mode: "listing", path, keys: ["listing"] })).values.listing).toBe(listing);
  }
  expect((await run(page, { mounts: [mount], sources: ["missing.toml"] }))).toEqual({ error: "FileNotFound", path: "/workspace/missing.toml" });
  expect(await reads(page)).toEqual([]);
  expect((await paths(page)).length).toBe(before);
  // The large file is readable when requested, so the earlier load did not skip it by accident.
  expect((await run(page, { mounts: [mount], sources: ["data/large.toml"] })).limit).toBe("bytes");
  expect(await reads(page)).toEqual([]);
});

test("selected-file paths, duplicates and collisions fail before any read", async ({ page }) => {
  await choose(page, project);
  for (const [paths, error] of [
    [{ "acme.toml": "../acme.toml" }, "InvalidPath"], [{ "acme.toml": "/acme.toml" }, "InvalidPath"],
    [{ "acme.toml": "a//b" }, "InvalidPath"], [{ "acme.toml": "a\\b" }, "InvalidPath"], [{ "acme.toml": "C:/a" }, "InvalidPath"],
    [{ "acme.toml": "a", "main.mbt": "a" }, "InvalidMount"], [{ "acme.toml": "a", "main.mbt": "a/b" }, "InvalidMount"],
    [{ "acme.toml": "a/b", "main.mbt": "a" }, "InvalidMount"],
  ] as const) {
    const result = await run(page, { mounts: [selected(paths)], sources: ["a"] });
    expect(result.error, JSON.stringify(paths)).toBe(error);
  }
  expect((await run(page, { mounts: [selected(projectPaths, "relative")] })).error).toBe("InvalidPath");
  expect(await reads(page)).toEqual([]);
});

test("workspace discovery finds the root file from a nested mounted directory", async ({ page }) => {
  await choose(page, project);
  const input = {
    mounts: [selected(projectPaths)], cwd: "/workspace/src", platform: "Linux", vars: outside,
    keys: ["server.host"], statuses: true,
  };
  const found = await run(page, { ...input, sources: [{ conventions: "acme", workspace: 0 }] });
  expect(found.values["server.host"]).toBe("selected");
  expect(found.origins["server.host"]).toEqual(["/workspace/acme.toml"]);
  expect(found.statuses).toEqual(["/workspace/acme.toml Loaded", "none NotFound", "none NotFound"]);
  expect(await reads(page)).toEqual(["acme.toml:text"]);
  // Standard conventions ask for machine directories, which no mount holds.
  const standard = await run(page, { ...input, sources: [{ conventions: "acme", boundary: "/workspace" }] });
  expect(standard.error).toBe("OutsideMount");
  // A wider caller boundary cannot escape the mounts either.
  const wider = await run(page, { ...input, mounts: [selected({ "main.mbt": "src/main.mbt" })], sources: [{ conventions: "acme", workspace: 0, boundary: "/" }] });
  expect(wider).toEqual({ error: "OutsideMount", operation: "load", path: "/" });
});

test("workspace discovery stops at the mount root and at a narrower boundary", async ({ page }) => {
  await choose(page, project);
  const input = { cwd: "/workspace/src", keys: ["server.host"], statuses: true };
  const none = await run(page, { ...input, mounts: [selected({ "main.mbt": "src/main.mbt" })], sources: [{ conventions: "acme", workspace: 0 }] });
  expect(none.error).toBe("KeyNotFound");
  const narrow = await run(page, { ...input, mounts: [selected(projectPaths)], sources: [{ conventions: "acme", workspace: 0, boundary: "/workspace/src" }] });
  expect(narrow.error).toBe("KeyNotFound");
  const nested = await run(page, { ...input, mounts: [selected({ "acme.toml": "src/acme.toml", "main.mbt": "src/main.mbt" })], sources: [{ conventions: "acme", workspace: 0, boundary: "/workspace/src" }] });
  expect(nested.origins["server.host"]).toEqual(["/workspace/src/acme.toml"]);
  expect(await reads(page)).toEqual(["acme.toml:text"]);
  const outsideStart = await run(page, { ...input, cwd: "/workspace", mounts: [selected(projectPaths)], sources: [{ conventions: "acme", workspace: 0, boundary: "/workspace/src" }] });
  expect(outsideStart.error).toBe("OutsideBoundary");
});

test("injected home variables give no machine-directory sources", async ({ page }) => {
  await choose(page, project);
  for (const platform of ["Linux", "MacOs", "Windows"]) {
    const result = await run(page, {
      mounts: [selected(projectPaths)], cwd: "/workspace/src", platform, vars: { ...outside, PROGRAMDATA: "/outside/data" },
      sources: [{ conventions: "acme", workspace: 0 }], keys: ["server.host"], statuses: true,
    });
    expect(result.values["server.host"], platform).toBe("selected");
    expect(result.statuses.some((status: string) => status.includes("/outside")), platform).toBe(false);
  }
});

test("discovery matches exact names and local and user overrides keep precedence", async ({ page }) => {
  await choose(page, {
    "Acme.toml": "[server]\nhost = 'case'\n",
    "acme.toml": "[server]\nhost = 'primary'\nport = 1\nname = 'primary'\n",
    "local.toml": "[server]\nhost = 'local'\nport = 2\n",
    "user.toml": "[server]\nport = 3\n",
  });
  const input = { cwd: "/workspace", sources: [{ conventions: "acme", workspace: 0 }], keys: ["server.host", "server.port", "server.name"] };
  const exact = await run(page, { ...input, mounts: [selected({ "Acme.toml": "Acme.toml" })] });
  expect(exact.error).toBe("KeyNotFound");
  const result = await run(page, {
    ...input, mounts: [selected({ "Acme.toml": "Acme.toml", "acme.toml": "acme.toml", "local.toml": "acme.local.toml", "user.toml": "acme.user.toml" })],
  });
  expect(result.values).toEqual({ "server.host": "local", "server.port": "3", "server.name": "primary" });
  expect(result.origins).toEqual({
    "server.host": ["/workspace/acme.local.toml"], "server.port": ["/workspace/acme.user.toml"], "server.name": ["/workspace/acme.toml"],
  });
  expect(result.reports).toEqual(["/workspace/acme.toml", "/workspace/acme.local.toml", "/workspace/acme.user.toml"]);
  expect((await reads(page)).sort()).toEqual(["acme.toml:text", "local.toml:text", "user.toml:text"]);
});

test("ambiguous selected candidates raise the core error with virtual paths", async ({ page }) => {
  await choose(page, { "acme.toml": project["acme.toml"], "hidden.toml": project["acme.toml"] });
  const result = await run(page, {
    mounts: [selected({ "acme.toml": "acme.toml", "hidden.toml": ".acme/acme.toml" })], cwd: "/workspace",
    sources: [{ conventions: "acme", workspace: 0 }],
  });
  expect(result.error).toBe("Ambiguous");
  expect(result.candidates.sort()).toEqual(["/workspace/.acme/acme.toml", "/workspace/acme.toml"]);
});

test("hosted defaults and selected project files merge in builder order", async ({ page }) => {
  await choose(page, { "acme.toml": "[server]\nhost = 'selected'\n", "bad.toml": "[broken\n", "hidden.toml": "[server]\nhost = 'hidden'\n" });
  const project = selected({ "acme.toml": "acme.toml" });
  const discover = { conventions: "acme", workspace: 1 };
  const before = (await paths(page)).length;
  const merged = await run(page, {
    mounts: [hosted(page), project], cwd: "/workspace", sources: ["/defaults/acme.toml", discover],
    keys: ["server.host", "server.port"], bind: true, statuses: true,
  });
  expect(merged.bound).toEqual({ host: "selected", port: 7070 });
  expect(merged.origins).toEqual({ "server.host": ["/workspace/acme.toml"], "server.port": ["/defaults/acme.toml"] });
  expect(merged.statuses).toEqual(["/defaults/acme.toml Loaded", "/workspace/acme.toml Loaded", "none NotFound", "none NotFound"]);
  // The builder, not the mount order, decides precedence. The core rejects an
  // explicit file after discovery, so reverse two explicit files instead.
  const reversed = await run(page, {
    mounts: [hosted(page), project], cwd: "/workspace", sources: ["/workspace/acme.toml", "/defaults/acme.toml"], keys: ["server.host"],
  });
  expect(reversed.values["server.host"]).toBe("defaults");
  expect(reversed.origins["server.host"]).toEqual(["/defaults/acme.toml"]);
  const parse = await run(page, { mounts: [hosted(page), selected({ "bad.toml": "acme.toml" })], cwd: "/workspace", sources: ["/defaults/acme.toml", discover] });
  expect(parse.error).toBe("Parse");
  expect(parse.path).toBe("/workspace/acme.toml");
  const ambiguous = await run(page, {
    mounts: [hosted(page), selected({ "acme.toml": "acme.toml", "hidden.toml": ".acme/acme.toml" })], cwd: "/workspace", sources: ["/defaults/acme.toml", discover],
  });
  expect(ambiguous.error).toBe("Ambiguous");
  // Only the hosted defaults use the network. Selected files are not uploaded.
  expect((await paths(page)).slice(before)).toEqual(["/defaults/acme.toml", "/defaults/acme.toml", "/defaults/acme.toml", "/defaults/acme.toml"]);
  const unchanged = await page.evaluate(async () => {
    const input = document.querySelector("#files") as HTMLInputElement;
    return Promise.all(Array.from(input.files!).map(async file => [file.name, await new Response(file).text()]));
  });
  expect(Object.fromEntries(unchanged)["acme.toml"]).toBe("[server]\nhost = 'selected'\n");
});

test("selected-file limits, read failures and abort are typed and stop reads", async ({ page }) => {
  await choose(page, project);
  const input = { mounts: [selected(projectPaths)], sources: ["acme.toml"] };
  expect((await run(page, { ...input, limits: { entries: 2 } })).limit).toBe("entries");
  expect((await run(page, { ...input, limits: { bytes: 8 } }))).toEqual({ error: "LimitExceeded", operation: "read", path: "/workspace/acme.toml", limit: "bytes" });
  expect(await reads(page)).toEqual([]);
  for (const [name, error] of [["NotReadableError", "Io"], ["NotAllowedError", "PermissionDenied"], ["TypeError", "Io"]] as const) {
    const result = await page.evaluate(async ({ input, name }) => {
      const saved = Blob.prototype.text;
      Blob.prototype.text = () => Promise.reject(new DOMException("selected-file-secret", name));
      try { return await (globalThis as any).landerRun(input); } finally { Blob.prototype.text = saved; }
    }, { input, name });
    expect(result, name).toEqual({ error, operation: "read", path: "/workspace/acme.toml" });
  }
  const unsupported = await page.evaluate(async input => {
    const saved = Blob.prototype.text;
    (Blob.prototype as any).text = undefined;
    try { return await (globalThis as any).landerRun(input); } finally { Blob.prototype.text = saved; }
  }, input);
  expect(unsupported).toEqual({ error: "Unsupported", operation: "load", path: "/workspace" });
  // A selected-file mount does not need fetch.
  const offline = await page.evaluate(async input => {
    const saved = globalThis.fetch;
    (globalThis as any).fetch = undefined;
    try { return await (globalThis as any).landerRun(input); } finally { globalThis.fetch = saved; }
  }, { ...input, keys: ["server.host"] });
  expect(offline.values["server.host"]).toBe("selected");
  const aborted = await page.evaluate(async input => {
    const controller = new AbortController();
    const signal = controller.signal;
    const listeners = new Set<unknown>();
    const add = signal.addEventListener.bind(signal), remove = signal.removeEventListener.bind(signal);
    signal.addEventListener = ((type: string, listener: any, options: any) => { if (type === "abort") listeners.add(listener); add(type, listener, options); }) as any;
    signal.removeEventListener = ((type: string, listener: any, options: any) => { if (type === "abort") listeners.delete(listener); remove(type, listener, options); }) as any;
    (globalThis as any).testSignal = signal;
    const saved = Blob.prototype.text;
    let calls = 0;
    Blob.prototype.text = () => { calls++; return new Promise<string>(() => {}); };
    try {
      const pending = (globalThis as any).landerRun(input);
      setTimeout(() => controller.abort(), 50);
      return { result: await pending, calls, listeners: listeners.size };
    } finally { Blob.prototype.text = saved; delete (globalThis as any).testSignal; }
  }, { mounts: [selected({ "acme.toml": "acme.toml", "main.mbt": "next.toml" })], sources: ["acme.toml", "next.toml"] });
  expect(aborted).toEqual({ result: { error: "Aborted", operation: "load", path: "/workspace/acme.toml" }, calls: 1, listeners: 0 });
});

test("selected-file text follows File.text() decoding", async ({ page }) => {
  await choose(page, {
    "bom.toml": Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from("[server]\nhost = 'bom'\n")]),
    "invalid.toml": Buffer.concat([Buffer.from("# "), Buffer.from([0xff]), Buffer.from("\n[server]\nhost = 'replaced'\n")]),
  });
  const mounts = [selected({ "bom.toml": "bom.toml", "invalid.toml": "invalid.toml" })];
  expect((await run(page, { mounts, sources: ["bom.toml"], keys: ["server.host"] })).values["server.host"]).toBe("bom");
  expect((await run(page, { mounts, sources: ["invalid.toml"], keys: ["server.host"] })).values["server.host"]).toBe("replaced");
});

test("the documented consumer maps file-input names and directory-input paths explicitly", async ({ page }) => {
  const base = new URL("/defaults/", page.url()).href;
  await page.goto("/example");
  expect(await page.evaluate(() => typeof (globalThis as any).loadSelectedServer)).toBe("function");
  await choose(page, { "acme.toml": "[server]\nhost = 'flat'\n" });
  expect(await page.evaluate(base => (globalThis as any).loadSelectedServer((document.querySelector("#files") as HTMLInputElement).files, base), base))
    .toBe("flat:7070 from /workspace/acme.toml");
  // A real directory input reports paths below the selected directory name.
  const dir = await mkdtemp(join(tmpdir(), "lander-selected-"));
  try {
    await mkdir(join(dir, "project", "src"), { recursive: true });
    await writeFile(join(dir, "project", "acme.toml"), "[server]\nhost = 'directory'\n");
    await writeFile(join(dir, "project", "src", "main.mbt"), "fn main { }\n");
    await page.setInputFiles("#directory", join(dir, "project"));
    const relative = await page.evaluate(() => Array.from((document.querySelector("#directory") as HTMLInputElement).files!).map(file => file.webkitRelativePath).sort());
    expect(relative).toEqual(["project/acme.toml", "project/src/main.mbt"]);
    expect(await page.evaluate(base => (globalThis as any).loadSelectedServer((document.querySelector("#directory") as HTMLInputElement).files, base), base))
      .toBe("directory:7070 from /workspace/acme.toml");
  } finally { await rm(dir, { recursive: true, force: true }); }
});
