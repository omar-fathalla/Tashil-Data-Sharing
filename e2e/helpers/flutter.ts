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
 * Assert a semantics node is an interactive button (not a DataTable cell)
 * and invoke it via the DOM node so a ~DPR offset cannot redirect the click
 * onto `flutter-view`.
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

  // Prefer element.click() on the flt-semantics node — this fires the
  // semantics onTap handler even when the box is slightly offset from paint.
  await locator.evaluate((el) => (el as HTMLElement).click());
  return probe!;
}

/**
 * Click a semantics node. Falls back to DOM click when Playwright's hit
 * target check would otherwise report interception by flutter-view.
 */
export async function clickSemantics(page: Page, id: string) {
  const locator = page.locator(byTestId(id)).first();
  await expect(locator).toBeVisible({ timeout: 60_000 });

  try {
    await locator.click({ timeout: 15_000 });
  } catch {
    await locator.evaluate((el) => (el as HTMLElement).click());
  }
}

export async function assertSemanticsNotDoubleScaled(
  page: Page,
  id: string,
  opts: { maxXRatioOfViewport?: number } = {},
) {
  const maxRatio = opts.maxXRatioOfViewport ?? 1.05;
  const probe = await probeSemantics(page, id);
  expect(probe, `missing ${id} for offset check`).not.toBeNull();
  const vw = page.viewportSize()?.width ?? 1280;
  // With a ~2× bug, nodes that belong on-screen often sit near 2× their
  // layout x or past the viewport edge. Keep a soft guardrail.
  expect(
    probe!.x,
    `${id} x=${probe!.x} looks past viewport (possible 2× semantics offset; dpr=${probe!.dpr})`,
  ).toBeLessThan(vw * maxRatio);
  return probe!;
}

export function fileInputLocator(page: Page): Locator {
  return page.locator('#tashil-file-input');
}
