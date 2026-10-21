import { expect, test, type Page } from "@playwright/test";

function mount(page: Page, files: string[] = ["acme.toml"], root = "/workspace", suffix = "/") {
  return { base: new URL(suffix, page.url()).href, root, manifest: { version: 1, files } };
}
async function run(page: Page, input: any) {
  return page.evaluate(input => (globalThis as any).landerRun(input), input);
}
async function stats(page: Page) { return (await page.request.get(new URL("/stats", page.url()).href)).json(); }
async function pathsSince(page: Page, start: number) { return (await stats(page)).paths.slice(start); }
test.beforeEach(async ({ page }) => {
  await page.goto("/");
  expect(await page.evaluate(() => typeof (globalThis as any).landerRun)).toBe("function");
});

test("production mounts merge, override, bind and retain virtual reports and origins", async ({ page }) => {
  const result = await run(page, {
    mounts: [mount(page, ["acme.toml"], "/defaults", "/defaults/"), mount(page, ["acme.toml"], "/workspace", "/workspace/")],
    sources: ["/defaults/acme.toml", "/workspace/acme.toml"], overrides: { server: { port: 9000 } },
    keys: ["server.host", "server.port"], bind: true,
  });
  expect(result.bound).toEqual({ host: "workspace", port: 9000 });
  expect(result.origins).toEqual({ "server.host": ["/workspace/acme.toml"], "server.port": ["none"] });
  expect(result.reports).toEqual(["/defaults/acme.toml", "/workspace/acme.toml", "none"]);
  expect(await page.evaluate(() => [typeof (globalThis as any).process, typeof (globalThis as any).require, typeof (globalThis as any).Bun])).toEqual(["undefined", "undefined", "undefined"]);
});

test("invalid roots, paths, manifest shapes and collisions fail without network I/O", async ({ page }) => {
  const start = (await stats(page)).paths.length;
  for (const root of ["", "relative", "/a/", "/a//b", "/a/.", "/a/..", "//a", "/a\\b", "/a\0b", "C:/a"]) {
    expect((await run(page, { mode: "construct", mounts: [mount(page, [], root)] })).error).toBe("InvalidPath");
  }
  for (const path of ["", "/absolute", ".", "..", "../a", "a/../b", "a/./b", "a//b", "a/", "a\\b", "a\0b", "C:/a"]) {
    expect((await run(page, { mode: "construct", mounts: [mount(page, [path])] })).error).toBe("InvalidPath");
  }
  for (const manifest of [
    null, [], {}, { version: 2, files: [] }, { version: "1", files: [] },
    { version: 1, files: "a" }, { version: 1, files: [1] }, { version: 1, files: [], directories: null },
    { version: 1, files: [], url: "https://secret.invalid/" },
    { version: 1, files: ["a", "a"] }, { version: 1, files: [], directories: ["a", "a"] },
    { version: 1, files: ["a"], directories: ["a"] },
    { version: 1, files: ["a", "a/b"] }, { version: 1, files: ["a/b", "a"] },
  ]) {
    const result = await run(page, { mode: "construct", mounts: [{ ...mount(page), manifest }] });
    expect(result.error, JSON.stringify(manifest)).toBe("InvalidMount");
  }
  expect(await pathsSince(page, start)).toEqual([]);
});

test("directory URL bases retain their path and encode each literal filename segment", async ({ page }) => {
  const start = (await stats(page)).paths.length;
  for (const base of [
    new URL("/configs", page.url()).href, "file:///configs/", "ftp://host/configs/",
    "https://name:secret@host/configs/", new URL("/configs/?secret=1", page.url()).href,
    new URL("/configs/#secret", page.url()).href, "relative/", "not a url",
  ]) {
    const result = await run(page, { mode: "construct", mounts: [{ ...mount(page), base }] });
    expect(result.error).toBe("InvalidMount");
    expect(JSON.stringify(result)).not.toContain("secret");
  }
  expect(await pathsSince(page, start)).toEqual([]);
  const normal = await run(page, { mounts: [mount(page, ["acme.toml"], "/workspace", "/configs/")], sources: ["acme.toml"], keys: ["server.host"] });
  expect(normal.values["server.host"]).toBe("directory-base");
  const filename = "space % #é?.toml";
  const encoded = await run(page, { mounts: [mount(page, [filename], "/workspace", "/configs/")], sources: [filename], keys: ["server.host"] });
  expect(encoded.values["server.host"]).toBe("encoded");
  expect(await pathsSince(page, start)).toEqual(["/configs/acme.toml", "/configs/" + encodeURIComponent(filename)]);
  const beforeLiteral = (await stats(page)).paths.length;
  const literal = await run(page, { mounts: [mount(page, ["%2e%2e/acme.toml"], "/workspace", "/configs/")], sources: ["%2e%2e/acme.toml"] });
  expect(literal.error).toBe("FileNotFound");
  expect(await pathsSince(page, beforeLiteral)).toEqual(["/configs/%252e%252e/acme.toml"]);
});

test("empty and overlapping mounts, invalid cwd and outside requests fail before I/O", async ({ page }) => {
  const start = (await stats(page)).paths.length;
  expect((await run(page, { mounts: [] })).error).toBe("InvalidMount");
  for (const roots of [["/workspace", "/workspace"], ["/workspace", "/workspace/vendor"], ["/", "/workspace"]]) {
    expect((await run(page, { mounts: roots.map(root => mount(page, ["acme.toml"], root)) })).error).toBe("InvalidMount");
  }
  for (const cwd of ["relative", "/workspace/../outside", "/outside", "/workspace/"]) {
    expect(["InvalidPath", "OutsideMount"]).toContain((await run(page, { mounts: [mount(page)], cwd })).error);
  }
  for (const source of ["/outside/acme.toml", "/workspace2/acme.toml", "/workspace/../outside/acme.toml"]) {
    expect(["OutsideMount", "InvalidPath"]).toContain((await run(page, { mounts: [mount(page)], sources: ["/workspace/acme.toml", source] })).error);
  }
  expect(await pathsSince(page, start)).toEqual([]);
  const result = await run(page, { mounts: [mount(page), mount(page, ["acme.toml"], "/workspace2")], sources: ["/workspace/acme.toml", "/workspace2/acme.toml"], keys: ["server.host"] });
  expect(result.origins["server.host"]).toEqual(["/workspace2/acme.toml"]);
  const atRoot = await run(page, { mounts: [mount(page, ["acme.toml"], "/")], sources: ["acme.toml"], keys: ["server.host"] });
  expect(atRoot.origins["server.host"]).toEqual(["/acme.toml"]);
});

test("manifest listings are exact, sorted, finite and include inferred and empty directories", async ({ page }) => {
  const start = (await stats(page)).paths.length;
  const mounted = { ...mount(page, ["z.toml", "a/b.toml", "A.toml"]), manifest: { version: 1, files: ["z.toml", "a/b.toml", "A.toml"], directories: ["empty", "a"] } };
  for (const [path, listing] of [["/workspace", "A.toml,a,empty,z.toml"], ["/workspace/empty", ""], ["/workspace/absent", "missing-descendant"]]) {
    const result = await run(page, { mounts: [mounted], mode: "listing", path, keys: ["listing"] });
    expect(result.values.listing).toBe(listing);
  }
  const unlisted = await run(page, { mounts: [mounted], sources: ["/workspace/acme.toml"] });
  expect(unlisted).toEqual({ error: "FileNotFound", path: "/workspace/acme.toml" });
  expect(await pathsSince(page, start)).toEqual([]);
  const missing = await run(page, { mounts: [mount(page, ["missing.toml"])], sources: ["missing.toml"] });
  expect(missing).toEqual({ error: "FileNotFound", path: "/workspace/missing.toml" });
  expect(await pathsSince(page, start)).toEqual(["/missing.toml"]);
});

test("run inputs remain explicit and no ambient browser configuration is consulted", async ({ page }) => {
  const mounts = [mount(page, [])];
  const empty = await run(page, { mounts, mode: "context", keys: ["cwd", "platform"] });
  expect(empty.values).toEqual({ cwd: "/workspace", platform: "none" });
  await page.evaluate(() => { localStorage.setItem("APP_A", "ambient"); history.replaceState({}, "", "/?APP_A=ambient"); });
  const absent = await run(page, { mounts, mode: "context", keys: ["a"] });
  expect(absent.error).toBe("KeyNotFound");
  const explicit = await run(page, { mounts, mode: "context", cwd: "/workspace/src", platform: "Windows", vars: { APP_A: "1", HOME: "/outside", APP_HOME: "/outside" }, keys: ["cwd", "platform", "a"] });
  expect(explicit.values).toEqual({ cwd: "/workspace/src", platform: "Windows", a: "1" });
});

test("HTTP and transport failures are typed, redacted and never fall back to absence", async ({ page }) => {
  for (const [file, status] of [["forbidden.toml", 403], ["server-error.toml", 500]] as const) {
    const result = await run(page, { mounts: [mount(page, [file])], sources: [file] });
    expect(result).toEqual({ error: "Http", operation: "read", path: "/workspace/" + file, status });
    expect(JSON.stringify(result)).not.toContain("sensitive-response-body");
    expect(JSON.stringify(result)).not.toContain(new URL(page.url()).origin);
  }
  const start = (await stats(page)).paths.length;
  const redirect = await run(page, { mounts: [mount(page, ["redirect.toml"])], sources: ["redirect.toml"] });
  expect(redirect.error).toBe("Io");
  expect(await pathsSince(page, start)).toEqual(["/redirect.toml"]);
  const cors = await run(page, { mounts: [{ ...mount(page), base: process.env.LANDER_BROWSER_CROSS_URL + "/" }], sources: ["acme.toml"] });
  expect(cors.error).toBe("Io");
  await page.route("**/network.toml", route => route.abort("failed"));
  const network = await run(page, { mounts: [mount(page, ["network.toml"])], sources: ["network.toml"] });
  expect(network.error).toBe("Io");
  const disconnect = await run(page, { mounts: [mount(page, ["disconnect.toml"])], sources: ["disconnect.toml"] });
  expect(disconnect.error).toBe("Io");
  await page.context().addCookies([{ name: "credential", value: "secret", url: new URL(page.url()).origin }]);
  const cookie = await run(page, { mounts: [mount(page, ["cookie.toml"])], sources: ["cookie.toml"], keys: ["server.host"] });
  expect(cookie.values["server.host"]).toBe("no-cookie");
});

test("entry and request limits count unique entries and reject before backend reads", async ({ page }) => {
  const start = (await stats(page)).paths.length;
  for (const limits of [{ entries: 0 }, { bytes: -1 }, { requests: 0 }]) {
    expect((await run(page, { mounts: [mount(page)], limits })).error).toBe("InvalidMount");
  }
  const nested = mount(page, ["a/b.toml", "a/c.toml"]);
  expect((await run(page, { mounts: [nested], limits: { entries: 2 } })).limit).toBe("entries");
  const exact = await run(page, { mounts: [nested], mode: "listing", path: "/workspace", keys: ["listing"], limits: { entries: 3 } });
  expect(exact.values.listing).toBe("a");
  expect((await run(page, { mounts: [mount(page, Array.from({ length: 4097 }, (_, i) => i + ".toml"))] })).limit).toBe("entries");
  expect((await run(page, { mounts: [mount(page, ["acme.toml", "cookie.toml"])], sources: ["acme.toml", "cookie.toml"], limits: { requests: 1 } })).limit).toBe("requests");
  expect(await pathsSince(page, start)).toEqual([]);
  const cached = await run(page, { mounts: [mount(page)], sources: ["acme.toml", "acme.toml"], keys: ["server.host"], limits: { entries: 1, requests: 1 } });
  expect(cached.values["server.host"]).toBe("browser.example");
  expect(await pathsSince(page, start)).toEqual(["/acme.toml"]);
});

test("faulty providers cannot loop and each load receives a fresh snapshot", async ({ page }) => {
  const start = (await stats(page)).paths.length;
  expect((await run(page, { mounts: [mount(page)], mode: "repeat" })).error).toBe("Protocol");
  expect(await pathsSince(page, start)).toEqual(["/acme.toml"]);
  expect((await run(page, { mounts: [mount(page)], mode: "empty-need" })).error).toBe("Protocol");
  const fresh = await run(page, { mounts: [mount(page, ["fresh.toml"])], mode: "fresh", sources: ["fresh.toml"], keys: ["server.host"] });
  expect(fresh.first_after).toBe(fresh.values["server.host"]);
  expect(fresh.second).not.toBe(fresh.first_after);
});

test("real oversized and invalid UTF-8 streams stop upstream and never fetch the next file", async ({ page }) => {
  for (const [file, limits, error] of [
    ["stream/large.toml", { bytes: 128 }, "LimitExceeded"],
    ["stream/decoding.toml", {}, "Io"],
  ] as const) {
    const start = (await stats(page)).paths.length;
    const result = await run(page, { mounts: [mount(page, [file, "cookie.toml"])], sources: [file, "cookie.toml"], limits });
    expect(result.error).toBe(error);
    expect(result.values).toBeUndefined();
    await expect.poll(async () => (await stats(page)).stopped).toContain("/" + file);
    expect((await stats(page)).finished).not.toContain("/" + file);
    expect(await pathsSince(page, start)).toEqual(["/" + file]);
  }
});

test("abort stops active HTTP, removes listeners, and prevents further reads", async ({ page }) => {
  const file = "stream/abort.toml";
  const start = (await stats(page)).paths.length;
  const input = { mounts: [mount(page, [file, "cookie.toml"])], sources: [file, "cookie.toml"] };
  const result = await page.evaluate(async input => {
    const controller = new AbortController();
    const signal = controller.signal;
    const listeners = new Set<unknown>();
    const add = signal.addEventListener.bind(signal), remove = signal.removeEventListener.bind(signal);
    signal.addEventListener = ((type: string, listener: any, options: any) => { if (type === "abort") listeners.add(listener); add(type, listener, options); }) as any;
    signal.removeEventListener = ((type: string, listener: any, options: any) => { if (type === "abort") listeners.delete(listener); remove(type, listener, options); }) as any;
    (globalThis as any).testSignal = signal;
    const pending = (globalThis as any).landerRun(input);
    setTimeout(() => controller.abort(), 80);
    const result = await pending;
    return { result, listeners: listeners.size };
  }, input);
  expect(result.result.error).toBe("Aborted");
  expect(result.listeners).toBe(0);
  await expect.poll(async () => (await stats(page)).stopped).toContain("/" + file);
  expect(await pathsSince(page, start)).toEqual(["/" + file]);
  const before = (await stats(page)).paths.length;
  expect((await run(page, input)).error).toBe("Aborted");
  expect(await pathsSince(page, before)).toEqual([]);
});

test("core parse and binding errors retain their type, virtual path and position", async ({ page }) => {
  const parse = await run(page, { mounts: [mount(page, ["bad.toml"])], sources: ["bad.toml"] });
  expect(parse.error).toBe("Parse");
  expect(parse.path).toBe("/workspace/bad.toml");
  expect(parse).toEqual(await run(page, { mounts: [mount(page)], mode: "parse-reference" }));
  const positioned = await run(page, { mounts: [mount(page)], mode: "positioned-parse", sources: ["acme.toml"] });
  expect(positioned).toEqual({ error: "Parse", path: "/workspace/acme.toml", line: 7, column: 3 });
  const decode = await run(page, { mounts: [mount(page, ["wrong-type.toml"])], sources: ["wrong-type.toml"], bind: true });
  expect(decode.error).toBe("Decode");
  expect(decode.path).toBe("server.host");
  expect(decode.message).toContain("/workspace/wrong-type.toml");
});

test("stream cleanup preserves original errors across read, cancel and release failures", async ({ page }) => {
  const input = { mounts: [mount(page)], sources: ["acme.toml"], limits: { bytes: 4 } };
  for (const mode of ["wrong-length", "read-error", "decode-error", "cancel-error", "release-error", "known-size"] as const) {
    const observed = await page.evaluate(async ({ input, mode }) => {
      let cancels = 0, releases = 0, aborted = 0;
      const stream = new ReadableStream<Uint8Array>({
        start(controller) {
          if (mode === "read-error") controller.error(new Error("read-error-marker"));
          else controller.enqueue(mode === "decode-error" || mode === "release-error" ? new Uint8Array([0xff]) : new TextEncoder().encode("too much text"));
        },
        cancel() { cancels++; },
      });
      const original = stream.getReader.bind(stream);
      stream.getReader = (() => {
        const reader = original();
        const cancel = reader.cancel.bind(reader), release = reader.releaseLock.bind(reader);
        reader.cancel = async () => { await cancel(); if (mode === "cancel-error") throw new Error("cleanup-error-marker"); };
        reader.releaseLock = () => { releases++; release(); if (mode === "release-error") throw new Error("release-error-marker"); };
        return reader;
      }) as any;
      const saved = globalThis.fetch;
      globalThis.fetch = (async (_url: any, options: any) => {
        options.signal.addEventListener("abort", () => aborted++);
        return new Response(stream, { headers: { "Content-Length": mode === "known-size" ? "9999" : "1" } });
      }) as any;
      try { return { result: await (globalThis as any).landerRun(input), cancels, releases, aborted, locked: stream.locked }; }
      finally { globalThis.fetch = saved; }
    }, { input, mode });
    expect(observed.result.error, mode).toBe(["wrong-length", "cancel-error", "known-size"].includes(mode) ? "LimitExceeded" : "Io");
    expect(observed.locked, mode).toBe(false);
    expect(observed.aborted, mode).toBe(1);
    expect(observed.cancels, mode).toBe(mode === "read-error" ? 0 : 1);
    expect(observed.releases, mode).toBe(mode === "known-size" ? 0 : 1);
    expect(JSON.stringify(observed.result)).not.toContain("cleanup-error-marker");
  }
});

test("missing Web APIs fail explicitly without a storage or Node fallback", async ({ page }) => {
  const result = await page.evaluate(async input => {
    const saved = globalThis.fetch;
    try { (globalThis as any).fetch = undefined; return await (globalThis as any).landerRun(input); }
    finally { globalThis.fetch = saved; }
  }, { mounts: [mount(page)], sources: ["acme.toml"] });
  expect(result.error).toBe("Unsupported");
});

test("byte bounds use UTF-8 bytes across files and never return partial configuration", async ({ page }) => {
  const bytes = new TextEncoder().encode("[server]\nhost = 'é🌘'\nport = 8080\n").length;
  const input = { mounts: [mount(page, ["unicode.toml"])], sources: ["unicode.toml"], keys: ["server.host"] };
  expect((await run(page, { ...input, limits: { bytes } })).values["server.host"]).toBe("é🌘");
  expect((await run(page, { ...input, limits: { bytes: bytes - 1 } })).limit).toBe("bytes");
  const start = (await stats(page)).paths.length;
  const result = await run(page, {
    mounts: [mount(page, ["unicode.toml", "acme.toml", "cookie.toml"])],
    sources: ["unicode.toml", "acme.toml", "cookie.toml"], limits: { bytes: bytes + 1 },
  });
  expect(result).toEqual({ error: "LimitExceeded", operation: "read", path: "/workspace/acme.toml", limit: "bytes" });
  expect(await pathsSince(page, start)).toEqual(["/unicode.toml", "/acme.toml"]);
});

test("the documented headless consumer loads through the public package", async ({ page }) => {
  const base = new URL("/", page.url()).href;
  await page.goto("/example");
  expect(await page.evaluate(() => typeof (globalThis as any).loadHostedServer)).toBe("function");
  expect(await page.evaluate(base => (globalThis as any).loadHostedServer(base), base)).toBe("browser.example:9000");
});

test("wire Content-Length cannot bypass the limit on decoded response bytes", async ({ page }) => {
  const start = (await stats(page)).paths.length;
  const result = await run(page, {
    mounts: [mount(page, ["compressed.toml", "cookie.toml"])],
    sources: ["compressed.toml", "cookie.toml"], limits: { bytes: 128 },
  });
  expect(result).toEqual({ error: "LimitExceeded", operation: "read", path: "/workspace/compressed.toml", limit: "bytes" });
  expect(await pathsSince(page, start)).toEqual(["/compressed.toml"]);
});
