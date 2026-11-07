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
| `file-row-<name>` | One archive row (name sanitized) | `file-row-sales-jan.xlsx` |
| `file-delete-<name>` | Per-row delete action | `file-delete-sales-jan.xlsx` |
| `delete-confirm` / `delete-cancel` | Delete confirmation dialog actions | `delete-confirm` |
| `snackbar-*` | Snackbar / toast feedback | `snackbar-error`, `snackbar-success`, `snackbar-message` |

### File-name sanitization

`<name>` in `file-row-*` / `file-delete-*` is the file name lowercased with
non `[a-z0-9._-]` runs replaced by `-` (see `TestIds.fileToken` in
`tashil_web/lib/core/testing/test_semantics.dart`).

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
| `sellout-uploaded-files` | Sell-Out “Uploaded Files (N)” tab |
| `sellin-uploaded-files` | Sell-In “Uploaded Files (N)” tab |
| `uploaded-files-list` | Uploaded files list / table |
| `file-row-<name>` | Row for that file (label includes file name) |
| `file-delete-<name>` | Delete for that file |
| `delete-cancel` | Cancel on delete confirm dialog |
| `delete-confirm` | Confirm delete |
| `snackbar-error` | Error snackbar |
| `snackbar-success` | Success snackbar |
| `snackbar-message` | Warning / info snackbar |

## Playwright tip

```js
page.locator('[flt-semantics-identifier="login-email"]')
// or after Flutter maps identifiers into ARIA:
page.getByLabel('Email')
```

Constants live in `tashil_web/lib/core/testing/test_semantics.dart` (`TestIds`).
