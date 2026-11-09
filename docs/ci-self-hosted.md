# Self-hosted CI runbook (tashil-mac)

CI uses a **hybrid runner split**:

| Class | Jobs | Runner var | Default |
|-------|------|------------|---------|
| Light / fast | Go tests, path detect, Cloud Run pin, Flutter/smoke gates, deploy `test-*` | `CI_HOSTED_RUNNER` | `ubuntu-latest` (GitHub-hosted) |
| Heavy | Flutter analyze/test (35m), Playwright smoke | `CI_RUNS_ON` | `["self-hosted","macOS","tashil-mac"]` |
| Deploy | `deploy-backend` / `deploy-web` | `CI_RUNS_ON` | Mac (gcloud WIF / toolchains) |

**Never** use GitHub-hosted macOS runners (`macos-latest`) — they are expensive.
`deploy.yml` keeps `cancel-in-progress: false` so production deploys are never
cancelled mid-flight.

**This Mac is shared** with other bots/accounts (their own runners, Firestore
emulators, Flutter/Go builds). CI must never assume exclusive use of the machine.

## Runner labels

```yaml
runs-on: [self-hosted, macOS, tashil-mac]
```

**`tashil-mac` … `tashil-mac-4` are four GitHub runner processes on one physical Mac.**
They share CPU, disk, and toolchains — when all four pick up jobs at once the machine
thrashes (slow Flutter/Go/Playwright, lost communication). Prefer hosted ubuntu for
light gates (`CI_HOSTED_RUNNER`); keep only heavy/deploy work on Mac. For overlapping
heavy jobs, enable `MAC_SHARED_LOCK=1` (below) or reduce how many Mac runners are
online so GitHub queues instead of over-paralleling one host.

**`tashil-mac-2` / `tashil-mac-3` / `tashil-mac-4` run as user `tashil-ci`**
(`HOME=/Users/tashil-ci`). Toolchains live at `$HOME/toolchains` — never hardcode
`/Users/fathalla`.

| Runner name    | User (target) | Install dir            | ADB server port |
|----------------|---------------|------------------------|-----------------|
| `tashil-mac`   | (legacy / migrating) | `~/actions-runner`   | 5037 |
| `tashil-mac-2` | `tashil-ci`   | `~/actions-runner-2`   | 5038 |
| `tashil-mac-3` | `tashil-ci`   | `~/actions-runner-3`   | 5039 |
| `tashil-mac-4` | `tashil-ci`   | `~/actions-runner-4`   | 5040 |

`scripts/ci_runner_env.sh` sets `PATH` (`$HOME/toolchains/bin` + Flutter), `ANDROID_HOME`,
`ANDROID_ADB_SERVER_PORT`, `ADB_SERVER_SOCKET=tcp:localhost:<port>`, and forces
`PUB_CACHE=$RUNNER_TEMP/pub-cache` (ignores any pre-set shared `PUB_CACHE`).
Isolation is checked by `scripts/ci_pub_cache_isolation_test.sh`.

Custom label on each: `tashil-mac`. GitHub also applies `self-hosted`, `macOS`, `ARM64`.

## Shared-Mac hard rules

1. **Never assume fixed ports** (`4173`, `8080`, `4000`, …). Probe with
   `scripts/pick_free_ports.py --min 5600` (our band). **Do not use 5570–5580** (other bot).
2. **Never kill by process name** (`pkill -f firestore`, etc.). Cleanup may only signal
   the **PID (tree) this job started** (`scripts/run_firestore_emulator_tests.sh`).
3. **Keep CPU bounded** — see table below. Other bots may be compiling at the same time.
4. **Per-job temp dirs** under `$RUNNER_TEMP/tashil-emu-…` (sandbox `HOME`/`TMPDIR`).
   Do not write job-specific emulator config into another user’s home.
5. **Hosted / Mac fallback** via `CI_HOSTED_RUNNER` / `CI_RUNS_ON` still works (same scripts; ports still probed).
6. **Cross-repo Mac lock** — opt-in via `MAC_SHARED_LOCK` (see below). Do **not** edit
   `~/mac-resources` from CI.
7. **Paths** use `$HOME` / `ANDROID_HOME` / `$HOME/toolchains` — never `/Users/fathalla`.

## Cross-repo Mac lock (`~/mac-resources/mac-lock.sh`)

GitHub `concurrency` only serializes within one workflow/ref. Another repo’s runners on
the same Mac can still overlap. Heavy jobs may book a **global** directory lock.

**Do not edit** `~/mac-resources` from this repo’s CI.

### Opt-in (`MAC_SHARED_LOCK`)

Lock is **off unless** repo variable / env `MAC_SHARED_LOCK=1`. Unset on the dedicated
`tashil-ci` user/machine (migration). Set `MAC_SHARED_LOCK=1` only while still sharing
fathalla-mac with other bots. Emulator **free-port** isolation stays on either way.

### Safe invoke (`scripts/mac_lock_ci.sh`)

1. Opt-in check (`MAC_SHARED_LOCK`)
2. **Native wait loop** on `LOCK.d` (does not exec live `mac-lock.sh` during the wait —
   another agent rewriting that file mid-wait used to shift bash’s read offset)
3. **Parent-alive** every poll: if `Runner.Worker` / `$PPID` chain / GITHUB job looks
   dead, **exit without acquiring**. After acquire, if parent is gone, **release immediately**
   (stops cancelled jobs from leaving orphan `LOCK.d`)
4. Release `if: always()` only when we own the lock (agent name in `status` / owner file)
5. Acquire **step** `timeout-minutes` is **shorter than the job** timeout so cancel still
   runs the release step

```bash
export MAC_SHARED_LOCK=1   # omit on dedicated tashil-ci
AGENT="ci-Tashil-Data-Sharing-${GITHUB_RUN_ID}-${GITHUB_JOB}"
bash scripts/mac_lock_ci.sh acquire "$AGENT" "omar-fathalla/Tashil-Data-Sharing" "<task>" <eta> <wait>
# … work …
bash scripts/mac_lock_ci.sh release "$AGENT"
```

| Job | Lock when `MAC_SHARED_LOCK=1`? | acquire step timeout | job timeout |
|-----|-------------------------------|----------------------|-------------|
| Backend Go (+ emulator) | yes | 10m | 25m |
| Flutter analyze & test (run) | yes | 8m | 35m |
| Playwright Semantics smoke (run) | yes | 15m | 45m |
| Cloud Run pin / PR comment / path detect & gates | **no** | — | 5m (hosted via `CI_HOSTED_RUNNER`) |

Path filters (`dorny/paths-filter`): no workflow-level `paths-ignore` — workflows always
start so gates report. Flutter + Playwright heavy jobs run only when `tashil_web/` /
`e2e/` / related scripts / workflow files change. Required checks report via lightweight
gate jobs on `CI_HOSTED_RUNNER` (`Flutter analyze & test`,
`flutter-web-semantics-smoke`).

Self-hosted Flutter: prefer `$HOME/toolchains/flutter` (`scripts/ci_detect_flutter.sh`);
**fail fast** if missing — never download via `flutter-action` on Mac. `PUB_CACHE` is
forced to `$RUNNER_TEMP/pub-cache` per job.

**Tradeoff when enabled:** one global `LOCK.d` serializes our heavy jobs with each other
and with other agents. Waits poll every 30s up to `wait_max_min`.

## Go test caps (self-hosted)

`scripts/run_go_tests_ci.sh`:

| Env | Default | Meaning |
|-----|---------|---------|
| `CI_GO_TEST_P` | 2 (Darwin/self-hosted) | max packages in parallel |
| `CI_GO_TEST_GOMAXPROCS` | same as `-p` | `GOMAXPROCS` per package |
| `CI_GO_TEST_PKG_TIMEOUT_MIN` | 15 | per-package `-timeout` |

Each package gets its own timeout (avoids one 18m package + another blowing a shared
20m `go test ./...` wall clock). Runs with `-json` and prints the **slowest 25 tests**.

Large local Downloads workbook tests (`TestRealWorkbooks…`, `TestLargeBook6…`) require
`RUN_LARGE_LOCAL_INGEST_TESTS=1` — on the shared Mac those files exist and otherwise
dominate CI. Handlers/ingestion unit tests only use short `time.Sleep` (ms); load comes
from fixture size, not sleeps.

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
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}
```

Superseded PR syncs cancel in-flight CI; **never cancel `main`**. **`deploy.yml` must
keep `cancel-in-progress: false`** — never cancel a production deploy.

GitHub workflow concurrency only serializes within one workflow/ref — it does **not**
stop `tashil-mac`…`tashil-mac-4` from all running different workflows at once on the
same Mac. Queueing levers: keep light jobs on `CI_HOSTED_RUNNER`, enable
`MAC_SHARED_LOCK=1` for heavies, or take runners offline so the label has fewer
slots.

## CPU budget (14-core Mac, up to 4 runners + other bots)

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
| Pub | Per-job `$RUNNER_TEMP/pub-cache` via `PUB_CACHE` (`ci_runner_env.sh`); never shared `~/.pub-cache`. Remote `actions/cache` only on github-hosted |
| Flutter SDK | **Required** preinstalled 3.41.2 at `$HOME/toolchains/flutter` on self-hosted (`ci_detect_flutter.sh`); missing → fail fast. `flutter-action` only on github-hosted fallback |
| Firebase emulator JARs | `~/.cache/firebase/emulators` (shared read; per-job config elsewhere) |
| npm (e2e) | `setup-node` cache |
| Playwright browsers | `~/.cache/ms-playwright` + `~/Library/Caches/ms-playwright` |

## Runner variables (hybrid + budget fallback)

Both expressions use `fromJSON` so a **single variable** can be either a JSON string
runner name or a JSON label array:

```yaml
# Light jobs (default GitHub-hosted ubuntu):
runs-on: ${{ fromJSON(vars.CI_HOSTED_RUNNER || '"ubuntu-latest"') }}

# Heavy + deploy jobs (default Mac self-hosted):
runs-on: ${{ fromJSON(vars.CI_RUNS_ON || '["self-hosted", "macOS", "tashil-mac"]') }}
```

Settings → Secrets and variables → Actions → Variables:

| Goal | Variable | Value (exact) |
|------|----------|---------------|
| Default (recommended) | leave both unset | light → ubuntu; heavy/deploy → Mac |
| Force light jobs to Mac (GitHub minutes / spending exhausted) | `CI_HOSTED_RUNNER` | `["self-hosted","macOS","tashil-mac"]` |
| Explicit ubuntu for light jobs | `CI_HOSTED_RUNNER` | `"ubuntu-latest"` (JSON string — include the quotes) |
| Move heavy jobs to ubuntu (Mac offline) | `CI_RUNS_ON` | `["ubuntu-latest"]` |

**Important:** values must be valid JSON for `fromJSON`. A bare `ubuntu-latest` (no
quotes) is **not** valid — use `"ubuntu-latest"` or leave the var unset.

On Linux fallback, Playwright installs with `npx playwright install --with-deps chromium`.
Emulator isolation scripts still probe free ports (safe on ubuntu-latest too).

## Check / restart / re-register runners

```bash
~/actions-runner/svc.sh status
~/actions-runner-2/svc.sh status
~/actions-runner-3/svc.sh status
~/actions-runner-4/svc.sh status

~/actions-runner/svc.sh stop && ~/actions-runner/svc.sh start
# … same for -2 / -3 / -4
```

If the Mac is saturated, stop one or two runner services so GitHub queues jobs
instead of scheduling four heavy workloads onto one host.

## Work directories

- `~/actions-runner/_work/Tashil-Data-Sharing/Tashil-Data-Sharing`
- `~/actions-runner-2/_work/...`
- `~/actions-runner-3/_work/...`
- `~/actions-runner-4/_work/...`
- Emulator sandboxes: `$RUNNER_TEMP/tashil-emu-<run>-<job>-<pid>/`

## Clean disk

```bash
du -sh ~/actions-runner/_work ~/actions-runner-2/_work ~/actions-runner-3/_work
# When idle (this account's runners only — do not wipe other users' homes):
rm -rf ~/actions-runner/_work/* ~/actions-runner-2/_work/* ~/actions-runner-3/_work/*
du -sh ~/.cache/firebase ~/Library/Caches/ms-playwright 2>/dev/null
# Stale shared home pub cache (pre-isolation); safe to remove when idle:
# rm -rf ~/.pub-cache
# Optional local toolchains pub dirs: rm -rf ~/toolchains/pub-cache
```

Preinstalled: Go 1.26, Flutter 3.41.2, Node 25, Java 21, `gh`, `git`. No Docker.

## What CI covers

- Cloud Run one-instance pin
- Backend: `go vet`, capped `go test`, isolated Firestore emulator product-match tests,
  `parse_live_backend_commit_test.py`
- Flutter: analyze + `flutter test --concurrency=2`
- Playwright Semantics smoke (Retina-safe activate)
