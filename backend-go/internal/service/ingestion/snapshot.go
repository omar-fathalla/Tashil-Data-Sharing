package ingestion

import (
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Startup snapshot
//
// On boot the server used to re-parse every archived workbook (minutes on
// GCSFuse). After every successful data change we now also write a gzip'd JSON
// snapshot of the parsed in-memory dataset to <archive dir>/_snapshot/. On the
// next boot the snapshot is used only if it was written with the same schema and
// parser version (SnapshotParserVersion) and the archive, product-master and targets files are byte-for-byte
// the same set (name, size, mtime) as when it was taken. In every other case
// (missing, corrupt, stale, different build) the server falls back to the full
// Excel replay and then writes a fresh snapshot. The archive itself is never
// modified by this code.

const (
	// SnapshotSchemaVersion must be bumped whenever the snapshot layout changes.
	SnapshotSchemaVersion = 1
	snapshotDirName       = "_snapshot"
	snapshotFileName      = "state.json.gz"
	snapshotDebounce      = 5 * time.Second
)

// SnapshotStore is implemented by repositories whose in-memory state is rebuilt by the archive replay.
type SnapshotStore interface {
	ExportSnapshot() ([]byte, error)
	ImportSnapshot(raw []byte) error
}

// ManifestEntry describes one input file the in-memory state was derived from.
type ManifestEntry struct {
	Path    string `json:"path"`
	Size    int64  `json:"size"`
	ModTime int64  `json:"mod_time_unix_nano"`
}

type snapshotEnvelope struct {
	SchemaVersion int             `json:"schema_version"`
	BuildID       string          `json:"build_id"`
	CreatedAt     time.Time       `json:"created_at"`
	Manifest      []ManifestEntry `json:"manifest"`
	BigQuery      json.RawMessage `json:"bigquery"`
	Firestore     json.RawMessage `json:"firestore"`
}

type snapshotConfig struct {
	mu        sync.Mutex // serialises snapshot writes
	timerMu   sync.Mutex
	timer     *time.Timer
	extraDirs []string
	extraFile []string
	buildID   string
	disabled  bool
	// applied holds archive workbook base names whose data this instance has loaded. Once tracking is on,
	// a snapshot only lists those files, so uploads handled by OTHER instances are replayed on the next
	// boot instead of being assumed present.
	applied  sync.Map
	tracking atomic.Bool
	// rebuild, when set, replays the whole archive into separate stores and returns their
	// exported state, so a full rebuild can run in the background while the old state is served.
	rebuild func(ctx context.Context) (bq, fs []byte, err error)
}

// OnRebuilt runs after a background rebuild is swapped in (e.g. re-apply durable rows).
func (p *Processor) OnRebuilt(fn func()) *Processor {
	p.onRebuilt = fn
	return p
}

// WithBackgroundRebuild registers the off-line full rebuild used when the snapshot is outdated.
func (p *Processor) WithBackgroundRebuild(fn func(ctx context.Context) (bq, fs []byte, err error)) *Processor {
	p.snap.rebuild = fn
	return p
}

// ImportState replaces the live replayed state (same sections as the startup snapshot).
func (p *Processor) ImportState(bqRaw, fsRaw []byte) error {
	bq, fsr, ok := p.snapshotStores()
	if !ok {
		return errors.New("snapshot not supported")
	}
	if err := fsr.ImportSnapshot(fsRaw); err != nil {
		return err
	}
	return bq.ImportSnapshot(bqRaw)
}

// loadAnySnapshot imports a snapshot with the current schema regardless of build or archive
// changes. Used only to serve something immediately while a background rebuild runs.
func (p *Processor) loadAnySnapshot() error {
	f, err := os.Open(p.SnapshotPath())
	if err != nil {
		return err
	}
	defer f.Close()
	zr, err := gzip.NewReader(f)
	if err != nil {
		return err
	}
	var env snapshotEnvelope
	if err := json.NewDecoder(zr).Decode(&env); err != nil {
		return err
	}
	if env.SchemaVersion != SnapshotSchemaVersion || len(env.BigQuery) == 0 || len(env.Firestore) == 0 {
		return errors.New("snapshot unusable")
	}
	return p.ImportState(env.BigQuery, env.Firestore)
}

func (p *Processor) markArchiveApplied(path string) {
	if path != "" {
		p.snap.applied.Store(filepath.Base(path), true)
	}
}

var (
	buildIDOnce sync.Once
	buildIDVal  string
)

// SnapshotParserVersion identifies the parsing/state logic a snapshot was built with.
// Bump it whenever a change to the ingestion parsers or the in-memory models would make
// an existing snapshot produce different data. Unrelated deploys keep the snapshot valid,
// so a new build no longer forces a multi-minute full archive replay.
const SnapshotParserVersion = "parser-2026-11-01b-extended-price"

// currentBuildID returns the snapshot compatibility key (schema + parser version), not a
// hash of the binary, so the snapshot survives deploys that do not change parsing.
func currentBuildID() string {
	buildIDOnce.Do(func() {
		buildIDVal = fmt.Sprintf("schema-%d/%s", SnapshotSchemaVersion, SnapshotParserVersion)
	})
	return buildIDVal
}

// WithSnapshotInputs registers extra directories / files (product master, targets,
// seed workbooks) whose contents feed the in-memory state, so a change to any of
// them invalidates the snapshot.
func (p *Processor) WithSnapshotInputs(dirs []string, files []string) *Processor {
	p.snap.extraDirs = append(p.snap.extraDirs, dirs...)
	p.snap.extraFile = append(p.snap.extraFile, files...)
	return p
}

func (p *Processor) snapshotStores() (SnapshotStore, SnapshotStore, bool) {
	if p.snap.disabled || p.archiveDir == "" {
		return nil, nil, false
	}
	bq, ok1 := p.bqRepo.(SnapshotStore)
	fsr, ok2 := p.fsRepo.(SnapshotStore)
	if !ok1 || !ok2 {
		return nil, nil, false
	}
	return bq, fsr, true
}

// SnapshotPath is where the startup snapshot lives.
func (p *Processor) SnapshotPath() string {
	if p.archiveDir == "" {
		return ""
	}
	return filepath.Join(p.archiveDir, snapshotDirName, snapshotFileName)
}

func (p *Processor) buildID() string {
	if p.snap.buildID != "" {
		return p.snap.buildID
	}
	return currentBuildID()
}

// buildManifest lists every input file (sorted) with size and mtime.
func (p *Processor) buildManifest() ([]ManifestEntry, error) {
	var out []ManifestEntry
	addDir := func(label, root string) error {
		if root == "" {
			return nil
		}
		err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
			if err != nil {
				if path == root && errors.Is(err, fs.ErrNotExist) {
					return fs.SkipDir
				}
				return err
			}
			if d.IsDir() {
				if d.Name() == snapshotDirName || d.Name() == "_jobs" {
					return fs.SkipDir
				}
				return nil
			}
			info, err := d.Info()
			if err != nil {
				return err
			}
			rel, _ := filepath.Rel(root, path)
			out = append(out, ManifestEntry{Path: label + ":" + filepath.ToSlash(rel), Size: info.Size(), ModTime: info.ModTime().UnixNano()})
			return nil
		})
		if errors.Is(err, fs.SkipDir) {
			return nil
		}
		return err
	}
	if err := addDir("archive", p.archiveDir); err != nil {
		return nil, err
	}
	for i, d := range p.snap.extraDirs {
		if filepath.Clean(d) == filepath.Clean(p.archiveDir) {
			continue
		}
		if err := addDir(fmt.Sprintf("extra%d", i), d); err != nil {
			return nil, err
		}
	}
	for _, f := range p.snap.extraFile {
		info, err := os.Stat(f)
		if err != nil {
			out = append(out, ManifestEntry{Path: "file:" + f, Size: -1})
			continue
		}
		out = append(out, ManifestEntry{Path: "file:" + f, Size: info.Size(), ModTime: info.ModTime().UnixNano()})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Path < out[j].Path })
	return out, nil
}

// WriteSnapshot captures the current in-memory dataset. It refuses to write if
// an input file changed while the state was being captured.
//
// The export is ~430MB of JSON in prod, so it runs behind the heavy-work gate (never alongside a replay)
// and is streamed straight into the gzip file instead of being re-encoded into extra in-memory copies.
func (p *Processor) WriteSnapshot() error {
	var err error
	p.withHeavy(func() { err = p.writeSnapshotGated() })
	return err
}

// writeSnapshotGated is WriteSnapshot for callers that already hold heavyMu.
func (p *Processor) writeSnapshotGated() error {
	bq, fsr, ok := p.snapshotStores()
	if !ok {
		return nil
	}
	p.snap.mu.Lock()
	defer p.snap.mu.Unlock()

	before, err := p.buildManifest()
	if err != nil {
		return fmt.Errorf("snapshot manifest: %w", err)
	}
	bqRaw, err := bq.ExportSnapshot()
	if err != nil {
		return err
	}
	fsRaw, err := fsr.ExportSnapshot()
	if err != nil {
		return err
	}
	after, err := p.buildManifest()
	if err != nil {
		return fmt.Errorf("snapshot manifest: %w", err)
	}
	if !reflect.DeepEqual(before, after) {
		return errors.New("snapshot skipped: archive changed while capturing state")
	}
	if p.snap.tracking.Load() {
		kept := after[:0:0]
		for _, e := range after {
			if strings.HasPrefix(e.Path, "archive:") && !isArchiveMetadataPath(e.Path) {
				if _, ok := p.snap.applied.Load(filepath.Base(e.Path)); !ok {
					continue
				}
			}
			kept = append(kept, e)
		}
		after = kept
	}
	head, err := json.Marshal(struct {
		SchemaVersion int             `json:"schema_version"`
		BuildID       string          `json:"build_id"`
		CreatedAt     time.Time       `json:"created_at"`
		Manifest      []ManifestEntry `json:"manifest"`
	}{SnapshotSchemaVersion, p.buildID(), time.Now().UTC(), after})
	if err != nil {
		return fmt.Errorf("snapshot encode: %w", err)
	}
	if !json.Valid(bqRaw) || !json.Valid(fsRaw) {
		return errors.New("snapshot encode: store export is not valid JSON")
	}

	target := p.SnapshotPath()
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return fmt.Errorf("snapshot mkdir: %w", err)
	}
	tmp, err := os.CreateTemp(filepath.Dir(target), ".state-*.tmp")
	if err != nil {
		return fmt.Errorf("snapshot temp: %w", err)
	}
	tmpName := tmp.Name()
	fail := func(stage string, err error) error {
		tmp.Close()
		_ = os.Remove(tmpName)
		return fmt.Errorf("snapshot %s: %w", stage, err)
	}
	// Same envelope as snapshotEnvelope (decoded by loadSnapshotIncremental), written piece by piece:
	// {head fields..., "bigquery": <raw>, "firestore": <raw>}
	cw := &countingWriter{w: tmp}
	zw := gzip.NewWriter(cw)
	for _, part := range [][]byte{head[:len(head)-1], []byte(`,"bigquery":`), bqRaw, []byte(`,"firestore":`), fsRaw, []byte("}\n")} {
		if _, err := zw.Write(part); err != nil {
			return fail("write", err)
		}
	}
	bqRaw, fsRaw = nil, nil
	if err := zw.Close(); err != nil {
		return fail("gzip", err)
	}
	if err := tmp.Sync(); err != nil {
		return fail("sync", err)
	}
	if err := tmp.Close(); err != nil {
		_ = os.Remove(tmpName)
		return fmt.Errorf("snapshot close: %w", err)
	}
	if err := os.Rename(tmpName, target); err != nil {
		_ = os.Remove(tmpName)
		return fmt.Errorf("snapshot rename: %w", err)
	}
	size := cw.n
	log.Printf("[Tashil Snapshot] Wrote %s (%d bytes, %d input files)", target, size, len(after))
	return nil
}

// ScheduleSnapshot writes a snapshot shortly after the last data change (debounced).
func (p *Processor) ScheduleSnapshot() {
	if _, _, ok := p.snapshotStores(); !ok || p.replaying.Load() {
		return
	}
	p.snap.timerMu.Lock()
	defer p.snap.timerMu.Unlock()
	if p.snap.timer != nil {
		p.snap.timer.Stop()
	}
	p.snap.timer = time.AfterFunc(snapshotDebounce, func() {
		if err := p.WriteSnapshot(); err != nil {
			log.Printf("[Tashil Snapshot] %v", err)
		}
	})
}

// loadSnapshot restores state from the snapshot if it is present, intact and current.
func (p *Processor) loadSnapshot() error {
	_, err := p.loadSnapshotIncremental()
	return err
}

// isArchiveMetadataPath reports manifest paths that hold archive metadata, not uploaded workbooks.
// They change on every upload (sidecars, legacy index, tombstones) and do not need a data replay.
func isArchiveMetadataPath(path string) bool {
	if !strings.HasPrefix(path, "archive:") {
		return false
	}
	rel := strings.TrimPrefix(path, "archive:")
	base := rel
	if i := strings.LastIndex(rel, "/"); i >= 0 {
		base = rel[i+1:]
	}
	return base == "index.json" || base == "deleted_tombstones.json" || strings.HasSuffix(base, ".tmp") ||
		strings.Contains(rel, "/"+archiveSidecarDir+"/") || strings.HasPrefix(rel, "_")
}

// diffSnapshotManifest compares the snapshot's inputs with the files on disk. It returns the archived
// workbooks that are new or changed since the snapshot. needFull is true when a workbook was removed or a
// non-archive input (seed files) changed; those cannot be applied incrementally.
func diffSnapshotManifest(snap, current []ManifestEntry) (added []string, needFull bool) {
	snapMap := make(map[string]ManifestEntry, len(snap))
	for _, e := range snap {
		snapMap[e.Path] = e
	}
	curMap := make(map[string]bool, len(current))
	for _, e := range current {
		curMap[e.Path] = true
		old, ok := snapMap[e.Path]
		if ok && old == e {
			continue
		}
		if isArchiveMetadataPath(e.Path) {
			continue
		}
		if !strings.HasPrefix(e.Path, "archive:") {
			return nil, true
		}
		added = append(added, strings.TrimPrefix(e.Path, "archive:"))
	}
	for _, e := range snap {
		if !curMap[e.Path] && !isArchiveMetadataPath(e.Path) {
			return nil, true
		}
	}
	return added, false
}

// loadSnapshotIncremental restores the snapshot and returns the archived workbooks added since it was
// written; the caller replays only those files.
func (p *Processor) loadSnapshotIncremental() ([]string, error) {
	bq, fsr, ok := p.snapshotStores()
	if !ok {
		return nil, errors.New("snapshot not supported")
	}
	f, err := os.Open(p.SnapshotPath())
	if err != nil {
		return nil, fmt.Errorf("no snapshot: %w", err)
	}
	defer f.Close()
	zr, err := gzip.NewReader(f)
	if err != nil {
		return nil, fmt.Errorf("snapshot corrupt: %w", err)
	}
	var env snapshotEnvelope
	if err := json.NewDecoder(zr).Decode(&env); err != nil {
		return nil, fmt.Errorf("snapshot corrupt: %w", err)
	}
	if _, err := io.Copy(io.Discard, zr); err != nil {
		return nil, fmt.Errorf("snapshot corrupt: %w", err)
	}
	if env.SchemaVersion != SnapshotSchemaVersion {
		return nil, fmt.Errorf("snapshot schema %d != %d", env.SchemaVersion, SnapshotSchemaVersion)
	}
	if env.BuildID == "" || env.BuildID != p.buildID() {
		return nil, errors.New("snapshot was written by a different server build")
	}
	current, err := p.buildManifest()
	if err != nil {
		return nil, fmt.Errorf("snapshot manifest: %w", err)
	}
	added, needFull := diffSnapshotManifest(env.Manifest, current)
	if needFull {
		return nil, fmt.Errorf("snapshot stale: archive files changed (%d in snapshot, %d on disk)", len(env.Manifest), len(current))
	}
	if len(env.BigQuery) == 0 || len(env.Firestore) == 0 {
		return nil, errors.New("snapshot corrupt: missing sections")
	}
	if err := fsr.ImportSnapshot(env.Firestore); err != nil {
		return nil, err
	}
	if err := bq.ImportSnapshot(env.BigQuery); err != nil {
		return nil, err
	}
	for _, e := range env.Manifest {
		if strings.HasPrefix(e.Path, "archive:") && !isArchiveMetadataPath(e.Path) {
			p.markArchiveApplied(e.Path)
		}
	}
	return added, nil
}

// RestoreOrReplay loads the startup snapshot when valid; otherwise it performs
// the full archive replay and writes a fresh snapshot. It returns which path was used.
func (p *Processor) RestoreOrReplay(ctx context.Context) (string, error) {
	p.snap.tracking.Store(true)
	start := time.Now()
	if added, err := p.loadSnapshotIncremental(); err == nil {
		log.Printf("[Tashil Snapshot] Startup restored from snapshot %s in %s", p.SnapshotPath(), time.Since(start).Round(time.Millisecond))
		if len(added) == 0 {
			return "snapshot", nil
		}
		// Apply only the uploads made since the snapshot instead of replaying the whole archive.
		incStart := time.Now()
		rerr := p.replayArchivedPaths(ctx, added)
		log.Printf("[Tashil Snapshot] Incremental replay of %d new archive file(s) took %s", len(added), time.Since(incStart).Round(time.Millisecond))
		if rerr == nil {
			p.ScheduleSnapshot()
		}
		return "snapshot+incremental", rerr
	} else {
		log.Printf("[Tashil Snapshot] Snapshot not used (%v); falling back to full archive replay", err)
	}
	if p.snap.rebuild != nil {
		if err := p.loadAnySnapshot(); err == nil {
			log.Printf("[Tashil Snapshot] Serving the previous snapshot now; full rebuild runs in the background")
			go p.runBackgroundRebuild(ctx)
			return "stale-snapshot+background-rebuild", nil
		}
	}
	// Make sure a partially imported snapshot can never leak into the replayed state.
	_ = p.bqRepo.ClearTenantData(ctx, "all")
	_ = p.fsRepo.ClearTenantData(ctx, "all")
	var err error
	p.withHeavy(func() {
		replayStart := time.Now()
		err = p.ReplayArchivedFilesToDatabase(ctx)
		log.Printf("[Tashil Snapshot] Full archive replay took %s", time.Since(replayStart).Round(time.Millisecond))
		if err == nil {
			// Persist right away so the next cold start (or another instance) restores instead of replaying.
			if werr := p.writeSnapshotGated(); werr != nil {
				log.Printf("[Tashil Snapshot] Could not write snapshot after replay: %v", werr)
			}
		}
	})
	return "replay", err
}

// isSnapshotMutation reports whether a successful request may have changed replayed data.
func IsSnapshotMutation(method, path string) bool {
	if method == "GET" || method == "HEAD" || method == "OPTIONS" {
		return false
	}
	return strings.HasPrefix(path, "/api/v1/ingest/") ||
		strings.HasPrefix(path, "/api/v1/product-master") ||
		strings.HasPrefix(path, "/api/v1/analytics/targets")
}

func (p *Processor) runBackgroundRebuild(ctx context.Context) {
	// At most one rebuild per instance at a time.
	if !p.rebuilding.CompareAndSwap(false, true) {
		log.Printf("[Tashil Snapshot] Background rebuild already running on this instance; skipped")
		return
	}
	defer p.rebuilding.Store(false)
	// At most one full rebuild across instances; the others adopt its snapshot.
	run, release := p.acquireRebuild(ctx)
	defer release()
	if !run {
		return
	}
	start := time.Now()
	swapped := false
	p.withHeavy(func() {
		bqRaw, fsRaw, err := p.snap.rebuild(ctx)
		if err != nil {
			log.Printf("[Tashil Snapshot] Background rebuild failed after %s: %v", time.Since(start).Round(time.Millisecond), err)
			return
		}
		if err := p.ImportState(bqRaw, fsRaw); err != nil {
			log.Printf("[Tashil Snapshot] Background rebuild import failed: %v", err)
			return
		}
		bqRaw, fsRaw = nil, nil
		swapped = true
		// Everything on disk at rebuild time is now loaded.
		if man, err := p.buildManifest(); err == nil {
			for _, e := range man {
				if strings.HasPrefix(e.Path, "archive:") && !isArchiveMetadataPath(e.Path) {
					p.markArchiveApplied(e.Path)
				}
			}
		}
		log.Printf("[Tashil Snapshot] Background rebuild swapped in after %s", time.Since(start).Round(time.Millisecond))
		if err := p.writeSnapshotGated(); err != nil {
			log.Printf("[Tashil Snapshot] Could not write snapshot after background rebuild: %v", err)
		}
	})
	if swapped && p.onRebuilt != nil {
		p.onRebuilt()
	}
}

type countingWriter struct {
	w io.Writer
	n int64
}

func (c *countingWriter) Write(b []byte) (int, error) {
	n, err := c.w.Write(b)
	c.n += int64(n)
	return n, err
}
