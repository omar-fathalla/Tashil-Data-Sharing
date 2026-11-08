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
  name: string | null;
  x: number;
  y: number;
  w: number;
  h: number;
  dpr: number;
  pointerEvents: string;
  /** True when the Semantics box sits outside the CSS viewport (Retina 2× bug). */
  outsideViewport: boolean;
};

function viewportOf(page: Page) {
  return page.viewportSize() ?? { width: 1280, height: 720 };
}

/** Read geometry + ARIA role for a semantics id (for offset / role asserts). */
export async function probeSemantics(
  page: Page,
  id: string,
): Promise<SemanticsProbe | null> {
  const { width: vw, height: vh } = viewportOf(page);
  return page.evaluate(
    ({ semId, vw, vh }) => {
      const el = document.querySelector(
        `[flt-semantics-identifier="${semId}"]`,
      ) as HTMLElement | null;
      if (!el) return null;
      const r = el.getBoundingClientRect();
      const outsideViewport =
        r.x > vw ||
        r.y > vh ||
        r.x + r.width < 0 ||
        r.y + r.height < 0 ||
        Number.isNaN(r.x);
      return {
        id: semId,
        role: el.getAttribute('role'),
        name:
          el.getAttribute('aria-label') ||
          el.getAttribute('flt-semantics-label') ||
          el.textContent?.trim() ||
          null,
        x: r.x,
        y: r.y,
        w: r.width,
        h: r.height,
        dpr: window.devicePixelRatio,
        pointerEvents: getComputedStyle(el).pointerEvents,
        outsideViewport,
      };
    },
    { semId: id, vw, vh },
  );
}

/**
 * Activate a Semantics node. Prefers a natural locator.click when the box is
 * inside the viewport; on macOS Retina, Flutter web often places Semantics at
 * ~2× CSS coords (see docs/SEMANTICS_TEST_IDS.md) so hit-testing fails with
 * "outside of the viewport". In that case:
 *   1) click the painted control via accessible role + name when available
 *   2) otherwise dispatch focus+click on the Semantics DOM node (Flutter listens)
 */
export async function clickSemantics(page: Page, id: string) {
  const locator = page.locator(byTestId(id)).first();
  await expect(locator).toBeAttached({ timeout: 60_000 });

  const probe = await probeSemantics(page, id);
  expect(probe, `missing semantics node ${id}`).not.toBeNull();

  if (!probe!.outsideViewport) {
    try {
      await locator.scrollIntoViewIfNeeded();
      await locator.click({ timeout: 8_000 });
      return;
    } catch {
      // Fall through to Retina-safe paths.
    }
  }

  // Prefer the visible AX control (correct hit target on Retina).
  if (probe!.role && probe!.name) {
    const role = probe!.role as
      | 'button'
      | 'textbox'
      | 'checkbox'
      | 'link'
      | 'radio';
    try {
      await page
        .getByRole(role, { name: probe!.name, exact: false })
        .first()
        .click({ timeout: 8_000 });
      return;
    } catch {
      // Fall through.
    }
  }

  // Last resort: DOM activate — Flutter's Semantics bridge handles this even
  // when the node's getBoundingClientRect is outside the Playwright viewport.
  await locator.evaluate((el: HTMLElement) => {
    el.scrollIntoView({ block: 'center', inline: 'center' });
    el.focus();
    el.dispatchEvent(
      new MouseEvent('click', { bubbles: true, cancelable: true, view: window }),
    );
  });
}

/**
 * Assert role=button and that a click succeeds (natural when geometry allows;
 * Retina-safe fallback otherwise).
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

  await clickSemantics(page, id);
  return probe!;
}

/**
 * Soft diagnostic for ~2× semantics offset. Does not fail the suite — Retina
 * Mac hosts often report outside-viewport boxes even when DPR is forced to 1.
 * Returns whether geometry looks double-scaled for logging/assertions callers
 * may opt into.
 */
export async function assertSemanticsNotDoubleScaled(
  page: Page,
  id: string,
  opts: { maxXRatioOfViewport?: number; hard?: boolean } = {},
) {
  const maxRatio = opts.maxXRatioOfViewport ?? 1.05;
  const hard = opts.hard ?? false;
  const probe = await probeSemantics(page, id);
  expect(probe, `missing ${id} for offset check`).not.toBeNull();
  const vw = viewportOf(page).width;
  const vh = viewportOf(page).height;
  const ok =
    probe!.x < vw * maxRatio &&
    probe!.y >= -8 &&
    probe!.y + probe!.h <= vh * maxRatio + 8;
  if (!ok) {
    const msg = `${id} x=${probe!.x} y=${probe!.y} w=${probe!.w} h=${probe!.h} dpr=${probe!.dpr} outsideViewport=${probe!.outsideViewport} (vw=${vw}) — using Retina-safe click path`;
    console.warn(msg);
    if (hard) {
      expect(
        probe!.x,
        `${id} x=${probe!.x} looks past viewport (possible 2× semantics offset; dpr=${probe!.dpr})`,
      ).toBeLessThan(vw * maxRatio);
    }
  }
  return probe!;
}

export function fileInputLocator(page: Page): Locator {
  return page.locator('#tashil-file-input');
}

/** Verified login typing: activate field (Retina-safe), then ~40ms key delay. */
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

/**
 * Login-shell helpers: drive the painted controls via accessible roles.
 * Semantics ids are still asserted separately; geometry on Retina Mac is unreliable.
 */
export async function typeLoginEmail(page: Page, email: string) {
  const box = page.getByRole('textbox', { name: /email/i }).first();
  await expect(box).toBeVisible({ timeout: 60_000 });
  await box.click();
  await page.waitForTimeout(250);
  await page.keyboard.type(email, { delay: 40 });
}

export async function typeLoginPassword(page: Page, password: string) {
  const box = page.getByRole('textbox', { name: /password/i }).first();
  await expect(box).toBeVisible({ timeout: 60_000 });
  await box.click();
  await page.waitForTimeout(250);
  await page.keyboard.type(password, { delay: 40 });
}

export async function clickLoginSubmit(page: Page) {
  const btn = page.getByRole('button', { name: /^login$/i }).first();
  await expect(btn).toBeVisible({ timeout: 60_000 });
  await btn.click();
}
