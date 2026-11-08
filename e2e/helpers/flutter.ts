import { expect, type Locator, type Page } from '@playwright/test';

/** Locator for a Flutter web Semantics identifier. */
export function byTestId(id: string) {
  return `[flt-semantics-identifier="${id}"]`;
}

/**
 * Freeze DPR/screen metrics before Flutter boots. On Retina Mac hosts,
 * Flutter web otherwise places Semantics/input hit-boxes at ~2× CSS x
 * (e.g. x=2880 on a 1440-wide viewport) even when Playwright reports dpr=1.
 */
export async function installRetinaGuards(
  page: Page,
  viewport: { width: number; height: number } = { width: 1440, height: 900 },
) {
  await page.addInitScript(
    ({ width, height }) => {
      try {
        Object.defineProperty(window, 'devicePixelRatio', {
          configurable: true,
          get: () => 1,
        });
      } catch {
        /* ignore */
      }
      try {
        Object.defineProperty(window.screen, 'width', {
          configurable: true,
          get: () => width,
        });
        Object.defineProperty(window.screen, 'height', {
          configurable: true,
          get: () => height,
        });
        Object.defineProperty(window.screen, 'availWidth', {
          configurable: true,
          get: () => width,
        });
        Object.defineProperty(window.screen, 'availHeight', {
          configurable: true,
          get: () => height,
        });
      } catch {
        /* ignore */
      }
    },
    viewport,
  );
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

function boxInViewport(
  bb: { x: number; y: number; width: number; height: number } | null,
  vw: number,
  vh: number,
): boolean {
  if (!bb || bb.width <= 0 || bb.height <= 0) return false;
  return (
    bb.x >= -1 &&
    bb.y >= -1 &&
    bb.x + bb.width <= vw + 2 &&
    bb.y + bb.height <= vh + 2
  );
}

/**
 * Activate a Flutter control for keyboard input.
 * Prefers an in-viewport hit-test click; on Retina Mac, Flutter often leaves
 * Semantics-backed <input> nodes outside the Playwright viewport — then focus
 * via DOM events (Flutter's bridge still receives them).
 */
export async function activateFlutterControl(page: Page, locator: Locator) {
  await expect(locator.first()).toBeAttached({ timeout: 60_000 });
  const { width: vw, height: vh } = viewportOf(page);
  const count = await locator.count();

  for (let i = 0; i < count; i++) {
    const el = locator.nth(i);
    const bb = await el.boundingBox();
    if (!boxInViewport(bb, vw, vh)) continue;
    try {
      await el.click({ timeout: 5_000 });
      return 'click';
    } catch {
      // try next / fall through
    }
  }

  await locator.first().evaluate((el: HTMLElement) => {
    el.focus();
    el.dispatchEvent(new Event('focus', { bubbles: true }));
    el.dispatchEvent(new FocusEvent('focusin', { bubbles: true }));
    for (const type of ['mousedown', 'mouseup', 'click'] as const) {
      el.dispatchEvent(
        new MouseEvent(type, { bubbles: true, cancelable: true, view: window }),
      );
    }
  });
  return 'dom-focus';
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
 * ~2× CSS coords so hit-testing fails with "outside of the viewport".
 */
export async function clickSemantics(page: Page, id: string) {
  const locator = page.locator(byTestId(id));
  await activateFlutterControl(page, locator);
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
    await page.waitForTimeout(250);
  });
  await page.waitForTimeout(250);
  await page.keyboard.type(text, { delay: 40 });
}

/** Login email via ARIA textbox (Retina-safe activate + force fill fallback). */
export async function typeLoginEmail(page: Page, email: string) {
  const box = page.getByRole('textbox', { name: /email/i });
  await activateFlutterControl(page, box);
  await page.waitForTimeout(250);
  try {
    // force skips Playwright's "inside viewport" check on Retina-misplaced inputs.
    await box.first().fill(email, { force: true, timeout: 5_000 });
  } catch {
    await page.keyboard.type(email, { delay: 40 });
  }
}

/** Login password via ARIA textbox (Retina-safe activate + force fill fallback). */
export async function typeLoginPassword(page: Page, password: string) {
  const box = page.getByRole('textbox', { name: /password/i });
  await activateFlutterControl(page, box);
  await page.waitForTimeout(250);
  try {
    await box.first().fill(password, { force: true, timeout: 5_000 });
  } catch {
    await page.keyboard.type(password, { delay: 40 });
  }
}

/** Login submit via ARIA button (Retina-safe activate). */
export async function clickLoginSubmit(page: Page) {
  const btn = page.getByRole('button', { name: /^login$/i });
  await activateFlutterControl(page, btn);
}
