import { test as base } from "@playwright/test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

/**
 * Tests that use the origin private file system run in a persistent profile.
 * WebKit rejects navigator.storage.getDirectory() with UnknownError in an
 * ephemeral Playwright context, as in private browsing. The profile directory
 * is new for each test and is removed afterwards.
 */
export const test = base.extend({
  context: async ({ playwright, browserName, baseURL }, use) => {
    const dir = await mkdtemp(join(tmpdir(), "lander-opfs-"));
    const context = await playwright[browserName].launchPersistentContext(dir, { baseURL, headless: true });
    try { await use(context); } finally {
      await context.close();
      await rm(dir, { recursive: true, force: true });
    }
  },
  page: async ({ context }, use) => { await use(context.pages()[0] ?? await context.newPage()); },
});
export { expect } from "@playwright/test";
