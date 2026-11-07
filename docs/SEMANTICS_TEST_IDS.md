# Flutter web Semantics test IDs

Stable identifiers for Playwright / Maestro / Patrol against the Flutter web
accessibility tree (`flt-semantics-identifier`, plus `aria-label` / Semantics
`label` where set).

Enabled at startup on web via `SemanticsBinding.instance.ensureSemantics()` in
`tashil_web/lib/main.dart` so nodes exist without manually enabling
accessibility mode.

## Naming scheme

Kebab-case tokens. Prefer a short **area prefix**, then the control role.

| Pattern | Meaning | Examples |
|---------|---------|----------|
| `login-*` | Tenant login form | `login-email`, `login-password`, `login-submit` |
| `logout` | Sign out | `logout` |
| `nav-*` | Shell navigation destinations | `nav-sell-out`, `nav-sell-in` |
| `sellout-*` / `sellin-*` | Page-scoped upload controls / counters | `sellout-upload-button`, `sellin-uploaded-files` |
| `upload-choose-file` | Smart Upload dropzone “choose file” | `upload-choose-file` |
| `uploaded-files-list` | Uploaded-files table / list region | `uploaded-files-list` |
| `file-row-<archiveId>-<name>` | One archive row (unique by archive id) | `file-row-abc123-sales-jan.xlsx` |
| `file-delete-<archiveId>-<name>` | Per-row delete action | `file-delete-abc123-sales-jan.xlsx` |
| `delete-confirm` / `delete-cancel` | Delete confirmation dialog actions | `delete-confirm` |
| `snackbar-*` | Snackbar / toast feedback | `snackbar-error`, `snackbar-success`, `snackbar-message` |

### File / archive token sanitization

`<archiveId>` and `<name>` are lowercased with non `[a-z0-9._-]` runs replaced
by `-` (see `TestIds.fileToken`). Archive id is always included so two rows with
the same file name stay unique.

### Nav uniqueness rule

Each `nav-*` id is attached to **exactly one** interactive face per destination
(e.g. NavigationRail / Drawer `icon` only — never also `selectedIcon` / `label`).
Compact “More” sheet items for Sell-Out / Sell-In also carry `nav-sell-out` /
`nav-sell-in`.

## Identifier catalog

| ID | Element |
|----|---------|
| `login-email` | Login email field |
| `login-password` | Login password field |
| `login-submit` | Login button |
| `logout` | Logout control (rail / drawer / profile) |
| `nav-sell-out` | Navigate to Sell-Out |
| `nav-sell-in` | Navigate to Sell-In |
| `sellout-upload-button` | Sell-Out “upload / choose file” |
| `sellin-upload-button` | Sell-In “upload / choose file” |
| `upload-choose-file` | Smart Upload portal choose-file button |
| `tashil-file-input` | Persistent hidden `<input type="file">` DOM id / `data-testid` (Playwright `setInputFiles`) |
| `upload-commit-confirm` / `upload-commit-cancel` | Sell-Out staged preview commit dialog |
| `sellout-uploaded-files` | Sell-Out “Uploaded Files (N)” tab |
| `sellin-uploaded-files` | Sell-In “Uploaded Files (N)” tab |
| `uploaded-files-list` | Uploaded files list / table |
| `file-row-<archiveId>-<name>` | Row for that archive (label includes file name) |
| `file-delete-<archiveId>-<name>` | Delete for that archive |
| `delete-cancel` | Cancel on delete confirm dialog |
| `delete-confirm` | Confirm delete |
| `snackbar-error` | Error snackbar |
| `snackbar-success` | Success snackbar |
| `snackbar-message` | Warning / info snackbar |

## Interactive controls (required for Playwright)

Upload / delete / dialog actions must use `TestSemantics.button` (or
`Semantics(button: true, onTap: …, container: true, excludeSemantics: true)`).

Without an owned `onTap`, DataTable archive actions collapse into
`role="cell"` and Playwright clicks are intercepted by `flutter-view`.

## Playwright tip

```js
page.locator('[flt-semantics-identifier="login-email"]')
// Tenant path must be explicit (absolute `/` drops `/adeco`):
await page.goto('/adeco')

// Sell-Out file pick (prefer setInputFiles; do not rely on filechooser alone):
await page.locator('[flt-semantics-identifier="sellout-upload-button"]').click()
await expect(page.locator('#tashil-file-input')).toHaveAttribute('data-armed', 'true')
await page.locator('#tashil-file-input').setInputFiles('fixtures/sellout-qa-preview.xlsx')

// Delete: assert role=button, open dialog, cancel (non-destructive):
await page.locator('[flt-semantics-identifier^="file-delete-"]').first().evaluate((el) => el.click())
await page.locator('[flt-semantics-identifier="delete-cancel"]').evaluate((el) => el.click())
```

File-delete / file-row ids are `file-delete-<archiveId>-<slugified-name>` /
`file-row-<archiveId>-<slugified-name>` via `TestIds.fileToken` (archive id +
slugified filename).

Playwright projects should keep `deviceScaleFactor: 1` so semantics CSS pixels
match the canvas (avoids ~2× hit-target offset).

Constants live in `tashil_web/lib/core/testing/test_semantics.dart` (`TestIds`).
