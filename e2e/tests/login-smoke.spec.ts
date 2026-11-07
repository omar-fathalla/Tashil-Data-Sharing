import { expect, test } from '@playwright/test';

/**
 * Read-only smoke: load the tenant shell and assert login Semantics ids exist.
 * Does not type credentials or click submit.
 *
 * Locators target Flutter web's accessibility tree attribute
 * `flt-semantics-identifier` (requires ensureSemantics at app startup).
 */
const LOGIN_IDS = ['login-email', 'login-password', 'login-submit'] as const;

function byTestId(id: string) {
  return `[flt-semantics-identifier="${id}"]`;
}

test.describe('Flutter web login Semantics smoke', () => {
  test('login identifiers are present in the accessibility tree', async ({
    page,
  }) => {
    await page.goto('/', { waitUntil: 'domcontentloaded' });

    // Flutter web boots the canvas first; semantics nodes appear after first frame.
    await page.waitForSelector('flutter-view, flt-glass-pane, canvas', {
      timeout: 60_000,
    });

    for (const id of LOGIN_IDS) {
      const locator = page.locator(byTestId(id));
      await expect(
        locator.first(),
        `expected Semantics identifier "${id}" (flt-semantics-identifier)`,
      ).toBeVisible({ timeout: 60_000 });
    }

    // Guard: at least one flt-semantics node exists (tree enabled).
    await expect(page.locator('flt-semantics').first()).toBeAttached({
      timeout: 10_000,
    });
  });
});
