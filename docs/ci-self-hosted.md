# Self-hosted CI runbook (tashil-mac)

CI (`ci.yml`) and Playwright smoke (`playwright_smoke.yml`) run on Mohamed’s Mac
via the shared label **`tashil-mac`**. Production **`deploy.yml` stays on
`ubuntu-latest`** with `cancel-in-progress: false` so deploys are never cancelled
mid-flight and do not depend on the Mac being awake.

**This Mac is shared** with other bots/accounts (their own runners, Firestore
emulators, Flutter/Go builds). CI must never assume exclusive use of the machine.

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

## Shared-Mac hard rules

1. **Never assume fixed ports** (`8080`, `4000`, `4400`, `9150`, …). Always probe for a
   free port (`scripts/pick_free_ports.py`).
2. **Never kill by process name** (`pkill -f firestore`, etc.). Cleanup may only signal
   the **PID (tree) this job started** (`scripts/run_firestore_emulator_tests.sh`).
3. **Keep CPU bounded** — see table below. Other bots may be compiling at the same time.
4. **Per-job temp dirs** under `$RUNNER_TEMP/tashil-emu-…` (sandbox `HOME`/`TMPDIR`).
   Do not write job-specific emulator config into another user’s home.
5. **Ubuntu fallback** via `CI_RUNS_ON` still works (same scripts; ports still probed).
6. **Cross-repo Mac lock** — see below. Do **not** edit `~/mac-resources` from CI; only call
   the installed `mac-lock.sh`.

## Cross-repo Mac lock (`~/mac-resources/mac-lock.sh`)

GitHub `concurrency` only serializes within one workflow/ref. Another repo’s runners on
the same Mac can still overlap. Heavy jobs therefore book a **global** directory lock:

```bash
~/mac-resources/mac-lock.sh acquire \
  "ci-Tashil-Data-Sharing-${GITHUB_RUN_ID}-${GITHUB_JOB}" \
  "omar-fathalla/Tashil-Data-Sharing" \
  "<task>" <eta_min> <wait_max_min>
# … work …
~/mac-resources/mac-lock.sh release "ci-Tashil-Data-Sharing-${GITHUB_RUN_ID}-${GITHUB_JOB}"
```

| Job | Takes lock? | eta_min | wait_max_min |
|-----|-------------|---------|--------------|
| Backend Go (+ Firestore emulator) | yes | 45 | 120 |
| Flutter analyze & test | yes | 25 | 120 |
| Playwright Semantics smoke | yes | 45 | 120 |
| Cloud Run one-instance pin | **no** (light) | — | — |
| Comment-on-PR-failure | **no** (light) | — | — |

If `~/mac-resources/mac-lock.sh` is missing (ubuntu-latest / github-hosted), acquire/release
**skip gracefully**.

**Tradeoff:** one global `LOCK.d` means our own heavy jobs also **serialize** with each
other (and with Tashil App / other agents). Wall-clock CI is longer; machine load stays
safe. Waits poll every 30s up to `wait_max_min` then fail.

## Firestore emulator isolation

`scripts/run_firestore_emulator_tests.sh`:

- Picks **3 free ports** (firestore + hub + logging); **UI disabled**
- Unique demo project: `demo-ci-<run_id>-<attempt>` (≤30 chars, `demo-` prefix)
- Writes a per-job `firebase.json` under `$RUNNER_TEMP/...`
- Sets `FIRESTORE_EMULATOR_HOST` (via `emulators:exec`) and
  `FIRESTORE_EMULATOR_PROJECT` / `GCLOUD_PROJECT` for Go tests
- Symlinks only the shared emulator **JAR cache**; config/logs stay in the job dir
- On EXIT/INT/TERM: kills **only** the wrapper PID recorded in `wrapper.pid`

Two backend jobs (or another bot’s emulator) can run concurrently because ports and
project IDs do not collide. Verify the port helper locally / in CI:

```bash
python3 scripts/pick_free_ports.py --self-test
```

## Concurrency

`ci.yml` and `playwright_smoke.yml`:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

Superseded pushes/PR syncs cancel in-flight CI on that ref. **`deploy.yml` must keep
`cancel-in-progress: false`** — never cancel a production deploy on `main`.

## CPU budget (14-core Mac, 3 runners + other bots)

| Job | Cap |
|-----|-----|
| `go test` | `-p` / `GOMAXPROCS` ≤ **3** (`cores/5`, clamped 2–3) |
| Emulator `go test` | `GOMAXPROCS=2`, `-parallel 1` |
| `flutter test` | `--concurrency=2` |
| Playwright | `workers: 1` |

Do **not** boot Android emulators or the iOS Simulator from CI. This Mac CI is
Flutter **web** + Go + Playwright Chromium only.

## Caching

| Cache | Path / mechanism |
|-------|------------------|
| Go modules | Local `~/go/pkg/mod` on self-hosted (remote setup-go cache disabled — was ~880MB / stalled); `cache: true` only on github-hosted |
| Go build | Local `~/Library/Caches/go-build` on self-hosted; actions/cache only on github-hosted |
| Pub | `~/.pub-cache` |
| Flutter SDK | preinstalled 3.41.2, else `flutter-action` + cache |
| Firebase emulator JARs | `~/.cache/firebase/emulators` (shared read; per-job config elsewhere) |
| npm (e2e) | `setup-node` cache |
| Playwright browsers | `~/.cache/ms-playwright` + `~/Library/Caches/ms-playwright` |

## Fallback to ubuntu-latest (Mac offline)

Set a repository variable (Settings → Secrets and variables → Actions → Variables):

| Name         | Value               |
|--------------|---------------------|
| `CI_RUNS_ON` | `["ubuntu-latest"]` |

```yaml
runs-on: ${{ fromJSON(vars.CI_RUNS_ON || '["self-hosted", "macOS", "tashil-mac"]') }}
```

On Linux fallback, Playwright installs with `npx playwright install --with-deps chromium`.
Emulator isolation scripts still probe free ports (safe on ubuntu-latest too).

## Check / restart / re-register runners

```bash
~/actions-runner/svc.sh status
~/actions-runner-2/svc.sh status
~/actions-runner-3/svc.sh status

~/actions-runner/svc.sh stop && ~/actions-runner/svc.sh start
# … same for -2 / -3
```

## Work directories

- `~/actions-runner/_work/Tashil-Data-Sharing/Tashil-Data-Sharing`
- `~/actions-runner-2/_work/...`
- `~/actions-runner-3/_work/...`
- Emulator sandboxes: `$RUNNER_TEMP/tashil-emu-<run>-<job>-<pid>/`

## Clean disk

```bash
du -sh ~/actions-runner/_work ~/actions-runner-2/_work ~/actions-runner-3/_work
# When idle (this account's runners only — do not wipe other users' homes):
rm -rf ~/actions-runner/_work/* ~/actions-runner-2/_work/* ~/actions-runner-3/_work/*
du -sh ~/.pub-cache ~/.cache/firebase ~/Library/Caches/ms-playwright 2>/dev/null
```

Preinstalled: Go 1.26, Flutter 3.41.2, Node 25, Java 21, `gh`, `git`. No Docker.

## What CI covers

- Cloud Run one-instance pin
- Backend: `go vet`, capped `go test`, isolated Firestore emulator product-match tests,
  `parse_live_backend_commit_test.py`
- Flutter: analyze + `flutter test --concurrency=2`
- Playwright Semantics smoke (Retina-safe activate)
