import { defineConfig, devices } from '@playwright/test';

/**
 * Read-only smoke. Default origin is the local Flutter web build in CI.
 * Tenant path is always navigated explicitly as `/adeco` (absolute `/` would
 * drop the tenant segment when BASE_URL includes a path).
 *
 * After deploy:
 *   BASE_ORIGIN=https://www.data.sw-point.com TENANT_PATH=/adeco npx playwright test
 */
const baseOrigin =
  process.env.BASE_ORIGIN?.replace(/\/$/, '') || 'http://127.0.0.1:4173';

export const TENANT_PATH = process.env.TENANT_PATH || '/adeco';

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
    baseURL: baseOrigin,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    // Smoke never completes a successful login or mutates prod data.
    navigationTimeout: 60_000,
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
