# Production deploy

Pushing to `main` runs `.github/workflows/deploy.yml`:

1. `go vet` + `go test ./...` (backend-go) and `flutter analyze` + `flutter test` (tashil_web).
2. Backend: `gcloud run deploy tashil-backend --source backend-go` (europe-west1) from the clean
   checkout. No flags other than region/project are passed, so the service keeps its current
   settings (min 1 / max 3, CPU always on, startup boost, gen2, archive volume, all env vars and
   secrets incl. `BIGQUERY_SINK_ENABLED=true`). The commit SHA is written to
   `backend-go/data/build_commit.txt`, so `/api/v1/version` reports it.
3. Web: `flutter build web --dart-define=APP_VERSION=<n>` and `firebase deploy --only hosting`.

Docs-only changes (`**.md`, `docs/**`) do not deploy. Runs are serialized (`deploy-production`
concurrency group, never cancelled mid-deploy). It can also be started by hand (workflow_dispatch).

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
