import { defineConfig, devices } from '@playwright/test';

/**
 * Read-only smoke. Default BASE_URL is the local Flutter web build served in CI.
 * After deploy, point at production with:
 *   BASE_URL=https://www.data.sw-point.com/adeco npx playwright test
 */
const baseURL =
  process.env.BASE_URL?.replace(/\/$/, '') || 'http://127.0.0.1:4173/adeco';

export default defineConfig({
  testDir: './tests',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  timeout: 90_000,
  expect: { timeout: 45_000 },
  reporter: process.env.CI ? [['github'], ['list']] : 'list',
  use: {
    baseURL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    // Smoke never logs in or mutates data.
    navigationTimeout: 60_000,
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
