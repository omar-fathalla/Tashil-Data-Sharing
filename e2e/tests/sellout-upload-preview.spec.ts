import path from 'node:path';
import { expect, test } from '@playwright/test';
import { TENANT_PATH } from '../playwright.config';
import { byTestId, clickSemantics, waitForFlutter } from '../helpers/flutter';

/**
 * Authenticated Sell-Out upload → dry-run preview (no commit).
 *
 * Requires:
 *   E2E_EMAIL / E2E_PASSWORD  (company-manager account for /adeco)
 *   BASE_ORIGIN               (defaults to local serve; use prod with care)
 *
 * Uses the persistent `#tashil-file-input` + `setInputFiles` (not filechooser).
 * Cancels the commit dialog so nothing is written.
 */
const FIXTURE = path.join(
  __dirname,
  '..',
  'fixtures',
  'sellout-qa-preview.xlsx',
);

const email = process.env.E2E_EMAIL?.trim() ?? '';
const password = process.env.E2E_PASSWORD?.trim() ?? '';
const hasCreds = email.length > 0 && password.length > 0;

const MAPPING_SOURCES = new Set(['ai', 'deterministic', 'cache', 'mock']);

test.describe('Sell-Out upload preview (dry-run)', () => {
  test('semantics arm + setInputFiles → mapping_source metadata, no commit', async ({
    page,
  }) => {
    test.skip(
      !hasCreds,
      'Set E2E_EMAIL and E2E_PASSWORD for authenticated upload e2e',
    );
    test.setTimeout(180_000);

    let uploadPayload: Record<string, unknown> | null = null;
    let commitAttempted = false;

    await page.route('**/api/v1/ingest/upload**', async (route) => {
      const req = route.request();
      const url = new URL(req.url());
      // Belt-and-suspenders: force preview even if a client omits dry_run.
      url.searchParams.set('dry_run', 'true');
      const response = await route.fetch({ url: url.toString() });
      const text = await response.text();
      try {
        uploadPayload = JSON.parse(text) as Record<string, unknown>;
      } catch {
        uploadPayload = { _raw: text };
      }
      await route.fulfill({
        status: response.status(),
        headers: response.headers(),
        body: text,
      });
    });

    await page.route('**/api/v1/ingest/commit**', async (route) => {
      commitAttempted = true;
      await route.abort('failed');
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
    await clickSemantics(page, 'nav-sell-out');

    const fileInput = page.locator('#tashil-file-input');
    await expect(fileInput).toBeAttached({ timeout: 60_000 });

    // User-activation path: semantics click arms the persistent input.
    await clickSemantics(page, 'sellout-upload-button');
    await expect(fileInput).toHaveAttribute('data-armed', 'true', {
      timeout: 20_000,
    });

    // Prefer setInputFiles over waitForEvent('filechooser').
    await fileInput.setInputFiles(FIXTURE);

    await expect
      .poll(() => uploadPayload != null, { timeout: 120_000 })
      .toBe(true);

    expect(uploadPayload).not.toBeNull();
    const source = String(uploadPayload!['mapping_source'] ?? '');
    expect(
      MAPPING_SOURCES.has(source),
      `mapping_source should be one of ${[...MAPPING_SOURCES].join('|')}, got "${source}"`,
    ).toBe(true);

    const model = String(
      uploadPayload!['ai_model_used'] ?? uploadPayload!['model'] ?? '',
    );
    // Honest metadata: model may be empty for deterministic/mock; source is required.
    if (source === 'ai' || source === 'cache') {
      expect(model.length, 'ai/cache mapping should report ai_model_used').toBeGreaterThan(0);
    }

    // Cancel commit so the run stays non-destructive.
    const cancel = page.locator(byTestId('upload-commit-cancel'));
    if (await cancel.count()) {
      await cancel.first().click({ timeout: 30_000 });
    }

    expect(commitAttempted, 'commit must not succeed during preview e2e').toBe(
      false,
    );
  });

  test('hidden file input is mounted before login interaction', async ({
    page,
  }) => {
    await page.goto(TENANT_PATH, { waitUntil: 'domcontentloaded' });
    await waitForFlutter(page);
    await expect(page.locator('#tashil-file-input')).toBeAttached({
      timeout: 60_000,
    });
    await expect(page.locator('#tashil-file-input')).toHaveAttribute(
      'data-testid',
      'tashil-file-input',
    );
  });
});
