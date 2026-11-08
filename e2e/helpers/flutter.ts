import { expect, type Locator, type Page } from '@playwright/test';

/** Locator for a Flutter web Semantics identifier. */
export function byTestId(id: string) {
  return `[flt-semantics-identifier="${id}"]`;
}

/** Wait until Flutter has painted and exposed at least one semantics node. */
export async function waitForFlutter(page: Page) {
  await page.waitForSelector('flutter-view, flt-glass-pane, canvas', {
    timeout: 60_000,
  });
  await expect(page.locator('flt-semantics').first()).toBeAttached({
    timeout: 60_000,
  });
}

export type SemanticsProbe = {
  id: string;
  role: string | null;
  x: number;
  y: number;
  w: number;
  h: number;
  dpr: number;
  pointerEvents: string;
};

/** Read geometry + ARIA role for a semantics id (for offset / role asserts). */
export async function probeSemantics(
  page: Page,
  id: string,
): Promise<SemanticsProbe | null> {
  return page.evaluate((semId) => {
    const el = document.querySelector(
      `[flt-semantics-identifier="${semId}"]`,
    ) as HTMLElement | null;
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return {
      id: semId,
      role: el.getAttribute('role'),
      x: r.x,
      y: r.y,
      w: r.width,
      h: r.height,
      dpr: window.devicePixelRatio,
      pointerEvents: getComputedStyle(el).pointerEvents,
    };
  }, id);
}

/**
 * Natural Playwright click — no evaluate/force fallback.
 * Hit-testing must succeed at the configured deviceScaleFactor.
 */
export async function clickSemantics(page: Page, id: string) {
  const locator = page.locator(byTestId(id)).first();
  await expect(locator).toBeVisible({ timeout: 60_000 });
  await locator.click({ timeout: 30_000 });
}

/**
 * Assert role=button and that a natural locator.click succeeds (validates
 * hit-testing / DPR alignment — no HTMLElement.click bypass).
 */
export async function expectClickableSemanticsButton(page: Page, id: string) {
  const locator = page.locator(byTestId(id)).first();
  await expect(locator).toBeAttached({ timeout: 60_000 });

  const probe = await probeSemantics(page, id);
  expect(probe, `missing semantics node ${id}`).not.toBeNull();
  expect(
    probe!.role,
    `${id} must be role=button (got ${probe!.role}; cell means onTap was missing)`,
  ).toBe('button');
  expect(
    probe!.pointerEvents,
    `${id} must accept pointer events`,
  ).not.toBe('none');

  await locator.click({ timeout: 30_000 });
  return probe!;
}

/**
 * Soft guard against ~2× semantics offset: node center should sit inside the
 * viewport (and not near 2× a typical layout x for on-screen controls).
 */
export async function assertSemanticsNotDoubleScaled(
  page: Page,
  id: string,
  opts: { maxXRatioOfViewport?: number } = {},
) {
  const maxRatio = opts.maxXRatioOfViewport ?? 1.05;
  const probe = await probeSemantics(page, id);
  expect(probe, `missing ${id} for offset check`).not.toBeNull();
  const vw = page.viewportSize()?.width ?? 1280;
  const vh = page.viewportSize()?.height ?? 720;
  expect(
    probe!.x,
    `${id} x=${probe!.x} looks past viewport (possible 2× semantics offset; dpr=${probe!.dpr})`,
  ).toBeLessThan(vw * maxRatio);
  expect(probe!.y).toBeGreaterThanOrEqual(-8);
  expect(probe!.y + probe!.h).toBeLessThanOrEqual(vh * maxRatio + 8);
  return probe!;
}

export function fileInputLocator(page: Page): Locator {
  return page.locator('#tashil-file-input');
}

/** Verified login typing: wait for focus, then ~40ms key delay. */
export async function typeIntoSemanticsField(
  page: Page,
  id: string,
  text: string,
) {
  await clickSemantics(page, id);
  const field = page.locator(byTestId(id)).first();
  await expect(field).toBeFocused({ timeout: 10_000 }).catch(async () => {
    // Flutter web may put focus on an inner input; wait briefly then type.
    await page.waitForTimeout(250);
  });
  await page.waitForTimeout(250);
  await page.keyboard.type(text, { delay: 40 });
}
