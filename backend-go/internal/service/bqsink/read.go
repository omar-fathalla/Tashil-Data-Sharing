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
//
// Every uploaded file is stored in full (keyed by archive_id). The read view rebuilds the in-memory
// SetSellInRecords semantics: for each (chain, month) only the most recently ingested batch is served.
func SellInReadSQL(tableRef string) string {
	return "WITH t AS (SELECT * FROM " + tableRef + " WHERE tenant_id = @tenant_id)," +
		" win AS (SELECT IFNULL(chain_key, '') ck, IFNULL(period_month, '') pm," +
		" ARRAY_AGG(batch_id ORDER BY ingested_at DESC, batch_id DESC LIMIT 1)[OFFSET(0)] wb FROM t GROUP BY 1, 2)" +
		" SELECT t.* FROM t JOIN win ON IFNULL(t.chain_key, '') = win.ck AND IFNULL(t.period_month, '') = win.pm AND t.batch_id = win.wb" +
		" ORDER BY ingested_at, source_file, period_month," +
		" SAFE_CAST(REGEXP_EXTRACT(record_id, r'_(\\d+)$') AS INT64), record_id"
}

// DecodeSellInRow converts one sell_in_records row back to a domain record. Meta columns that share a
// JSON name with the struct (tenant_id, batch_id, ingested_at) are mapped back onto it.
func DecodeSellInRow(row map[string]bigquery.Value) (domain.SellInRecord, error) {
	m := make(map[string]interface{}, len(row))
	for k, v := range row {
		switch k {
		case ColArchiveID, ColSourceFile, ColPartitionDate, ColPeriodMonth, ColChainKey, ColWriteMode:
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

// SellOutReadSQL (tableRef already back-quoted) loads every sell-out row of one tenant in a stable order.
//
// Every uploaded file is stored in full (keyed by archive_id). The view rebuilds the in-memory semantics:
// a replace_periods file (rows without write_mode are legacy wide-matrix uploads) owns each (chain, month)
// it covers, so only the latest such batch is served there and older upsert rows for that period are hidden;
// upsert_records rows then dedupe by record_id, latest ingest wins.
func SellOutReadSQL(tableRef string) string {
	return "WITH t AS (SELECT * FROM " + tableRef + " WHERE tenant_id = @tenant_id)," +
		" win AS (SELECT IFNULL(chain_key, '') ck, IFNULL(period_month, '') pm," +
		" ARRAY_AGG(STRUCT(batch_id AS b, ingested_at AS ts) ORDER BY ingested_at DESC, batch_id DESC LIMIT 1)[OFFSET(0)] w" +
		" FROM t WHERE IFNULL(write_mode, 'replace_periods') = 'replace_periods' GROUP BY 1, 2)" +
		" SELECT t.* FROM t LEFT JOIN win ON IFNULL(t.chain_key, '') = win.ck AND IFNULL(t.period_month, '') = win.pm" +
		" WHERE (IFNULL(t.write_mode, 'replace_periods') = 'replace_periods' AND t.batch_id = win.w.b)" +
		" OR (IFNULL(t.write_mode, 'replace_periods') != 'replace_periods' AND (win.w.b IS NULL OR t.ingested_at > win.w.ts))" +
		" QUALIFY ROW_NUMBER() OVER (PARTITION BY IFNULL(t.record_id, GENERATE_UUID()) ORDER BY t.ingested_at DESC, t.batch_id DESC) = 1" +
		" ORDER BY ingested_at, record_id"
}

// rowToJSONMap drops sink-only meta columns and renders timestamps so the row can be JSON-decoded
// into a domain struct (tenant_id and ingested_at are kept: they exist on the structs too).
func rowToJSONMap(row map[string]bigquery.Value) map[string]interface{} {
	m := make(map[string]interface{}, len(row))
	for k, v := range row {
		switch k {
		case ColBatchID, ColArchiveID, ColSourceFile, ColPartitionDate, ColPeriodMonth, ColChainKey, ColWriteMode:
			continue
		}
		if t, ok := v.(time.Time); ok {
			m[k] = t.UTC().Format(time.RFC3339Nano)
			continue
		}
		m[k] = v
	}
	return m
}

// DecodeSellOutRow converts one sell_out_facts row back to a domain fact.
func DecodeSellOutRow(row map[string]bigquery.Value) (domain.SellOutFact, error) {
	b, err := json.Marshal(rowToJSONMap(row))
	if err != nil {
		return domain.SellOutFact{}, err
	}
	var f domain.SellOutFact
	if err := json.Unmarshal(b, &f); err != nil {
		return domain.SellOutFact{}, fmt.Errorf("decode sell_out row: %w", err)
	}
	// Meta columns are dropped from the JSON map (names differ from the struct).
	if strings.TrimSpace(f.IngestionBatchID) == "" {
		if s, ok := row[ColBatchID].(string); ok {
			f.IngestionBatchID = s
		}
	}
	if strings.TrimSpace(f.SourceFilename) == "" {
		if s, ok := row[ColSourceFile].(string); ok {
			f.SourceFilename = s
		}
	}
	return f, nil
}

// ReadSellOut loads all durable sell-out facts of a tenant. A missing table reads as zero rows.
func (s *BigQuerySink) ReadSellOut(ctx context.Context, tenantID string) ([]domain.SellOutFact, error) {
	q := s.client.Query(SellOutReadSQL(s.ref(TableSellOut)))
	q.Parameters = []bigquery.QueryParameter{{Name: "tenant_id", Value: NormalizeTenant(tenantID)}}
	it, err := q.Read(ctx)
	if err != nil {
		if strings.Contains(err.Error(), "notFound") || strings.Contains(err.Error(), "Not found: Table") {
			return nil, nil
		}
		return nil, fmt.Errorf("read sell_out_facts: %w", err)
	}
	var out []domain.SellOutFact
	for {
		var row map[string]bigquery.Value
		err := it.Next(&row)
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("read sell_out_facts: %w", err)
		}
		f, err := DecodeSellOutRow(row)
		if err != nil {
			return nil, err
		}
		out = append(out, f)
	}
	return out, nil
}
