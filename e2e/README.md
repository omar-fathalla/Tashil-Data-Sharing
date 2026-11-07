# Playwright Semantics smoke (web-only)

Read-only smoke that loads the Flutter web app and asserts login Semantics
identifiers (`login-email`, `login-password`, `login-submit`) exist in the DOM
as `flt-semantics-identifier`.

## Local (against a built web app)

```bash
cd tashil_web && flutter build web --release
npx --yes serve@14 -s build/web -l 4173

# other terminal
cd e2e
npm ci
npx playwright install chromium
BASE_ORIGIN=http://127.0.0.1:4173 TENANT_PATH=/adeco npm test
```

## Against production (read-only, after Semantics deploy)

```bash
cd e2e
BASE_ORIGIN=https://www.data.sw-point.com TENANT_PATH=/adeco npm test
```

Smokes navigate to `/adeco` explicitly (never `/`, which would drop the tenant
path). They type a dummy password only to assert it never leaks into the DOM /
Semantics tree, and do not complete a successful login.
