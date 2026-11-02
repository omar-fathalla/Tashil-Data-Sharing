package bqsink

import (
	"bytes"
	"encoding/json"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestLoadChunksCoverAllRowsOnce(t *testing.T) {
	got := LoadChunks(45001, 20000)
	want := [][2]int{{0, 20000}, {20000, 40000}, {40000, 45001}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("chunks %v", got)
	}
	if len(LoadChunks(0, 20000)) != 0 {
		t.Fatal("no rows, no chunks")
	}
}

// Streamed plans must encode exactly the rows the materialised plan holds, chunk by chunk.
func TestStreamSellInMatchesPlanSellIn(t *testing.T) {
	now := time.Date(2026, 11, 2, 8, 0, 0, 0, time.UTC)
	recs := make([]domain.SellInRecord, 7)
	for i := range recs {
		recs[i] = domain.SellInRecord{RecordID: "r" + string(rune('a'+i)), Year: 2026, MonthNum: i%12 + 1, RetailerChain: "Fathalla", NetValueEGP: float64(i)}
	}
	meta := Meta{TenantID: "adeco", ArchiveID: "arch_x", SourceFile: "in26.xlsx", BatchID: "b1"}
	full := PlanSellIn(meta, recs, now)
	stream := StreamSellIn(meta, recs, now)
	if stream.Rows != nil || stream.Len() != len(recs) || full.Len() != len(recs) {
		t.Fatalf("lengths: stream rows=%v len=%d full=%d", stream.Rows != nil, stream.Len(), full.Len())
	}
	var a, b bytes.Buffer
	enc := json.NewEncoder(&a)
	for _, r := range full.Rows {
		_ = enc.Encode(r)
	}
	for _, c := range LoadChunks(stream.Len(), 3) {
		if err := EncodeRows(&b, stream, c[0], c[1]); err != nil {
			t.Fatal(err)
		}
	}
	if a.String() != b.String() || strings.Count(b.String(), "\n") != len(recs) {
		t.Fatal("chunked streamed rows differ from the materialised plan")
	}
}

func TestStreamSellOutMatchesPlanSellOut(t *testing.T) {
	now := time.Date(2026, 11, 2, 8, 0, 0, 0, time.UTC)
	facts := []domain.SellOutFact{{RecordID: "1", TransactionDate: "2026-03-04"}, {RecordID: "2", TransactionDate: "2025-12-31"}}
	meta := Meta{TenantID: "adeco", ArchiveID: "arch_y"}
	full := PlanSellOut(meta, facts, ModeUpsertRecords, now)
	stream := StreamSellOut(meta, facts, ModeUpsertRecords, now)
	for i := range facts {
		if !reflect.DeepEqual(full.Rows[i], stream.Row(i)) {
			t.Fatalf("row %d differs", i)
		}
	}
}
