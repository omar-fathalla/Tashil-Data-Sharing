# Self-hosted CI runbook (tashil-mac)

CI (`ci.yml`) and Playwright smoke (`playwright_smoke.yml`) run on Mohamed’s Mac
via the shared label **`tashil-mac`**. Production **`deploy.yml` stays on
`ubuntu-latest`** with `cancel-in-progress: false` so deploys are never cancelled
mid-flight and do not depend on the Mac being awake.

## Runner labels

```yaml
runs-on: [self-hosted, macOS, tashil-mac]
```

Three runners share that label (parallel jobs OK):

| Runner name    | Install dir          |
|----------------|----------------------|
| `tashil-mac`   | `~/actions-runner`   |
| `tashil-mac-2` | `~/actions-runner-2` |
| `tashil-mac-3` | `~/actions-runner-3` |

Custom label on each: `tashil-mac`. GitHub also applies `self-hosted`, `macOS`, `ARM64`.

## Concurrency

`ci.yml` and `playwright_smoke.yml`:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

Superseded pushes/PR syncs cancel in-flight CI on that ref. **`deploy.yml` must keep
`cancel-in-progress: false`** — never cancel a production deploy on `main`.

## CPU budget (14-core Mac, 3 runners)

When all three runners are busy, uncapped `go test -p` / Flutter concurrency drove
host load into the 30–100+ range. Caps in workflows:

| Job | Cap |
|-----|-----|
| `go test` | `-p` / `GOMAXPROCS` ≤ **3** (`cores/5`, clamped 2–3) |
| `flutter test` | `--concurrency=2` |
| Playwright | `workers: 1` (already) |

Do **not** boot Android emulators or the iOS Simulator from CI. This Mac CI is
Flutter **web** + Go + Playwright Chromium only.

## Caching

| Cache | Path / mechanism |
|-------|------------------|
| Go modules | `actions/setup-go` `cache: true` |
| Go build | `~/.cache/go-build` + `~/Library/Caches/go-build` |
| Pub | `~/.pub-cache` |
| Flutter SDK | preinstalled 3.41.2, else `flutter-action` + cache |
| Firebase emulators | `~/.cache/firebase/emulators` |
| npm (e2e) | `setup-node` cache |
| Playwright browsers | `~/.cache/ms-playwright` + `~/Library/Caches/ms-playwright` |

## Fallback to ubuntu-latest (Mac offline)

Set a repository variable (Settings → Secrets and variables → Actions → Variables):

| Name         | Value               |
|--------------|---------------------|
| `CI_RUNS_ON` | `["ubuntu-latest"]` |

Both workflows resolve:

```yaml
runs-on: ${{ fromJSON(vars.CI_RUNS_ON || '["self-hosted", "macOS", "tashil-mac"]') }}
```

Remove the variable (or set it back to `["self-hosted", "macOS", "tashil-mac"]`) to
return to the Mac. One-line alternative: hardcode `runs-on: ubuntu-latest`.

On Linux fallback, Playwright installs with `npx playwright install --with-deps chromium`.

## Check / restart / re-register runners

On the Mac (as the runner user):

```bash
~/actions-runner/svc.sh status
~/actions-runner-2/svc.sh status
~/actions-runner-3/svc.sh status

~/actions-runner/svc.sh stop && ~/actions-runner/svc.sh start
~/actions-runner-2/svc.sh stop && ~/actions-runner-2/svc.sh start
~/actions-runner-3/svc.sh stop && ~/actions-runner-3/svc.sh start
```

Re-register (token from GitHub → Settings → Actions → Runners):

```bash
cd ~/actions-runner   # or -2 / -3
./svc.sh stop
./config.sh remove --token <REMOVE_TOKEN>
./config.sh --url https://github.com/omar-fathalla/Tashil-Data-Sharing \
  --token <REG_TOKEN> \
  --name tashil-mac \          # or tashil-mac-2 / tashil-mac-3
  --labels self-hosted,macOS,ARM64,tashil-mac \
  --work _work
./svc.sh install && ./svc.sh start
```

## Work directories

- `~/actions-runner/_work/Tashil-Data-Sharing/Tashil-Data-Sharing`
- `~/actions-runner-2/_work/Tashil-Data-Sharing/Tashil-Data-Sharing`
- `~/actions-runner-3/_work/Tashil-Data-Sharing/Tashil-Data-Sharing`

Jobs clean large artifacts they create (Flutter `build/web`, Playwright reports,
job-started Firebase emulator PIDs). They must **not** kill a manually started
Firestore emulator outside the job’s PID snapshot.

## Clean disk

```bash
du -sh ~/actions-runner/_work ~/actions-runner-2/_work ~/actions-runner-3/_work
# When idle:
rm -rf ~/actions-runner/_work/* ~/actions-runner-2/_work/* ~/actions-runner-3/_work/*
du -sh ~/.pub-cache ~/.cache/firebase ~/Library/Caches/ms-playwright 2>/dev/null
```

Preinstalled toolchains (do not delete casually): Go 1.26, Flutter 3.41.2, Node 25,
Java 21 (temurin-compatible), `gh`, `git`. Docker is **not** installed.

CI reuses preinstalled Flutter/Java when versions match (avoids Adoptium /
`flutter-action` download stalls).

## What CI covers

- **Cloud Run one-instance pin** — `scripts/check_cloud_run_one_instance.sh`
- **Backend** — `go vet`, capped `go test`, Firestore emulator product-match tests,
  `scripts/parse_live_backend_commit_test.py`
- **Flutter** — `flutter analyze` + `flutter test --concurrency=2`
- **Playwright smoke** — Flutter web + Chromium Semantics login smoke
  (1440×900, `deviceScaleFactor: 1`, DPR init guards, Retina-safe DOM focus when
  Semantics inputs sit outside the viewport — see `docs/SEMANTICS_TEST_IDS.md`)
