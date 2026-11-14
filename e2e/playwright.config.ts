import { defineConfig, devices } from '@playwright/test';

/**
 * Read-only smoke. Default origin is the local Flutter web build in CI.
 * Tenant path is always navigated explicitly as `/adeco` (absolute `/` would
 * drop the tenant segment when BASE_URL includes a path).
 *
 * After deploy:
 *   BASE_ORIGIN=https://www.data.sw-point.com TENANT_PATH=/adeco npx playwright test
 *
 * Flutter exposes flt-semantics only when the initial URL has ?semantics=1
 * (see withAutomationSemantics in helpers/flutter.ts). Do not rely on
 * always-on ensureSemantics in production builds.
 *
 * macOS Retina hosts: force DPR=1 via launch args so Flutter web Semantics
 * hit-targets stay inside the Playwright viewport (avoids "outside of the
 * viewport" on locator.click).
 */
const baseOrigin =
  process.env.BASE_ORIGIN?.replace(/\/$/, '') || 'http://127.0.0.1:4173';

export const TENANT_PATH = process.env.TENANT_PATH || '/adeco';

/** Explicit desktop viewport — do not rely on host display metrics. */
const VIEWPORT = { width: 1440, height: 900 } as const;

const chromiumLaunchArgs = [
  '--force-device-scale-factor=1',
  '--high-dpi-support=1',
  `--window-size=${VIEWPORT.width},${VIEWPORT.height}`,
  '--disable-dev-shm-usage',
];

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
    viewport: { ...VIEWPORT },
    deviceScaleFactor: 1,
    isMobile: false,
    hasTouch: false,
    launchOptions: {
      args: chromiumLaunchArgs,
    },
  },
  projects: [
    {
      name: 'chromium-dpr1',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { ...VIEWPORT },
        deviceScaleFactor: 1,
        isMobile: false,
        hasTouch: false,
        launchOptions: {
          args: chromiumLaunchArgs,
        },
      },
    },
    {
      // Hit-test under Retina-like DPR (natural locator.click, no bypass).
      // Scoped so login smoke stays on DPR 1 in CI.
      name: 'chromium-dpr2',
      testMatch: /sellout-semantics-clickable\.spec\.ts/,
      use: {
        ...devices['Desktop Chrome'],
        viewport: { ...VIEWPORT },
        deviceScaleFactor: 2,
        isMobile: false,
        hasTouch: false,
        launchOptions: {
          args: [
            '--force-device-scale-factor=2',
            '--high-dpi-support=1',
            `--window-size=${VIEWPORT.width},${VIEWPORT.height}`,
            '--disable-dev-shm-usage',
          ],
        },
      },
    },
  ],
});
