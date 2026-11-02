package bqsink

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"cloud.google.com/go/bigquery"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// Table names inside the configured dataset.
const (
	TableSellOut       = "sell_out_facts"
	TableSellIn        = "sell_in_records"
	TableProductMaster = "product_master_items"
	TableIngestionLog  = "ingestion_log"
)

// Kind identifies the sheet type being persisted.
type Kind string

const (
	KindSellOut       Kind = "sell_out"
	KindSellIn        Kind = "sell_in"
	KindProductMaster Kind = "product_master"
)

// SellOutMode selects the dedupe strategy for sell-out uploads, mirroring the in-memory repository.
type SellOutMode string

const (
	// ModeReplacePeriods replaces every (chain, month) present in the upload (ReplaceTenantFacts semantics).
	ModeReplacePeriods SellOutMode = "replace_periods"
	// ModeUpsertRecords replaces rows with the same record_id (InsertSellOutFacts semantics).
	ModeUpsertRecords SellOutMode = "upsert_records"
)

// Meta describes the upload a write belongs to.
type Meta struct {
	TenantID   string
	BatchID    string
	ArchiveID  string
	SourceFile string
}

// TableSpec describes how a sink table is created.
type TableSpec struct {
	Name          string
	Schema        bigquery.Schema
	PartitionType bigquery.TimePartitioningType
	ClusterBy     []string
	Description   string
}

// Plan is a fully-resolved, idempotent write: load Rows into a staging table, then in one
// transaction DELETE the rows matched by DeleteWhere and INSERT the staged rows.
type Plan struct {
	Kind        Kind
	Meta        Meta
	Table       TableSpec
	Rows        []map[string]interface{}
	DeleteWhere string // may reference @tenant_id, @batch_id, @source_file, @keys, @chains and the staging table as `{{staging}}`
	Params      []bigquery.QueryParameter
	// N and RowAt describe rows built lazily (streamed in bounded chunks); used when Rows is nil.
	N     int
	RowAt func(i int) map[string]interface{}
}

// Len is the number of rows the plan writes.
func (p Plan) Len() int {
	if p.Rows != nil || p.RowAt == nil {
		return len(p.Rows)
	}
	return p.N
}

// Row returns row i, building it on demand for streamed plans.
func (p Plan) Row(i int) map[string]interface{} {
	if p.Rows != nil || p.RowAt == nil {
		return p.Rows[i]
	}
	return p.RowAt(i)
}

func (p Plan) materialize() []map[string]interface{} {
	rows := make([]map[string]interface{}, 0, p.N)
	for i := 0; i < p.N; i++ {
		rows = append(rows, p.RowAt(i))
	}
	return rows
}

// NormalizeTenant returns the canonical "tenant-<slug>" key used by the archive.
func NormalizeTenant(tenantID string) string {
	s := strings.ToLower(strings.TrimSpace(tenantID))
	s = strings.TrimPrefix(s, "tenant-")
	s = strings.TrimPrefix(s, "tenant_")
	if s == "" {
		s = "system"
	}
	return "tenant-" + s
}

func chainKey(s string) string {
	return strings.ToLower(strings.TrimSpace(s))
}

func parseDate(s string) (time.Time, bool) {
	s = strings.TrimSpace(s)
	for _, layout := range []string{"2006-01-02", time.RFC3339, "2006-01-02 15:04:05", "2006/01/02", "2006-01"} {
		if t, err := time.Parse(layout, s); err == nil {
			return t, true
		}
		if len(s) > len(layout) && layout == "2006-01-02" {
			if t, err := time.Parse(layout, s[:10]); err == nil {
				return t, true
			}
		}
	}
	return time.Time{}, false
}

func sortedKeys(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func baseParams(meta Meta) []bigquery.QueryParameter {
	return []bigquery.QueryParameter{
		{Name: "tenant_id", Value: meta.TenantID},
		{Name: "batch_id", Value: meta.BatchID},
		{Name: "source_file", Value: meta.SourceFile},
		{Name: "archive_id", Value: meta.ArchiveID},
	}
}

// archiveDeleteWhere is the idempotent replace key shared by every sink table: an upload replaces only the
// rows of its own file (same archive_id, or same batch), plus legacy rows written before archive ids were
// recorded for the same source file. Rows of other files are never deleted, so every uploaded file stays
// stored in full; overlap between files is resolved by the read views.
const archiveDeleteWhere = "tenant_id = @tenant_id AND ((@batch_id != '' AND batch_id = @batch_id)" +
	" OR (@archive_id != '' AND archive_id = @archive_id)" +
	" OR (IFNULL(archive_id, '') = '' AND LOWER(IFNULL(source_file, '')) = LOWER(@source_file)))"

func metaRow(meta Meta, now time.Time) map[string]interface{} {
	return map[string]interface{}{
		ColTenantID:   meta.TenantID,
		ColBatchID:    meta.BatchID,
		ColArchiveID:  meta.ArchiveID,
		ColSourceFile: meta.SourceFile,
		ColIngestedAt: now.UTC().Format(bqTimestampLayout),
	}
}

// SellOutSpec is the sell_out_facts table definition.
func SellOutSpec() TableSpec {
	return TableSpec{
		Name:          TableSellOut,
		Schema:        SchemaFor(domain.SellOutFact{}),
		PartitionType: bigquery.DayPartitioningType,
		ClusterBy:     []string{ColTenantID, ColChainKey, "item_code", "barcode"},
		Description:   "Tashil sell-out facts from uploaded retailer workbooks (partitioned by transaction date).",
	}
}

// SellInSpec is the sell_in_records table definition.
func SellInSpec() TableSpec {
	return TableSpec{
		Name:          TableSellIn,
		Schema:        SchemaFor(domain.SellInRecord{}),
		PartitionType: bigquery.MonthPartitioningType,
		ClusterBy:     []string{ColTenantID, ColChainKey, "item_code"},
		Description:   "Tashil sell-in / CPFR plan records from uploaded workbooks (partitioned by plan month).",
	}
}

// ProductMasterSpec is the product_master_items table definition (one snapshot per uploaded sheet).
func ProductMasterSpec() TableSpec {
	return TableSpec{
		Name:          TableProductMaster,
		Schema:        SchemaFor(domain.ProductMasterItem{}),
		PartitionType: bigquery.DayPartitioningType,
		ClusterBy:     []string{ColTenantID, "item_code", "barcode"},
		Description:   "Tashil product master & price list snapshots, one set of rows per uploaded sheet (partitioned by upload date).",
	}
}

// IngestionLogEntry is one row of the ingestion_log table.
type IngestionLogEntry struct {
	Kind         string `json:"kind"`
	Operation    string `json:"operation"`
	TargetTable  string `json:"target_table"`
	RowsWritten  int    `json:"rows_written"`
	Status       string `json:"status"`
	ErrorMessage string `json:"error_message"`
	DurationMs   int64  `json:"duration_ms"`
}

// IngestionLogSpec is the ingestion_log table definition.
func IngestionLogSpec() TableSpec {
	return TableSpec{
		Name:          TableIngestionLog,
		Schema:        SchemaFor(IngestionLogEntry{}),
		PartitionType: bigquery.DayPartitioningType,
		ClusterBy:     []string{ColTenantID, "kind"},
		Description:   "One row per BigQuery sink write attempt (upload, replace, delete).",
	}
}

// sellOutRow builds the BigQuery row of one sell-out fact.
func sellOutRow(meta Meta, f *domain.SellOutFact, mode SellOutMode, now time.Time) map[string]interface{} {
	row := RowFor(*f)
	for k, v := range metaRow(meta, now) {
		row[k] = v
	}
	row[ColChainKey] = chainKey(f.RetailerChain)
	month := ""
	if len(strings.TrimSpace(f.TransactionDate)) >= 7 {
		month = strings.TrimSpace(f.TransactionDate)[:7]
	}
	row[ColPeriodMonth] = month
	if mode == ModeUpsertRecords {
		row[ColWriteMode] = string(ModeUpsertRecords)
	} else {
		row[ColWriteMode] = string(ModeReplacePeriods)
	}
	if d, ok := parseDate(f.TransactionDate); ok {
		row[ColPartitionDate] = d.Format("2006-01-02")
	}
	return row
}

// PlanSellOut builds an idempotent write plan for sell-out facts.
func PlanSellOut(meta Meta, facts []domain.SellOutFact, mode SellOutMode, now time.Time) Plan {
	p := StreamSellOut(meta, facts, mode, now)
	p.Rows = p.materialize()
	return p
}

// StreamSellOut is PlanSellOut without materialising the rows: each row is built when it is loaded, so a large
// file never holds every row map in memory at once.
func StreamSellOut(meta Meta, facts []domain.SellOutFact, mode SellOutMode, now time.Time) Plan {
	meta.TenantID = NormalizeTenant(meta.TenantID)
	return Plan{Kind: KindSellOut, Meta: meta, Table: SellOutSpec(), N: len(facts),
		RowAt:       func(i int) map[string]interface{} { return sellOutRow(meta, &facts[i], mode, now) },
		DeleteWhere: archiveDeleteWhere, Params: baseParams(meta)}
}

// sellInRow builds the BigQuery row of one sell-in record.
func sellInRow(meta Meta, r *domain.SellInRecord, now time.Time) map[string]interface{} {
	row := RowFor(*r)
	for k, v := range metaRow(meta, now) {
		row[k] = v
	}
	ck := chainKey(r.RetailerChain)
	if ck == "" {
		ck = "fathalla"
	}
	yr, mn := r.Year, r.MonthNum
	month := fmt.Sprintf("%04d-%02d", yr, mn)
	row[ColChainKey] = ck
	row[ColPeriodMonth] = month
	row[ColPartitionDate] = month + "-01"
	return row
}

// PlanSellIn builds an idempotent write plan for sell-in records (SetSellInRecords semantics:
// replace same file+chain, and any (chain, year, month) present in the upload).
func PlanSellIn(meta Meta, records []domain.SellInRecord, now time.Time) Plan {
	p := StreamSellIn(meta, records, now)
	p.Rows = p.materialize()
	return p
}

// StreamSellIn is PlanSellIn with rows built lazily while loading (bounded memory for large files).
func StreamSellIn(meta Meta, records []domain.SellInRecord, now time.Time) Plan {
	meta.TenantID = NormalizeTenant(meta.TenantID)
	records = validSellInPeriods(records)
	return Plan{Kind: KindSellIn, Meta: meta, Table: SellInSpec(), N: len(records),
		RowAt:       func(i int) map[string]interface{} { return sellInRow(meta, &records[i], now) },
		DeleteWhere: archiveDeleteWhere, Params: baseParams(meta)}
}

// PlanProductMaster builds a snapshot write plan: re-uploading the same sheet (same batch or filename) replaces its rows;
// different sheets are kept side by side as price-list history.
func PlanProductMaster(meta Meta, summary *domain.ProductMasterSummaryResponse, now time.Time) Plan {
	meta.TenantID = NormalizeTenant(meta.TenantID)
	if meta.SourceFile == "" && summary != nil {
		meta.SourceFile = summary.SourceFilename
	}
	var rows []map[string]interface{}
	if summary != nil {
		for i := range summary.Items {
			it := summary.Items[i]
			row := RowFor(it)
			for k, v := range metaRow(meta, now) {
				row[k] = v
			}
			row[ColPartitionDate] = now.UTC().Format("2006-01-02")
			row[ColPeriodMonth] = now.UTC().Format("2006-01")
			rows = append(rows, row)
		}
	}
	return Plan{Kind: KindProductMaster, Meta: meta, Table: ProductMasterSpec(), Rows: rows, DeleteWhere: archiveDeleteWhere, Params: baseParams(meta)}
}

// TableForKind maps a sheet kind to its table spec.
func TableForKind(k Kind) TableSpec {
	switch k {
	case KindSellIn:
		return SellInSpec()
	case KindProductMaster:
		return ProductMasterSpec()
	default:
		return SellOutSpec()
	}
}


// validSellInPeriods drops records without a real (year, month). SetSellInRecords already rejects
// them, so this only guards the sink: no row is ever written under an invented 2026-01 period.
func validSellInPeriods(records []domain.SellInRecord) []domain.SellInRecord {
	for i := range records {
		if records[i].Year <= 0 || records[i].MonthNum < 1 || records[i].MonthNum > 12 {
			out := make([]domain.SellInRecord, 0, len(records))
			for _, r := range records {
				if r.Year > 0 && r.MonthNum >= 1 && r.MonthNum <= 12 {
					out = append(out, r)
				}
			}
			return out
		}
	}
	return records
}
