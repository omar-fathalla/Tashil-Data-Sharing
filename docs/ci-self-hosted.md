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
thrashes (observed under contention: **Setup Node ~10m**, **`flutter build web` ~7–12m**,
plus lost communication). Prefer hosted ubuntu for light gates (`CI_HOSTED_RUNNER`);
keep only heavy/deploy work on Mac; serialize heavies (below).

## Mac contention — recommended fix (combine)

Do **all three** while four runners share one host; drop levers only after the Mac is
dedicated / single-runner:

| Lever | What it does | Who sets it |
|-------|--------------|-------------|
| **Hosted light gates** | Path detect, Cloud Run pin, Backend Go, Flutter/smoke gates, deploy `test-*` stay on `CI_HOSTED_RUNNER` (default `ubuntu-latest`) so they never compete for Mac CPU/disk | Already in workflows — leave `CI_HOSTED_RUNNER` unset (or `"ubuntu-latest"`). **Do not** point it at Mac unless GitHub minutes are exhausted |
| **Job group `tashil-mac-heavy`** | In-repo: only one of `test-flutter` / `smoke-run` / `deploy-backend` / `deploy-web` runs at a time (`cancel-in-progress: false`). Pending heavies wait in GitHub’s queue and **do not occupy a Mac runner** | Wired in workflows (this repo) |
| **`MAC_SHARED_LOCK=1`** | Cross-repo directory lock (`~/mac-resources/LOCK.d`) so other bots/repos on the same Mac serialize with our heavies | Repo variable (Actions → Variables) |
| **Fewer online runners** | Stop `tashil-mac-3` / `tashil-mac-4` (leave 1–2 online) so the label cannot schedule four heavies even if a job skips the group | On the Mac host (`svc.sh stop`) |

**Ops checklist (shared Mac):**

1. Confirm light jobs are hosted (variable unset or `"ubuntu-latest"`).
2. Set **`MAC_SHARED_LOCK=1`** on this repo while multiple runners share the box.
3. Prefer **1–2** online Mac runners; use 4 only when load is proven quiet.
4. Expect heavies to queue (wall-clock longer, step times healthy) instead of
   10m Setup Node / 12m flutter builds from thrash.

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
6. **Serialize Mac heavies** — in-repo via job concurrency `tashil-mac-heavy`;
   cross-repo via `MAC_SHARED_LOCK` (see below). Do **not** edit `~/mac-resources` from CI.
7. **Paths** use `$HOME` / `ANDROID_HOME` / `$HOME/toolchains` — never `/Users/fathalla`.

## In-repo Mac job concurrency (`tashil-mac-heavy`)

Workflow-level `concurrency` only serializes **one workflow + one ref** (and cancels
superseded PR runs). It does **not** stop PR-A’s Flutter job and PR-B’s Playwright
smoke from both landing on `tashil-mac` at once.

Heavy Mac jobs therefore also set **job-level** concurrency:

```yaml
concurrency:
  group: tashil-mac-heavy
  cancel-in-progress: false
```

| Job | Workflow |
|-----|----------|
| `test-flutter` | `ci.yml` |
| `smoke-run` | `playwright_smoke.yml` |
| `deploy-backend` / `deploy-web` | `deploy.yml` |

`cancel-in-progress: false` is required so a new heavy does not kill an in-flight
deploy or flutter build. Superseded **PR** workflow runs still cancel via the
workflow-level group (non-`main` only).

This is complementary to `MAC_SHARED_LOCK`: the job group covers **this repo**; the
directory lock covers **other repos/bots** on the same Mac.

## Cross-repo Mac lock (`~/mac-resources/mac-lock.sh`)

Another repo’s runners on the same Mac can still overlap with our heavies. Heavy jobs
may book a **global** directory lock when opted in.

**Do not edit** `~/mac-resources` from this repo’s CI.

### Opt-in (`MAC_SHARED_LOCK`)

Lock is **off unless** repo variable / env `MAC_SHARED_LOCK=1`.

**Set `MAC_SHARED_LOCK=1` whenever multiple runner processes share one physical Mac**
(including `tashil-ci` with `tashil-mac`…`tashil-mac-4`). The old “unset on dedicated
tashil-ci” advice assumed exclusive single-runner use — four runners on one box still
need serialization (same-repo group + this lock for cross-repo).

Unset / omit the variable only when the Mac has a **single** online runner and no
other bots. Emulator **free-port** isolation stays on either way.

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
export MAC_SHARED_LOCK=1   # recommended while 2+ runners share one Mac
AGENT="ci-Tashil-Data-Sharing-${GITHUB_RUN_ID}-${GITHUB_JOB}"
bash scripts/mac_lock_ci.sh acquire "$AGENT" "omar-fathalla/Tashil-Data-Sharing" "<task>" <eta> <wait>
# … work …
bash scripts/mac_lock_ci.sh release "$AGENT"
```

| Job | `tashil-mac-heavy`? | Lock when `MAC_SHARED_LOCK=1`? | acquire step timeout | job timeout |
|-----|---------------------|-------------------------------|----------------------|-------------|
| Backend Go (+ emulator) | no (hosted by default) | yes (no-op on ubuntu) | 10m | 25m |
| Flutter analyze & test (run) | **yes** | yes | 8m | 35m |
| Playwright Semantics smoke (run) | **yes** | yes | 15m | 45m |
| Deploy backend / web | **yes** | no (group + deploy workflow queue) | — | 30m / 25m |
| Cloud Run pin / PR comment / path detect & gates | no | **no** | — | 5m (hosted via `CI_HOSTED_RUNNER`) |

Path filters (`dorny/paths-filter`): no workflow-level `paths-ignore` — workflows always
start so gates report. Backend Go, Cloud Run pin, Flutter, and Playwright heavy jobs
run only when their path filters match (any `.github/workflows/**` change sets all
filters true). Required checks report via lightweight gate jobs on `CI_HOSTED_RUNNER`
(`Backend Go tests`, `Cloud Run one-instance pin`, `Flutter analyze & test`,
`flutter-web-semantics-smoke`) so skips still show **success** (never hang required
checks / merge queue).

**Merge queue:** `ci.yml` and `playwright_smoke.yml` listen for `merge_group` so
required checks run in the queue. `deploy.yml` does **not** — production stays
one-deploy-per-merged-PR via `push` to `main` (`await-ci` → deploy → livez/health).

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

### Workflow-level (cancel superseded PR runs)

`ci.yml` and `playwright_smoke.yml`:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}
```

Superseded PR syncs cancel in-flight CI; **never cancel `main`**. **`deploy.yml` must
keep `cancel-in-progress: false`** — never cancel a production deploy.

### Job-level (Mac heavy serialize)

See **In-repo Mac job concurrency (`tashil-mac-heavy`)** above. Workflow concurrency
alone does **not** stop `tashil-mac`…`tashil-mac-4` from running different workflows
at once. Queueing levers: hosted lights, `tashil-mac-heavy`, `MAC_SHARED_LOCK=1`,
fewer online runners.

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
| Default (recommended) | leave `CI_*` unset | light → ubuntu; heavy/deploy → Mac |
| Serialize vs other bots on shared Mac | `MAC_SHARED_LOCK` | `1` (recommended while 2+ runners share one host) |
| Force light jobs to Mac (GitHub minutes / spending exhausted) | `CI_HOSTED_RUNNER` | `["self-hosted","macOS","tashil-mac"]` — also set `MAC_SHARED_LOCK=1` and/or reduce online runners |
| Explicit ubuntu for light jobs | `CI_HOSTED_RUNNER` | `"ubuntu-latest"` (JSON string — include the quotes) |
| Move heavy jobs to ubuntu (Mac offline) | `CI_RUNS_ON` | `["ubuntu-latest"]` |

**Important:** values must be valid JSON for `fromJSON`. A bare `ubuntu-latest` (no
quotes) is **not** valid — use `"ubuntu-latest"` or leave the var unset.

On Linux fallback, Playwright installs with `npx playwright install --with-deps chromium`.
Emulator isolation scripts still probe free ports (safe on ubuntu-latest too).

## Production deploy (`deploy.yml`)

Hybrid (#56) + await-ci (#41). Concurrency `group: ${{ github.workflow }}` with
`cancel-in-progress: false` (#55).

| Job | Runner | Notes |
|-----|--------|-------|
| `await-ci` | `CI_HOSTED_RUNNER` (ubuntu) | `if: github.ref == 'refs/heads/main'`; waits for `ci.yml` success; runs smoke unit test — **no** `test-backend` / `test-web` Mac duplicate |
| `deploy-backend` | `CI_RUNS_ON` (Mac) | job concurrency `tashil-mac-heavy` (`cancel-in-progress: false`); gcloud WIF; `CLOUDSDK_CONFIG` under `$RUNNER_TEMP`; hard-fail smoke `/api/v1/version` + `/livez` + `/api/v1/health`; timeout 30m |
| `deploy-web` | `CI_RUNS_ON` (Mac) | same `tashil-mac-heavy` group; Flutter detect/require-preinstalled; gcloud isolation; timeout 25m |

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
instead of scheduling four heavy workloads onto one host:

```bash
# Example: leave tashil-mac + tashil-mac-2 online
~/actions-runner-3/svc.sh stop
~/actions-runner-4/svc.sh stop
```

With `tashil-mac-heavy` + `MAC_SHARED_LOCK=1`, two online runners is usually enough
(one busy on the heavy, one free for rare non-grouped Mac work / faster pickup after
release). Four online runners without those levers recreates Setup Node / flutter
build thrash.

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
