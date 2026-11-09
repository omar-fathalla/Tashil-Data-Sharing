package bigquery

import (
	"context"
	"errors"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

type blockingAggWriter struct {
	started chan struct{}
	release chan struct{}
	err     error
	calls   atomic.Int32
}

func (b *blockingAggWriter) WriteAnalyticsAggregates(context.Context, *domain.AnalyticsAggregates) error {
	b.calls.Add(1)
	select {
	case <-b.started:
	default:
		close(b.started)
	}
	<-b.release
	return b.err
}

func TestMaterializeAnalyticsAggregatesWaitsForBQWriteAndReturnsError(t *testing.T) {
	c := newSeededTestClient(t)
	started := make(chan struct{})
	release := make(chan struct{})
	w := &blockingAggWriter{started: started, release: release, err: errors.New("mirror boom")}
	c.AttachAggregatesWriterForSyncMirror(w, "tenant-adeco")
	c.DisableBackgroundAggregatesMirror()

	done := make(chan error, 1)
	go func() {
		_, err := c.MaterializeAnalyticsAggregates(context.Background(), "tenant-adeco")
		done <- err
	}()

	select {
	case <-started:
	case <-time.After(backgroundComputeWait):
		t.Fatal("Materialize never reached WriteAnalyticsAggregates")
	}

	select {
	case err := <-done:
		t.Fatalf("Materialize returned before sync write finished: %v", err)
	case <-time.After(100 * time.Millisecond):
	}

	close(release)
	err := <-done
	if err == nil || !strings.Contains(err.Error(), "mirror boom") {
		t.Fatalf("want mirror boom, got %v", err)
	}
	if w.calls.Load() != 1 {
		t.Fatalf("writes=%d", w.calls.Load())
	}
}

func TestDisableBackgroundAggregatesMirrorSkipsAsyncGetWrite(t *testing.T) {
	c := newSeededTestClient(t)
	w := &fakeAggWriter{got: make(chan *domain.AnalyticsAggregates, 4)}
	c.AttachAggregatesWriterForSyncMirror(w, "tenant-adeco")
	c.DisableBackgroundAggregatesMirror()

	if _, err := c.GetAnalyticsAggregates(context.Background(), "tenant-adeco"); err != nil {
		t.Fatal(err)
	}
	select {
	case <-w.got:
		t.Fatal("GetAnalyticsAggregates must not async-mirror when background disabled")
	case <-time.After(200 * time.Millisecond):
	}

	if _, err := c.MaterializeAnalyticsAggregates(context.Background(), "tenant-adeco"); err != nil {
		t.Fatal(err)
	}
	select {
	case <-w.got:
	case <-time.After(backgroundComputeWait):
		t.Fatal("Materialize must write synchronously")
	}
}
