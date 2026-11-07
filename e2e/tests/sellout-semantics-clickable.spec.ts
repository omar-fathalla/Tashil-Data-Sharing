import { expect, test } from '@playwright/test';
import { TENANT_PATH } from '../playwright.config';
import {
  assertSemanticsNotDoubleScaled,
  byTestId,
  clickSemantics,
  expectClickableSemanticsButton,
  fileInputLocator,
  probeSemantics,
  waitForFlutter,
} from '../helpers/flutter';

/**
 * Asserts archive delete / confirm / upload semantics are real buttons and
 * clickable (not role=cell intercepted by flutter-view). Cancels delete so
 * the run stays non-destructive.
 *
 * Requires E2E_EMAIL / E2E_PASSWORD (company-manager on /adeco).
 */
const email = process.env.E2E_EMAIL?.trim() ?? '';
const password = process.env.E2E_PASSWORD?.trim() ?? '';
const hasCreds = email.length > 0 && password.length > 0;

async function expectButtonRole(page: import('@playwright/test').Page, id: string) {
  const probe = await probeSemantics(page, id);
  expect(probe, `missing ${id}`).not.toBeNull();
  expect(
    probe!.role,
    `${id} must be role=button (got ${probe!.role})`,
  ).toBe('button');
  expect(probe!.pointerEvents).not.toBe('none');
  return probe!;
}

test.describe('Sell-Out semantics clickability', () => {
  test('upload + file-delete + delete dialog buttons are tappable', async ({
    page,
  }) => {
    test.skip(
      !hasCreds,
      'Set E2E_EMAIL and E2E_PASSWORD for authenticated semantics e2e',
    );
    test.setTimeout(180_000);

    // Never allow a real archive delete during this smoke.
    await page.route('**/api/v1/ingest/archive/**', async (route) => {
      if (route.request().method() === 'DELETE') {
        await route.abort('failed');
        return;
      }
      await route.continue();
    });

    await page.goto(TENANT_PATH, { waitUntil: 'domcontentloaded' });
    await waitForFlutter(page);

    await clickSemantics(page, 'login-email');
    await page.keyboard.type(email, { delay: 15 });
    await clickSemantics(page, 'login-password');
    await page.keyboard.type(password, { delay: 15 });
    await clickSemantics(page, 'login-submit');

    await expect(page.locator(byTestId('nav-sell-out'))).toBeVisible({
      timeout: 90_000,
    });
    await assertSemanticsNotDoubleScaled(page, 'nav-sell-out');
    await clickSemantics(page, 'nav-sell-out');

    // --- Upload button: role=button, click arms #tashil-file-input ---
    await expect(page.locator(byTestId('sellout-upload-button'))).toBeVisible({
      timeout: 60_000,
    });
    await assertSemanticsNotDoubleScaled(page, 'sellout-upload-button');
    await expectButtonRole(page, 'sellout-upload-button');
    await expectClickableSemanticsButton(page, 'sellout-upload-button');
    await expect(fileInputLocator(page)).toHaveAttribute('data-armed', 'true', {
      timeout: 20_000,
    });

    // Open Uploaded Files tab for archive rows.
    const filesTab = page.locator(byTestId('sellout-uploaded-files'));
    if (await filesTab.count()) {
      await clickSemantics(page, 'sellout-uploaded-files');
    }

    const deleteBtn = page
      .locator('[flt-semantics-identifier^="file-delete-"]')
      .first();
    test.skip(
      (await deleteBtn.count()) === 0,
      'No archived Sell-Out files — cannot exercise file-delete-*',
    );

    const deleteId = await deleteBtn.getAttribute('flt-semantics-identifier');
    expect(deleteId).toMatch(/^file-delete-/);
    await assertSemanticsNotDoubleScaled(page, deleteId!);
    await expectButtonRole(page, deleteId!);

    // Click delete → dialog; assert confirm is a button; click cancel only.
    await expectClickableSemanticsButton(page, deleteId!);
    await expect(page.locator(byTestId('delete-confirm'))).toBeAttached({
      timeout: 30_000,
    });
    await expect(page.locator(byTestId('delete-cancel'))).toBeAttached({
      timeout: 5_000,
    });
    await expectButtonRole(page, 'delete-confirm');
    await expectButtonRole(page, 'delete-cancel');
    await expectClickableSemanticsButton(page, 'delete-cancel');

    await expect(page.locator(byTestId('delete-confirm'))).toHaveCount(0, {
      timeout: 15_000,
    });
  });
});
