import path from 'node:path';
import { expect, test } from '@playwright/test';
import { TENANT_PATH } from '../playwright.config';
import {
  byTestId,
  clickSemantics,
  fileInputLocator,
  typeIntoSemanticsField,
  waitForFlutter,
} from '../helpers/flutter';

/**
 * Authenticated Sell-Out upload → dry-run preview (no commit).
 *
 * Requires E2E_EMAIL / E2E_PASSWORD. Against production, mapping_source=mock
 * is rejected.
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

const baseOrigin = (process.env.BASE_ORIGIN || '').replace(/\/$/, '');
const isProductionOrigin = /data\.sw-point\.com$/i.test(
  baseOrigin.replace(/^https?:\/\//, '').split('/')[0] ?? '',
);

const HONEST_SOURCES = new Set(['ai', 'deterministic', 'cache']);

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
    let uploadRequestUrl = '';
    let commitAttempted = false;

    // Observe only — do NOT rewrite dry_run (client must send it naturally).
    await page.route('**/api/v1/ingest/upload**', async (route) => {
      const req = route.request();
      uploadRequestUrl = req.url();
      const response = await route.fetch();
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

    await typeIntoSemanticsField(page, 'login-email', email);
    await typeIntoSemanticsField(page, 'login-password', password);

    const loginReq = page.waitForRequest(
      (r) => r.url().includes('/api/') && r.method() === 'POST',
      { timeout: 60_000 },
    ).catch(() => null);
    await clickSemantics(page, 'login-submit');
    const seenLogin = await loginReq;
    if (seenLogin) {
      const headers = seenLogin.headers();
      const tenant =
        headers['x-tenant-id'] || headers['X-Tenant-ID'] || '';
      // Tenant path is /adeco — header may be adeco or tenant-adeco.
      expect(tenant.toLowerCase()).toMatch(/adeco/);
    }

    await expect(page.locator(byTestId('nav-sell-out'))).toBeVisible({
      timeout: 90_000,
    });
    await clickSemantics(page, 'nav-sell-out');

    const fileInput = fileInputLocator(page);
    await expect(fileInput).toBeAttached({ timeout: 60_000 });

    await clickSemantics(page, 'sellout-upload-button');
    await expect(fileInput).toHaveAttribute('data-armed', 'true', {
      timeout: 20_000,
    });
    await fileInput.setInputFiles(FIXTURE);

    await expect
      .poll(() => uploadPayload != null, { timeout: 120_000 })
      .toBe(true);

    expect(
      uploadRequestUrl,
      'client must send dry_run=true without route rewriting',
    ).toMatch(/[?&]dry_run=true\b/);

    expect(uploadPayload).not.toBeNull();
    const source = String(uploadPayload!['mapping_source'] ?? '');
    expect(
      HONEST_SOURCES.has(source) || (!isProductionOrigin && source === 'mock'),
      isProductionOrigin
        ? `production preview must not be mapping_source=mock (got "${source}")`
        : `mapping_source should be honest (got "${source}")`,
    ).toBe(true);
    if (isProductionOrigin) {
      expect(source).not.toBe('mock');
    }

    expect(uploadPayload!['is_staged'] === true || uploadPayload!['is_staged'] === 'true').toBe(
      true,
    );
    const committed = uploadPayload!['is_committed'];
    expect(committed === true || committed === 'true').toBe(false);

    if (source === 'ai' || source === 'cache') {
      const model = String(uploadPayload!['ai_model_used'] ?? '');
      expect(model.length).toBeGreaterThan(0);
    }

    // Preview dialog: cancel so nothing commits.
    const cancel = page.locator(byTestId('upload-commit-cancel'));
    await expect(cancel).toBeVisible({ timeout: 60_000 });
    await cancel.click({ timeout: 30_000 });

    expect(commitAttempted).toBe(false);
  });

  test('hidden file input is mounted before login interaction', async ({
    page,
  }) => {
    await page.goto(TENANT_PATH, { waitUntil: 'domcontentloaded' });
    await waitForFlutter(page);
    await expect(fileInputLocator(page)).toBeAttached({ timeout: 60_000 });
    await expect(fileInputLocator(page)).toHaveAttribute(
      'data-testid',
      'tashil-file-input',
    );
  });
});
