package bqsink

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"cloud.google.com/go/bigquery"
	"google.golang.org/api/iterator"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// SellInReadSQL (tableRef already back-quoted) returns the query that loads every sell-in row of one tenant, in upload order
// (source file, plan month, original row number) so the rebuilt in-memory slice matches a fresh parse.
func SellInReadSQL(tableRef string) string {
	return "SELECT * FROM " + tableRef + " WHERE tenant_id = @tenant_id" +
		" ORDER BY ingested_at, source_file, period_month," +
		" SAFE_CAST(REGEXP_EXTRACT(record_id, r'_(\\d+)$') AS INT64), record_id"
}

// DecodeSellInRow converts one sell_in_records row back to a domain record. Meta columns that share a
// JSON name with the struct (tenant_id, batch_id, ingested_at) are mapped back onto it.
func DecodeSellInRow(row map[string]bigquery.Value) (domain.SellInRecord, error) {
	m := make(map[string]interface{}, len(row))
	for k, v := range row {
		switch k {
		case ColArchiveID, ColSourceFile, ColPartitionDate, ColPeriodMonth, ColChainKey:
			continue
		}
		if t, ok := v.(time.Time); ok {
			m[k] = t.UTC().Format(time.RFC3339Nano)
			continue
		}
		m[k] = v
	}
	b, err := json.Marshal(m)
	if err != nil {
		return domain.SellInRecord{}, err
	}
	var r domain.SellInRecord
	if err := json.Unmarshal(b, &r); err != nil {
		return domain.SellInRecord{}, fmt.Errorf("decode sell_in row: %w", err)
	}
	if strings.TrimSpace(r.SourceFilename) == "" {
		if s, ok := row[ColSourceFile].(string); ok {
			r.SourceFilename = s
		}
	}
	return r, nil
}

// ReadSellIn loads all durable sell-in records of a tenant. A missing table reads as zero rows.
func (s *BigQuerySink) ReadSellIn(ctx context.Context, tenantID string) ([]domain.SellInRecord, error) {
	q := s.client.Query(SellInReadSQL(s.ref(TableSellIn)))
	q.Parameters = []bigquery.QueryParameter{{Name: "tenant_id", Value: NormalizeTenant(tenantID)}}
	it, err := q.Read(ctx)
	if err != nil {
		if strings.Contains(err.Error(), "notFound") || strings.Contains(err.Error(), "Not found: Table") {
			return nil, nil
		}
		return nil, fmt.Errorf("read sell_in_records: %w", err)
	}
	var out []domain.SellInRecord
	for {
		var row map[string]bigquery.Value
		err := it.Next(&row)
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("read sell_in_records: %w", err)
		}
		r, err := DecodeSellInRow(row)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, nil
}
