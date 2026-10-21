import { expect, test } from "@playwright/test";

test("hosted TOML, override, binding, origin, and no Node shims", async ({ page, browser }) => {
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  const files: string[] = [];
  page.on("request", request => { if (request.url().endsWith(".toml")) files.push(request.url()); });
  await page.goto("/");
  expect(errors).toEqual([]);
  expect(await page.evaluate(() => typeof (globalThis as any).landerProbe)).toBe("function");
  expect(await page.evaluate(() => [typeof (globalThis as any).process, typeof (globalThis as any).require, typeof (globalThis as any).Bun])).toEqual(["undefined", "undefined", "undefined"]);
  const result = await page.evaluate(() => (globalThis as any).landerProbe("/acme.toml"));
  expect(result).toBe("browser.example:9000 from /workspace/acme.toml");
  expect(files).toHaveLength(1);
  expect(errors).toEqual([]);
  console.log(`Engine ${test.info().project.name}: ${browser.version()}`);
  if (process.env.LANDER_BROWSER_FAIL_ASSERTION === "1") expect(result).toBe("deliberate failure");
});

test("boundary and core failures reject through the promise bridge", async ({ page }) => {
  await page.goto("/");
  expect(await page.evaluate(() => typeof (globalThis as any).landerProbe)).toBe("function");
  for (const [path, expected] of [["/missing.toml", "HTTP 404"], ["/bad.toml", "/workspace/bad.toml"], ["/wrong-type.toml", "server.host"]]) {
    const error = await page.evaluate(async path => {
      try { await (globalThis as any).landerProbe(path); return "unexpected success"; }
      catch (error) { return String(error); }
    }, path);
    expect(error).toContain(expected);
  }
});
