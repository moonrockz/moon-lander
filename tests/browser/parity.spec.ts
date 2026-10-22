import { expect, test } from "@playwright/test";

test("browser js gives the same observation as wasm, wasm-gc, js on Node and native", async ({ page }) => {
  await page.goto("/");
  expect(await page.evaluate(() => typeof (globalThis as any).landerParity)).toBe("function");
  // The task script made this reference on all four targets from the same checkout.
  const reference = (await (await page.request.get(new URL("/parity-reference.txt", page.url()).href)).text()).trimEnd();
  const observed = await page.evaluate(() => (globalThis as any).landerParity());
  // The revision is a digest of every case input, so both sides used the same fixture.
  expect(observed.split("\n")[0]).toMatch(/^fixture [0-9a-f]+$/);
  expect(observed.split("\n")[0]).toBe(reference.split("\n")[0]);
  // Values, provenance, reports in source order, the parse error and the binding error.
  for (const marker of ["case complete", "case parse", "error Parse(", "case binding", "error Decode("]) {
    expect(observed).toContain(marker);
  }
  expect(observed).toBe(reference);
});
