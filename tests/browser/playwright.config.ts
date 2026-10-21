import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: ".",
  testMatch: "feasibility.spec.ts",
  outputDir: "../../_build/browser/results",
  workers: 1,
  retries: 0,
  timeout: 15_000,
  globalTimeout: 120_000,
  reporter: "list",
  use: { baseURL: process.env.LANDER_BROWSER_URL, headless: true },
  projects: ["chromium", "firefox", "webkit"].map(browserName => ({
    name: browserName,
    use: { browserName: browserName as "chromium" | "firefox" | "webkit" },
  })),
});
