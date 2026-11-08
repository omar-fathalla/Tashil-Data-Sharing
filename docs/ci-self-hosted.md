# Self-hosted CI runbook (tashil-mac)

CI (`ci.yml`) and Playwright smoke (`playwright_smoke.yml`) run on Mohamed’s Mac
via the shared label **`tashil-mac`**. Production **`deploy.yml` stays on
`ubuntu-latest`** so deploys do not depend on the Mac being awake.

## Runner labels

```yaml
runs-on: [self-hosted, macOS, tashil-mac]
```

Three runners share that label (parallel jobs OK):

| Runner name   | Install dir                         |
|---------------|-------------------------------------|
| `tashil-mac`  | `~/actions-runner`                  |
| `tashil-mac-2`| `~/actions-runner-2`                |
| `tashil-mac-3`| `~/actions-runner-3`                |

Custom label on each: `tashil-mac`. GitHub also applies `self-hosted`, `macOS`, `ARM64`.

## Fallback to ubuntu-latest (Mac offline)

Set a repository variable (Settings → Secrets and variables → Actions → Variables):

| Name         | Value                |
|--------------|----------------------|
| `CI_RUNS_ON` | `["ubuntu-latest"]`  |

Both workflows resolve:

```yaml
runs-on: ${{ fromJSON(vars.CI_RUNS_ON || '["self-hosted", "macOS", "tashil-mac"]') }}
```

Remove the variable (or set it back to `["self-hosted", "macOS", "tashil-mac"]`) to
return to the Mac. One-line alternative: hardcode `runs-on: ubuntu-latest` in the
workflow files.

On Linux fallback, Playwright installs with `npx playwright install --with-deps chromium`.

## Check / restart / re-register runners

On the Mac (as the runner user):

```bash
# Status (launchd service installed via svc.sh)
~/actions-runner/svc.sh status
~/actions-runner-2/svc.sh status
~/actions-runner-3/svc.sh status

# Restart
~/actions-runner/svc.sh stop && ~/actions-runner/svc.sh start
~/actions-runner-2/svc.sh stop && ~/actions-runner-2/svc.sh start
~/actions-runner-3/svc.sh stop && ~/actions-runner-3/svc.sh start
```

If a runner is offline or needs re-registration (new token from
GitHub → repo → Settings → Actions → Runners → New self-hosted runner):

```bash
cd ~/actions-runner   # or -2 / -3
./svc.sh stop
./config.sh remove --token <REMOVE_TOKEN>
./config.sh --url https://github.com/omar-fathalla/Tashil-Data-Sharing \
  --token <REG_TOKEN> \
  --name tashil-mac \          # or tashil-mac-2 / tashil-mac-3
  --labels self-hosted,macOS,ARM64,tashil-mac \
  --work _work
./svc.sh install
./svc.sh start
```

## Work directories

Each runner checks out under its `_work` tree, e.g.:

- `~/actions-runner/_work/Tashil-Data-Sharing/Tashil-Data-Sharing`
- `~/actions-runner-2/_work/Tashil-Data-Sharing/Tashil-Data-Sharing`
- `~/actions-runner-3/_work/Tashil-Data-Sharing/Tashil-Data-Sharing`

Jobs clean large artifacts they create (Flutter `build/web`, Playwright reports,
job-started Firebase emulator PIDs). They must **not** kill a manually started
Firestore emulator outside the job’s PID snapshot.

## Clean disk

```bash
# Runner work caches (safe when idle)
du -sh ~/actions-runner/_work ~/actions-runner-2/_work ~/actions-runner-3/_work

# Optional: purge old work folders when no jobs are running
rm -rf ~/actions-runner/_work/* ~/actions-runner-2/_work/* ~/actions-runner-3/_work/*

# Flutter / pub / Firebase emulator caches (repopulated by CI)
du -sh ~/.pub-cache ~/.cache/firebase 2>/dev/null
# rm -rf ~/.cache/firebase/emulators   # only if emulator download is broken
```

Preinstalled toolchains (do not delete casually): Go 1.26, Flutter 3.41.2, Node 25,
Java 21 (temurin-compatible), `gh`, `git`. Docker is **not** installed.

## What CI covers

- **Cloud Run one-instance pin** — `scripts/check_cloud_run_one_instance.sh`
- **Backend** — `go vet`, `go test` (capped `-p` / `GOMAXPROCS`), Firestore emulator
  product-match tests, `scripts/parse_live_backend_commit_test.py`
- **Flutter** — `flutter analyze` + `flutter test` (reuses preinstalled SDK when present)
- **Playwright smoke** — Flutter web build + Chromium Semantics login smoke
  (explicit 1440×900 viewport, `deviceScaleFactor: 1`, `--force-device-scale-factor=1`)
