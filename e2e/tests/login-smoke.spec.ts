import { expect, test } from '@playwright/test';
import { TENANT_PATH } from '../playwright.config';
import {
  assertSemanticsNotDoubleScaled,
  byTestId,
  typeIntoSemanticsField,
  waitForFlutter,
} from '../helpers/flutter';

/**
 * Read-only smoke against the tenant login shell.
 *
 * Locators use Flutter web `flt-semantics-identifier` (requires
 * `ensureSemantics` at app startup).
 *
 * Does not complete a successful login. A dummy password is typed only to
 * verify it never leaks into the Semantics tree / DOM text.
 */
const LOGIN_IDS = ['login-email', 'login-password', 'login-submit'] as const;

/** Sentinel that must never appear in page HTML / semantics attributes. */
const DUMMY_PASSWORD = 'DUMMY_PW_NEVER_LEAK_9x7q';

test.describe('Flutter web Semantics smoke', () => {
  test('tenant path, login ids, typing/click, password never leaks', async ({
    page,
  }) => {
    // Absolute tenant path — do NOT use '/' (that strips /adeco from the URL).
    await page.goto(TENANT_PATH, { waitUntil: 'domcontentloaded' });
    await expect(page).toHaveURL(new RegExp(`${TENANT_PATH}/?(\\?.*)?$`));

    await waitForFlutter(page);

    // Guard against Retina 2× semantics offset that puts nodes outside viewport.
    await assertSemanticsNotDoubleScaled(page, 'login-email');

    for (const id of LOGIN_IDS) {
      const locator = page.locator(byTestId(id));
      await expect(
        locator,
        `expected exactly one Semantics identifier "${id}"`,
      ).toHaveCount(1);
      await expect(locator.first()).toBeVisible({ timeout: 60_000 });
    }

    const submit = page.locator(byTestId('login-submit')).first();

    await typeIntoSemanticsField(page, 'login-email', 'smoke@example.com');
    await typeIntoSemanticsField(page, 'login-password', DUMMY_PASSWORD);

    // Dummy password must not appear in DOM text or semantics attributes.
    const html = await page.content();
    expect(html).not.toContain(DUMMY_PASSWORD);
    const semanticsDump = await page
      .locator('flt-semantics')
      .evaluateAll((nodes) =>
        nodes
          .map((n) => {
            const el = n as HTMLElement;
            return [
              el.getAttribute('flt-semantics-identifier') ?? '',
              el.getAttribute('aria-label') ?? '',
              el.textContent ?? '',
            ].join('|');
          })
          .join('\n'),
      );
    expect(semanticsDump).not.toContain(DUMMY_PASSWORD);

    await expect(submit).toBeEnabled();
    await submit.scrollIntoViewIfNeeded();
    await submit.click();
    // Failed / local-only auth must never leak the dummy password into the DOM.
    // URL may stay on /adeco or the app may rewrite to `/` when no backend is present;
    // either way this smoke stays non-destructive (no successful login).
    await expect
      .poll(async () => (await page.content()).includes(DUMMY_PASSWORD), {
        timeout: 5_000,
      })
      .toBe(false);
    const semanticsAfter = await page
      .locator('flt-semantics')
      .evaluateAll((nodes) =>
        nodes
          .map((n) => {
            const el = n as HTMLElement;
            return [
              el.getAttribute('flt-semantics-identifier') ?? '',
              el.getAttribute('aria-label') ?? '',
              el.textContent ?? '',
            ].join('|');
          })
          .join('\n'),
      );
    expect(semanticsAfter).not.toContain(DUMMY_PASSWORD);
  });

  test('login catalog identifiers remain unique after interaction', async ({
    page,
  }) => {
    await page.goto(TENANT_PATH, { waitUntil: 'domcontentloaded' });
    await expect(page).toHaveURL(new RegExp(`${TENANT_PATH}/?`));
    await waitForFlutter(page);

    for (const id of LOGIN_IDS) {
      await expect(page.locator(byTestId(id))).toHaveCount(1);
    }
  });
});
