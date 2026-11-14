# Production deploy

Pushing to `main` runs `.github/workflows/deploy.yml`:

1. `go vet` + `go test ./...` (backend-go) and `flutter analyze` + `flutter test` (tashil_web).
2. Backend: `gcloud run deploy tashil-backend --source backend-go` (europe-west1) from the clean
   checkout. Deploy pins `--cpu=2 --memory=4Gi` and `--min-instances=1 --max-instances=1`
   until shared storage lands (#37); other settings (CPU always on, startup boost, gen2,
   archive volume, env vars and secrets incl. `BIGQUERY_SINK_ENABLED=true`) are kept. The
   commit SHA is written to `backend-go/data/build_commit.txt`, so `/api/v1/version` reports it.
   **Skip rule:** on `push` to `main`, Cloud Run deploy is skipped only when `backend-go/` and
   `.github/workflows/deploy.yml` are unchanged versus the **live** `/api/v1/version` `git_commit`
   (not `github.event.before`). That way a failed backend deploy followed by a web-only push still
   redeploys the backend. Empty, unreachable, or **malformed** live version JSON fail-safe to
   redeploy (`deploy=true`); they must not abort the job. `workflow_dispatch` always redeploys.
3. Web: `scripts/flutter_build_web.sh <n>` (pwa-strategy=none, kill-switch SW, version.json) and `firebase deploy --only hosting`.

Docs-only changes (`**.md`, `docs/**`) do not deploy. Runs are serialized (`deploy-production`
concurrency group, never cancelled mid-deploy). It can also be started by hand (workflow_dispatch).

## Startup probe (zero-downtime rollouts)

The backend loads its data for ~3 minutes after it starts listening. `GET /readyz` returns
`503 {"status":"loading"}` until that load has finished (then the same auth check as `/livez`),
and the Cloud Run **startup probe** points at it, so a new revision only receives traffic once it
is warm; the previous revision keeps serving until then (max-instances is per revision).
`/livez` stays the cheap liveness endpoint (always 200 once auth users are loaded).

Service-level pin (Cloud Run keeps it on later `gcloud run deploy --source` runs, like the
startup-cpu-boost / always-on settings):

```
--startup-probe=httpGet.path=/readyz,httpGet.port=8080,initialDelaySeconds=180,periodSeconds=10,timeoutSeconds=5,failureThreshold=24
```

Cloud Run caps `failureThreshold × periodSeconds` at 240s and `initialDelaySeconds` at 240s, so
this allows 180s + 240s = 7 minutes (load ~3 min) and detects readiness within 10s after the
first check. If a load ever takes longer, the new revision fails and traffic stays on the old one.
The log line `Startup data load finished in …; /readyz now passes.` marks the moment. The flag is
not in `deploy.yml` (workflow edits need separate approval); add it next to `--cpu/--memory`
if the workflow is updated.

## Auth durability (single-instance stopgap)

Login users are hydrated from Firestore `tenant_users` at startup (seed only when the collection
is empty). Password / Active updates **persist to Firestore before** they become visible to
`GetUserByEmail` on that instance. Login also calls `EnsureAuthUsersFresh` so a peer (or a
restarted) instance converges within a few seconds.

**Until Cloud Run stays at one instance**, treat auth as single-writer/single-reader in practice.
Raising `max-instances` without a durable watch/versioned auth path will leave other instances
accepting stale passwords/Active until refresh/restart. Keep `--min-instances=1 --max-instances=1`
when integrating deploy.yml changes (#30 skip logic, #39 pin, #26 memory). The CI pin guard is
`scripts/check_cloud_run_one_instance.sh` (see `ci.yml`).

## Web version number

CI does not commit back to `main` (that would trigger another deploy). The sidebar version is
`deploy_version.txt` (last manual value, 22) + `github.run_number` of this workflow, so it only
goes up. `scripts/deploy_web.sh` still works for manual deploys, but it bumps
`deploy_version.txt` by 1, so a later CI number may repeat a manual one. Prefer CI.

## Auth

Workload Identity Federation, no service-account keys:

- Pool `github`, provider `github` (issuer `token.actions.githubusercontent.com`), condition
  `repository == omar-fathalla/Tashil-Data-Sharing && ref == refs/heads/main`.
- Service account `tashil-gh-deployer@tashil-data-sharing.iam.gserviceaccount.com`:
  run.admin, cloudbuild.builds.editor, artifactregistry.writer, firebasehosting.admin,
  serviceusage.serviceUsageConsumer, logging.viewer (build log streaming); storage.admin only on
  `gs://run-sources-tashil-data-sharing-europe-west1`; serviceAccountUser on `tashil-backend-sa`
  and the Cloud Build service account `564362209163-compute@developer.gserviceaccount.com`.
