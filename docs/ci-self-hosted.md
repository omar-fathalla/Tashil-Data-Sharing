# Self-hosted CI runbook (tashil-mac)

CI uses **hosted ubuntu for portable jobs**; Mac self-hosted is **deploy-only**
until WIF/ubuntu deploy is tested:

| Class | Jobs | Runner var | Default |
|-------|------|------------|---------|
| Portable CI | Path detect, Cloud Run pin, Go tests, Flutter analyze/test, Playwright smoke + gates, PR comment | `CI_HOSTED_RUNNER` | `ubuntu-latest` (GitHub-hosted) |
| Deploy | `deploy-gate` / `deploy-backend` / `deploy-web` (≤30m) | `CI_RUNS_ON` | `["self-hosted","macOS","tashil-mac"]` |

**Never** use GitHub-hosted macOS runners (`macos-latest`) / larger / paid runners.
`deploy.yml` keeps `cancel-in-progress: false` so production deploys are never
cancelled mid-flight.

**Public repo Mac safety:** `deploy.yml` has no `pull_request` /
`pull_request_target` triggers. Deploy jobs require same-repo `workflow_run` on
`main` (or `workflow_dispatch`). Every job also has a refuse step that fails
closed if a fork PR somehow lands on `self-hosted`. Keep `CI_HOSTED_RUNNER`
unset (ubuntu) while public — do not point it at Mac for budget fallback unless
you accept that only non-fork events should use that fallback.

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
| **Hosted portable CI** | Path detect, Cloud Run pin, Backend Go, Flutter analyze/test, Playwright smoke + gates stay on `CI_HOSTED_RUNNER` (default `ubuntu-latest`) so PR CI never competes for Mac CPU/disk | Already in workflows — leave `CI_HOSTED_RUNNER` unset (or `"ubuntu-latest"`). **Do not** point it at Mac while the repo is public |
| **Job group `tashil-deploy`** | Deploy-only: `deploy-backend` / `deploy-web` serialize one-at-a-time (`cancel-in-progress: false`). Not shared with PR/test jobs | Wired in `deploy.yml` |
| **`MAC_SHARED_LOCK=1`** | Cross-repo directory lock (`~/mac-resources/LOCK.d`) so other bots/repos on the same Mac serialize with deploy / rare Mac fallback | Repo variable (Actions → Variables) |
| **Fewer online runners** | Stop `tashil-mac-3` / `tashil-mac-4` (leave 1–2 online) so the label cannot schedule four heavies | On the Mac host (`svc.sh stop`) |

**Ops checklist (shared Mac):**

1. Confirm portable CI is hosted (variable unset or `"ubuntu-latest"`).
2. Set **`MAC_SHARED_LOCK=1`** on this repo while multiple runners share the box.
3. Prefer **1–2** online Mac runners; use 4 only when load is proven quiet.
4. Deploy stays Mac via `workflow_run` (#97) — no await-ci busy-wait.

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
6. **Serialize Mac work carefully** — PR/test heavies queue on the runners (no shared
   job group); deploys use `tashil-deploy`; cross-repo via `MAC_SHARED_LOCK` (see
   below). Do **not** edit `~/mac-resources` from CI.
7. **Paths** use `$HOME` / `ANDROID_HOME` / `$HOME/toolchains` — never `/Users/fathalla`.

## Mac job concurrency (no shared `tashil-mac-heavy`)

Workflow-level `concurrency` only serializes **one workflow + one ref** (and cancels
superseded PR runs). It does **not** stop PR-A’s Flutter job and PR-B’s Playwright
smoke from both landing on `tashil-mac` at once — that is fine: the runner queue
holds them without cancelling.

**Pending-slot eviction (do not reintroduce a shared group):** GitHub keeps only
**one pending** job per concurrency group even with `cancel-in-progress: false`
(that flag protects only the *running* job). A second pending job **cancels** the
first. Evidence: #66 CI `test-flutter` cancelled (`runner_id=0`) when main deploy
entered the shared group ~3s after `deploy-backend` finished. A check-then-enter
wait (`wait_mac_heavy_free.sh`) still races: two jobs can both see idle then both
pending.

| Job | Concurrency |
|-----|-------------|
| `test-flutter` / `smoke-run` | **none** (hosted ubuntu by default; lock no-ops) |
| `deploy-backend` / `deploy-web` | job group `tashil-deploy` (`cancel-in-progress: false`) |

```yaml
# deploy.yml only
concurrency:
  group: tashil-deploy
  cancel-in-progress: false
```

`scripts/wait_mac_heavy_free.sh` is retained but unused (legacy). Prefer runner
queue + `MAC_SHARED_LOCK` over a shared job concurrency group for PR/test heavies.

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

| Job | Job concurrency? | Lock when `MAC_SHARED_LOCK=1`? | acquire step timeout | job timeout |
|-----|-------------------|-------------------------------|----------------------|-------------|
| Backend Go (+ emulator) | no (hosted ubuntu) | yes (no-op on ubuntu) | 10m | 45m |
| Flutter analyze & test (run) | no (hosted ubuntu) | yes (no-op on ubuntu) | 8m | 45m |
| Playwright Semantics smoke (run) | no (hosted ubuntu) | yes (no-op on ubuntu) | 15m | 45m |
| Wait CI Flutter (smoke) | no (hosted) | **no** (poll only) | — | 45m (deadline 40m) |
| Deploy gate | no (Mac) | **no** | — | 5m |
| Deploy backend / web | **`tashil-deploy`** (Mac) | no (deploy group + workflow queue) | — | 30m / 30m |
| Cloud Run pin / PR comment / path detect & gates | no | **no** | — | 5m (hosted via `CI_HOSTED_RUNNER`) |

Path filters (`dorny/paths-filter`): no workflow-level `paths-ignore` — workflows always
start so gates report. Backend Go, Cloud Run pin, Flutter, and Playwright heavy jobs
run only when their path filters match (any `.github/workflows/**` change sets all
filters true). Required checks report via lightweight gate jobs on `CI_HOSTED_RUNNER`
(`Backend Go tests`, `Cloud Run one-instance pin`, `Flutter analyze & test`,
`flutter-web-semantics-smoke`) so skips still show **success** (never hang required
checks / merge queue).

**Hosted work jobs stay in the graph:** `test-backend`, `guard-cloud-run-one-instance`,
and smoke `wait-ci-flutter` use `if: always() && !cancelled() && needs.changes.result == 'success'`
and path-skip inside the job. That avoids `needs.*.result=abandoned` when a job-level
path `if:` drops the node (seen on main `db5888d` / #71 and smoke on #72/#73).
`smoke-run` (hosted) schedules only when `wait-ci-flutter.outputs.run_smoke == 'true'`
so docs-only PRs do not spin a heavy runner. `test-flutter` keeps its job-level path
`if:`. Gates fail clearly on `abandoned` / `cancelled` and tell you to use
**Re-run all jobs** (not Re-run failed jobs — successful deps like `changes` become
`abandoned` on failed-only re-runs).

**Merge queue:** `ci.yml` and `playwright_smoke.yml` listen for `merge_group` so
required checks run in the queue. `deploy.yml` does **not** — production deploys
via `workflow_run` after **CI tests** succeeds on `main` (`deploy-gate` →
deploy → livez/health). No runner busy-wait.

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

### Job-level (deploy serialize only)

See **Mac job concurrency** above. PR/test Mac heavies rely on the runner queue
(no shared group — avoids pending-slot eviction). Deploy uses `tashil-deploy`.
Other levers: hosted lights, `MAC_SHARED_LOCK=1`, prefer 1–2 online runners.

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
# Portable CI (default GitHub-hosted ubuntu):
runs-on: ${{ fromJSON(vars.CI_HOSTED_RUNNER || '"ubuntu-latest"') }}

# Deploy jobs (default Mac self-hosted; keep until WIF/ubuntu tested):
runs-on: ${{ fromJSON(vars.CI_RUNS_ON || '["self-hosted", "macOS", "tashil-mac"]') }}
```

Settings → Secrets and variables → Actions → Variables:

| Goal | Variable | Value (exact) |
|------|----------|---------------|
| Default (recommended) | leave `CI_*` unset | portable CI → ubuntu; deploy → Mac |
| Serialize vs other bots on shared Mac | `MAC_SHARED_LOCK` | `1` (recommended while 2+ runners share one host) |
| Force portable CI to Mac (GitHub minutes exhausted) | `CI_HOSTED_RUNNER` | `["self-hosted","macOS","tashil-mac"]` — **avoid while public** (fork PRs blocked by refuse step, but prefer hosted) |
| Explicit ubuntu for portable CI | `CI_HOSTED_RUNNER` | `"ubuntu-latest"` (JSON string — include the quotes) |
| Move deploy to ubuntu (after WIF tested) | `CI_RUNS_ON` | `["ubuntu-latest"]` |

**Important:** values must be valid JSON for `fromJSON`. A bare `ubuntu-latest` (no
quotes) is **not** valid — use `"ubuntu-latest"` or leave the var unset.

On Linux fallback, Playwright installs with `npx playwright install --with-deps chromium`.
Emulator isolation scripts still probe free ports (safe on ubuntu-latest too).

## Job timeout policy (Mac runners)

Four `tashil-mac*` runners share one physical Mac. A job that busy-waits for hours
holds a runner slot and deadlocks the queue (seen: deploy `await-ci` ~2.5h after
#95 routed all jobs to Mac). **Every job must set `timeout-minutes`:**

| Class | Jobs | `timeout-minutes` |
|-------|------|-------------------|
| Path detect + gates | `changes`, `*-gate`, Cloud Run pin, PR comment, deploy `deploy-gate`, smoke gate | **5** |
| Test / heavy | `test-backend`, `test-flutter`, `smoke-run`, `wait-ci-flutter` | **~45** (`test-backend` ≥40 per #96 headroom) |
| Deploy | `deploy-backend`, `deploy-web` | **30** |

Never use multi-hour timeouts for polling. Prefer event triggers (`workflow_run`)
over sleep-loops on Mac.

## Production deploy (`deploy.yml`)

Hybrid (#56) + **workflow_run** (replaces await-ci busy-wait from #41). Concurrency
`group: ${{ github.workflow }}` with `cancel-in-progress: false` (#55).

**Triggers:** `workflow_run` of workflow name `CI tests` / `types: [completed]` /
`branches: [main]` (jobs require `conclusion == success`), plus `workflow_dispatch`.
No `push` trigger — avoids scheduling deploy beside CI on the same Mac pool.

**Path skip:** `workflow_run` cannot use `paths-ignore`. `deploy-gate` skips when the
CI-green commit only touched `**.md`, `docs/**`, `LICENSE`, `.gitignore`, or
`.github/workflows/**` (CI-only workflow edits must not deploy).

| Job | Runner | Notes |
|-----|--------|-------|
| `deploy-gate` | `CI_RUNS_ON` (Mac until WIF/ubuntu tested) | 5m; same-repo success-only `workflow_run` on `main` / dispatch; path skip; outputs `sha` + `should_deploy` — **no** polling; no PR triggers |
| `deploy-backend` | `CI_RUNS_ON` (Mac) | job concurrency `tashil-deploy` (`cancel-in-progress: false`); checks out gate SHA; smoke unit test; gcloud WIF; `CLOUDSDK_CONFIG` under `$RUNNER_TEMP`; hard-fail smoke `/api/v1/version` + `/livez` + `/api/v1/health`; timeout 30m; `--max-instances=1` unchanged |
| `deploy-web` | `CI_RUNS_ON` (Mac) | same `tashil-deploy` group; Flutter detect/require-preinstalled; gcloud isolation; timeout 30m |

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

With `MAC_SHARED_LOCK=1` + `tashil-deploy` for production, two online runners is
usually enough. Four online runners without the lock recreates Setup Node /
flutter build thrash; prefer 1–2 online when the Mac is shared.

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
