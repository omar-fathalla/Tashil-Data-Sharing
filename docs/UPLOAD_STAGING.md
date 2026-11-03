# Upload preview → commit

- `POST /api/v1/ingest/upload?dry_run=true` parses the file and stages it. **Nothing is archived or written**
  until commit. The staged file is kept on the archive mount under `_staged/<tenant>/<batch>.{json,bin}`
  for 6 hours, so a commit landing on another Cloud Run instance still works.
- `POST /api/v1/ingest/commit` takes `batch_id` plus the target chain either in the JSON body
  (`chain`) or as `?chain=`. If both are given and differ → `400 chain_conflict`.
- Commit responses:
  - `410` – the preview expired (or was never staged): «المعاينة انتهت، ارفع الملف تاني. مفيش حاجة اتحفظت.»
  - `404` – batch belongs to another tenant.
  - `409` – the file was re-parsed on this instance and the rows / value / chain differ from the preview; nothing is saved.
- The period choice made at preview (e.g. "use the sheet months") is reused at commit; the archive
  entry is created at commit with that period. Discard removes the staged copy.

# Retail chains (admin)

- Chain create / update / delete need a verified JWT with role `super_admin`, `vendor_admin` or `admin`
  (the `X-Simulated-Role` header is ignored here). Non-super-admins can only write their own tenant.
- Create is create-if-absent: `409` on a duplicate; `created_by`, `created_at` and an audit entry are stored.
- `GET /api/v1/admin/chains?include_referenced=1` also lists chain codes referenced by Sell-In rules/data
  that are not registered yet (`registered: false`). Reads keep the existing header/query tenant behaviour.
