import { expect, test } from '@playwright/test';
import { TENANT_PATH } from '../playwright.config';
import {
  assertSemanticsNotDoubleScaled,
  byTestId,
  clickSemantics,
  expectClickableSemanticsButton,
  probeSemantics,
  typeIntoSemanticsField,
  waitForFlutter,
  withAutomationSemantics,
} from '../helpers/flutter';

/**
 * Locks Sell-Out Targets toolbar semantics after the #232 redesign:
 * Add + Export only (upload/template hidden). Archive upload
 * (`sellout-upload-button`) stays on the Uploaded Files tab — not here.
 *
 * Skips when E2E_EMAIL / E2E_PASSWORD are unset (CI login smoke has no creds).
 */
const email = process.env.E2E_EMAIL?.trim() ?? '';
const password = process.env.E2E_PASSWORD?.trim() ?? '';
const hasCreds = email.length > 0 && password.length > 0;

test.describe('Sell-Out Targets toolbar semantics', () => {
  test('add + export ids present; upload/template absent on Targets', async ({
    page,
  }) => {
    test.skip(
      !hasCreds,
      'Set E2E_EMAIL and E2E_PASSWORD for authenticated Targets toolbar e2e',
    );
    test.setTimeout(180_000);

    await page.goto(withAutomationSemantics(TENANT_PATH), {
      waitUntil: 'domcontentloaded',
    });
    await waitForFlutter(page);

    await typeIntoSemanticsField(page, 'login-email', email);
    await typeIntoSemanticsField(page, 'login-password', password);
    await clickSemantics(page, 'login-submit');

    await expect(page.locator(byTestId('nav-sell-out'))).toBeVisible({
      timeout: 90_000,
    });
    await clickSemantics(page, 'nav-sell-out');

    await expect(page.locator(byTestId('sellout-targets-tab'))).toBeVisible({
      timeout: 60_000,
    });
    await clickSemantics(page, 'sellout-targets-tab');

    await expect(page.locator(byTestId('sellout-targets-add'))).toBeVisible({
      timeout: 60_000,
    });
    await expect(page.locator(byTestId('sellout-targets-export'))).toBeVisible({
      timeout: 30_000,
    });
    await assertSemanticsNotDoubleScaled(page, 'sellout-targets-add');
    await assertSemanticsNotDoubleScaled(page, 'sellout-targets-export');

    const addProbe = await probeSemantics(page, 'sellout-targets-add');
    expect(addProbe, 'missing sellout-targets-add').not.toBeNull();
    expect(addProbe!.role).toBe('button');
    await expectClickableSemanticsButton(page, 'sellout-targets-add');

    // Redesign: Targets toolbar must not expose archive/target upload controls.
    await expect(page.locator(byTestId('sellout-upload-button'))).toHaveCount(0);
    await expect(page.getByText('رفع ملف المستهدفات')).toHaveCount(0);
    await expect(page.getByText('تنزيل القالب')).toHaveCount(0);
  });
});
