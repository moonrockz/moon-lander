import { expect, test } from "@playwright/test";

test("profile controls and overlays use existing mounts with no Node globals", async ({ page }) => {
  await page.goto("/");
  const start = (await (await page.request.get("/stats")).json()).paths.length;
  const result = await page.evaluate(async base => (globalThis as any).landerRun({
    mounts: [{ root: "/workspace", base, manifest: { version: 1, files: ["acme.toml", "acme.profile.metrics.toml", "acme.profile.unused.toml"] } }],
    cwd: "/workspace", sources: [{ conventions: "acme", workspace: 0, profiles: true }],
    keys: ["server.host"], profile_state: true,
  }), new URL("/profiles/", page.url()).href);
  expect(result.error).toBeUndefined();
  expect(result.profiles).toEqual(["common", "production", "metrics"]);
  expect(result.values["server.host"]).toBe("profile");
  expect(result.origins["server.host"]).toEqual(["/workspace/acme.profile.metrics.toml"]);
  const paths = (await (await page.request.get("/stats")).json()).paths.slice(start);
  expect(paths).toContain("/profiles/acme.profile.metrics.toml");
  expect(paths).not.toContain("/profiles/acme.profile.unused.toml");
  expect(await page.evaluate(() => [typeof (globalThis as any).process, typeof (globalThis as any).require, typeof (globalThis as any).Bun])).toEqual(["undefined", "undefined", "undefined"]);
});

test("disabled profiles avoid overlays and selected unreadable files fail", async ({ page }) => {
  await page.goto("/");
  const base = new URL("/profiles/", page.url()).href;
  const invoke = (selection: string | false) => page.evaluate(async ({ base, selection }) => (globalThis as any).landerRun({
    mounts: [{ root: "/workspace", base, manifest: { version: 1, files: ["acme.toml", "acme.profile.locked.toml"] } }],
    cwd: "/workspace", sources: [{ conventions: "acme", workspace: 0, profiles: true, selection }],
    keys: ["server.host"], profile_state: true,
  }), { base, selection });
  const disabled = await invoke(false);
  expect(disabled.error).toBeUndefined();
  expect(disabled.profiles).toEqual([]);
  expect(disabled.values["server.host"]).toBe("base");
  const unreadable = await invoke("locked");
  expect(unreadable).toEqual({ error: "Http", operation: "read", path: "/workspace/acme.profile.locked.toml", status: 403 });
  expect(JSON.stringify(unreadable)).not.toContain("unreadable selected profile");
});
