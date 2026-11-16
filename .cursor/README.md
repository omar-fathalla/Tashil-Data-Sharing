# Cursor cloud agent environment

New agents start from a Build snapshot instead of reinstalling Flutter and Go every session. The image (`.cursor/Dockerfile`) holds the toolchains. The install script (`.cursor/install.sh`) only syncs lockfile dependencies and is what a Build runs once before snapshotting.

| Tool | Pin | Source |
| --- | --- | --- |
| Flutter | 3.41.2, web precache, analytics off | CI `FLUTTER_VERSION` |
| Go | 1.26.0 (`GOTOOLCHAIN=local`) | `backend-go/go.mod` |
| Node | 22.23.4 | Playwright smoke uses Node 22 |
| Java | OpenJDK 21 (Ubuntu 24.04 package) | Firestore emulator |
| Playwright | 1.65.0 Chromium plus Ubuntu 24.04 OS libraries | `e2e/package-lock.json` |

No `start` command: nothing has to stay running for `go test` or `flutter test`.

## Verify

```bash
bash .cursor/install.sh
cd backend-go && GOPROXY=off go test ./...
cd tashil_web && flutter analyze && flutter test
```

A second `bash .cursor/install.sh` should finish without downloading the Flutter SDK or the Go toolchain. Set `TASHIL_SKIP_PLAYWRIGHT_BROWSERS=1` to skip the Chromium download.

`backend-go/data` is not read or written by this setup.

## Dashboard

Committing this file does not by itself change an existing saved environment. Cursor uses a saved environment first, and that environment reads `.cursor/environment.json` only when its config-as-code location points at this file.

After this change is on `main`:

1. Open the saved environment [Tashil-Data-Sharing](https://cursor.com/dashboard/cloud-agents/environments/e/e2dfe2a2-dae8-11f1-8120-06b44be262b7) (`e2dfe2a2-dae8-11f1-8120-06b44be262b7`). It currently has no active build.
2. Set its environment.json location to `.cursor/environment.json` in this repository (Config as code).
3. Run a Build and wait until it succeeds. New agents that select this environment boot from that snapshot and skip `install`.

The personal environment `1dc2b5f3-dae8-11f1-8120-06b44be262b7` is dashboard-managed (`environmentJsonPath` empty) and will keep ignoring this file until its location is pointed here as well. Agents have to be started on an environment that records this file.
