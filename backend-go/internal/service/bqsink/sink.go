package bqsink

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"cloud.google.com/go/bigquery"
	"github.com/google/uuid"
	"google.golang.org/api/googleapi"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// Result statuses.
const (
	StatusOK       = "ok"
	StatusFailed   = "failed"
	StatusDisabled = "disabled"
	StatusSkipped  = "skipped"
)

// Result reports the outcome of one sink write. It is returned in upload API responses as "bigquery_sync".
type Result struct {
	Status      string `json:"status"`
	Table       string `json:"table,omitempty"`
	RowsWritten int    `json:"rows_written"`
	Error       string `json:"error,omitempty"`
	DurationMs  int64  `json:"duration_ms"`
}

// Failed reports whether the write failed.
func (r *Result) Failed() bool { return r != nil && r.Status == StatusFailed }

// Sink persists uploaded sheets to the analytics warehouse.
type Sink interface {
	Enabled() bool
	WriteSellOut(ctx context.Context, meta Meta, facts []domain.SellOutFact, mode SellOutMode) *Result
	WriteSellIn(ctx context.Context, meta Meta, records []domain.SellInRecord) *Result
	WriteProductMaster(ctx context.Context, meta Meta, summary *domain.ProductMasterSummaryResponse) *Result
	DeleteBatch(ctx context.Context, kind Kind, meta Meta) *Result
	// DeleteTenant removes every row of one tenant from the kind's table (clear-tenant endpoint).
	DeleteTenant(ctx context.Context, kind Kind, tenantID string) *Result
}

// Config controls the BigQuery sink.
type Config struct {
	Enabled   bool
	ProjectID string
	Dataset   string
	Location  string
}

// ConfigFromEnv reads BIGQUERY_SINK_ENABLED (default false), BIGQUERY_LOCATION (default europe-west1)
// and falls back to the given project/dataset (from PROJECT_ID / BIGQUERY_DATASET).
func ConfigFromEnv(projectID, dataset string) Config {
	enabled := false
	if v, ok := os.LookupEnv("BIGQUERY_SINK_ENABLED"); ok {
		if b, err := strconv.ParseBool(strings.TrimSpace(v)); err == nil {
			enabled = b
		}
	}
	loc := strings.TrimSpace(os.Getenv("BIGQUERY_LOCATION"))
	if loc == "" {
		loc = "europe-west1"
	}
	return Config{Enabled: enabled, ProjectID: projectID, Dataset: dataset, Location: loc}
}

// Noop is the disabled sink used locally and in tests.
type Noop struct{}

func (Noop) Enabled() bool { return false }
func (Noop) WriteSellOut(context.Context, Meta, []domain.SellOutFact, SellOutMode) *Result {
	return &Result{Status: StatusDisabled}
}
func (Noop) WriteSellIn(context.Context, Meta, []domain.SellInRecord) *Result {
	return &Result{Status: StatusDisabled}
}
func (Noop) WriteProductMaster(context.Context, Meta, *domain.ProductMasterSummaryResponse) *Result {
	return &Result{Status: StatusDisabled}
}
func (Noop) DeleteBatch(context.Context, Kind, Meta) *Result { return &Result{Status: StatusDisabled} }
func (Noop) DeleteTenant(context.Context, Kind, string) *Result {
	return &Result{Status: StatusDisabled}
}

// broken is returned when the sink is enabled but the client could not be created: every write fails loudly.
type broken struct{ err error }

func (b broken) Enabled() bool { return true }
func (b broken) fail(table string) *Result {
	log.Printf("ERROR [bqsink] write to %s skipped: sink unavailable: %v", table, b.err)
	return &Result{Status: StatusFailed, Table: table, Error: "bigquery sink unavailable: " + b.err.Error()}
}
func (b broken) WriteSellOut(context.Context, Meta, []domain.SellOutFact, SellOutMode) *Result {
	return b.fail(TableSellOut)
}
func (b broken) WriteSellIn(context.Context, Meta, []domain.SellInRecord) *Result {
	return b.fail(TableSellIn)
}
func (b broken) WriteProductMaster(context.Context, Meta, *domain.ProductMasterSummaryResponse) *Result {
	return b.fail(TableProductMaster)
}
func (b broken) DeleteBatch(_ context.Context, k Kind, _ Meta) *Result {
	return b.fail(TableForKind(k).Name)
}
func (b broken) DeleteTenant(_ context.Context, k Kind, _ string) *Result {
	return b.fail(TableForKind(k).Name)
}

// New builds the sink described by cfg. A disabled config yields Noop; a client error yields a sink whose writes fail loudly.
func New(ctx context.Context, cfg Config) Sink {
	if !cfg.Enabled {
		log.Printf("[bqsink] BigQuery sink disabled (set BIGQUERY_SINK_ENABLED=true to enable)")
		return Noop{}
	}
	if cfg.ProjectID == "" || cfg.Dataset == "" {
		err := errors.New("PROJECT_ID and BIGQUERY_DATASET are required")
		log.Printf("ERROR [bqsink] %v", err)
		return broken{err: err}
	}
	client, err := bigquery.NewClient(ctx, cfg.ProjectID)
	if err != nil {
		log.Printf("ERROR [bqsink] failed to create BigQuery client: %v", err)
		return broken{err: err}
	}
	client.Location = cfg.Location
	log.Printf("[bqsink] BigQuery sink enabled: %s.%s (%s)", cfg.ProjectID, cfg.Dataset, cfg.Location)
	return &BigQuerySink{client: client, cfg: cfg, ensured: map[string]bool{}}
}

// BigQuerySink writes via batch load jobs into a staging table followed by a DELETE+INSERT transaction.
type BigQuerySink struct {
	client  *bigquery.Client
	cfg     Config
	mu      sync.Mutex
	ensured map[string]bool
}

func (s *BigQuerySink) Enabled() bool { return true }

func (s *BigQuerySink) WriteSellOut(ctx context.Context, meta Meta, facts []domain.SellOutFact, mode SellOutMode) *Result {
	return s.run(ctx, PlanSellOut(meta, facts, mode, time.Now()), "upsert")
}

func (s *BigQuerySink) WriteSellIn(ctx context.Context, meta Meta, records []domain.SellInRecord) *Result {
	return s.run(ctx, PlanSellIn(meta, records, time.Now()), "upsert")
}

func (s *BigQuerySink) WriteProductMaster(ctx context.Context, meta Meta, summary *domain.ProductMasterSummaryResponse) *Result {
	return s.run(ctx, PlanProductMaster(meta, summary, time.Now()), "upsert")
}

// DeleteBatch removes every row loaded by a batch (used when an archived file is deleted).
func (s *BigQuerySink) DeleteBatch(ctx context.Context, kind Kind, meta Meta) *Result {
	start := time.Now()
	meta.TenantID = NormalizeTenant(meta.TenantID)
	spec := TableForKind(kind)
	res := &Result{Status: StatusOK, Table: spec.Name}
	if meta.BatchID == "" && meta.ArchiveID == "" {
		res.Status = StatusSkipped
		return res
	}
	err := func() error {
		if err := s.ensureTable(ctx, spec); err != nil {
			return err
		}
		sql := DeleteArchiveSQL(s.ref(spec.Name))
		return s.runQuery(ctx, sql, baseParams(meta))
	}()
	s.finish(ctx, res, err, start, kind, "delete", meta)
	return res
}

// DeleteTenantSQL is the statement used by DeleteTenant; it is always scoped to one tenant.
func DeleteTenantSQL(tableRef string) string {
	return "DELETE FROM " + tableRef + " WHERE tenant_id = @tenant_id"
}

// DeleteTenant removes every row of one tenant. An empty or wildcard tenant is refused.
func (s *BigQuerySink) DeleteTenant(ctx context.Context, kind Kind, tenantID string) *Result {
	start := time.Now()
	spec := TableForKind(kind)
	res := &Result{Status: StatusOK, Table: spec.Name}
	clean := strings.ToLower(strings.TrimSpace(tenantID))
	if clean == "" || clean == "all" || clean == "*" {
		res.Status = StatusSkipped
		return res
	}
	meta := Meta{TenantID: NormalizeTenant(tenantID)}
	err := func() error {
		if err := s.ensureTable(ctx, spec); err != nil {
			return err
		}
		return s.runQuery(ctx, DeleteTenantSQL(s.ref(spec.Name)), []bigquery.QueryParameter{{Name: "tenant_id", Value: meta.TenantID}})
	}()
	s.finish(ctx, res, err, start, kind, "delete_tenant", meta)
	return res
}

func (s *BigQuerySink) ref(table string) string {
	return fmt.Sprintf("`%s.%s.%s`", s.cfg.ProjectID, s.cfg.Dataset, table)
}

func (s *BigQuerySink) run(ctx context.Context, plan Plan, op string) *Result {
	start := time.Now()
	res := &Result{Status: StatusOK, Table: plan.Table.Name}
	if len(plan.Rows) == 0 {
		res.Status = StatusSkipped
		return res
	}
	err := s.replace(ctx, plan)
	if err == nil {
		res.RowsWritten = len(plan.Rows)
	}
	s.finish(ctx, res, err, start, plan.Kind, op, plan.Meta)
	return res
}

func (s *BigQuerySink) finish(ctx context.Context, res *Result, err error, start time.Time, kind Kind, op string, meta Meta) {
	res.DurationMs = time.Since(start).Milliseconds()
	if err != nil {
		res.Status = StatusFailed
		res.Error = err.Error()
		log.Printf("ERROR [bqsink] %s %s tenant=%s batch=%s file=%q failed after %dms: %v", op, res.Table, meta.TenantID, meta.BatchID, meta.SourceFile, res.DurationMs, err)
	} else {
		log.Printf("[bqsink] %s %s tenant=%s batch=%s file=%q rows=%d in %dms", op, res.Table, meta.TenantID, meta.BatchID, meta.SourceFile, res.RowsWritten, res.DurationMs)
	}
	s.logIngestion(ctx, meta, IngestionLogEntry{
		Kind: string(kind), Operation: op, TargetTable: res.Table, RowsWritten: res.RowsWritten,
		Status: res.Status, ErrorMessage: res.Error, DurationMs: res.DurationMs,
	})
}

func (s *BigQuerySink) logIngestion(ctx context.Context, meta Meta, e IngestionLogEntry) {
	spec := IngestionLogSpec()
	now := time.Now()
	row := RowFor(e)
	for k, v := range metaRow(meta, now) {
		row[k] = v
	}
	row[ColPartitionDate] = now.UTC().Format("2006-01-02")
	if err := s.ensureTable(ctx, spec); err != nil {
		log.Printf("ERROR [bqsink] ingestion_log unavailable: %v", err)
		return
	}
	if err := s.load(ctx, s.client.Dataset(s.cfg.Dataset).Table(spec.Name), spec.Schema, []map[string]interface{}{row}, bigquery.WriteAppend); err != nil {
		log.Printf("ERROR [bqsink] ingestion_log append failed: %v", err)
	}
}

// replace loads rows into a short-lived staging table, then atomically deletes the rows they supersede and inserts them.
func (s *BigQuerySink) replace(ctx context.Context, plan Plan) error {
	if err := s.ensureTable(ctx, plan.Table); err != nil {
		return err
	}
	ds := s.client.Dataset(s.cfg.Dataset)
	stagingName := fmt.Sprintf("_staging_%s_%s", plan.Table.Name, strings.ReplaceAll(uuid.New().String(), "-", ""))
	staging := ds.Table(stagingName)
	if err := staging.Create(ctx, &bigquery.TableMetadata{
		Schema:         plan.Table.Schema,
		ExpirationTime: time.Now().Add(2 * time.Hour),
		Description:    "temporary staging table for tashil bqsink",
	}); err != nil {
		return fmt.Errorf("create staging table: %w", err)
	}
	defer func() {
		dctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if err := staging.Delete(dctx); err != nil {
			log.Printf("[bqsink] warning: staging table %s not dropped (expires in 2h): %v", stagingName, err)
		}
	}()
	if err := s.load(ctx, staging, plan.Table.Schema, plan.Rows, bigquery.WriteTruncate); err != nil {
		return fmt.Errorf("load staging: %w", err)
	}
	sql := BuildReplaceSQL(s.ref(plan.Table.Name), s.ref(stagingName), plan.Table.Schema, plan.DeleteWhere)
	var err error
	for attempt := 1; attempt <= 4; attempt++ {
		err = s.runQuery(ctx, sql, plan.Params)
		if err == nil || !isConcurrentUpdate(err) {
			break
		}
		log.Printf("[bqsink] concurrent update on %s, retrying (attempt %d)", plan.Table.Name, attempt)
		time.Sleep(time.Duration(attempt*attempt) * time.Second)
	}
	if err != nil {
		return fmt.Errorf("replace transaction: %w", err)
	}
	return nil
}

// BuildReplaceSQL renders the DELETE+INSERT multi-statement transaction.
func BuildReplaceSQL(targetRef, stagingRef string, schema bigquery.Schema, deleteWhere string) string {
	cols := make([]string, 0, len(schema))
	for _, f := range schema {
		cols = append(cols, "`"+f.Name+"`")
	}
	colList := strings.Join(cols, ", ")
	where := strings.ReplaceAll(deleteWhere, "{{staging}}", stagingRef)
	return fmt.Sprintf("BEGIN TRANSACTION;\nDELETE FROM %s WHERE %s;\nINSERT INTO %s (%s) SELECT %s FROM %s;\nCOMMIT TRANSACTION;",
		targetRef, where, targetRef, colList, colList, stagingRef)
}

func isConcurrentUpdate(err error) bool {
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "concurrent update") || strings.Contains(msg, "aborted due to concurrent")
}

func (s *BigQuerySink) runQuery(ctx context.Context, sql string, params []bigquery.QueryParameter) error {
	q := s.client.Query(sql)
	q.Parameters = params
	q.Location = s.cfg.Location
	job, err := q.Run(ctx)
	if err != nil {
		return err
	}
	status, err := job.Wait(ctx)
	if err != nil {
		return err
	}
	return status.Err()
}

func (s *BigQuerySink) load(ctx context.Context, table *bigquery.Table, schema bigquery.Schema, rows []map[string]interface{}, disp bigquery.TableWriteDisposition) error {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	for _, r := range rows {
		if err := enc.Encode(r); err != nil {
			return fmt.Errorf("encode row: %w", err)
		}
	}
	src := bigquery.NewReaderSource(&buf)
	src.SourceFormat = bigquery.JSON
	src.Schema = schema
	loader := table.LoaderFrom(src)
	loader.WriteDisposition = disp
	loader.CreateDisposition = bigquery.CreateNever
	loader.Location = s.cfg.Location
	job, err := loader.Run(ctx)
	if err != nil {
		return err
	}
	status, err := job.Wait(ctx)
	if err != nil {
		return err
	}
	if err := status.Err(); err != nil {
		if len(status.Errors) > 0 {
			return fmt.Errorf("%w (first row error: %v)", err, status.Errors[0])
		}
		return err
	}
	return nil
}

// ensureTable creates the table if missing (partitioned + clustered) and adds any new nullable columns.
func (s *BigQuerySink) ensureTable(ctx context.Context, spec TableSpec) error {
	s.mu.Lock()
	done := s.ensured[spec.Name]
	s.mu.Unlock()
	if done {
		return nil
	}
	t := s.client.Dataset(s.cfg.Dataset).Table(spec.Name)
	md, err := t.Metadata(ctx)
	if err != nil {
		var gerr *googleapi.Error
		if !errors.As(err, &gerr) || gerr.Code != http.StatusNotFound {
			return fmt.Errorf("read table %s: %w", spec.Name, err)
		}
		meta := &bigquery.TableMetadata{
			Schema:      spec.Schema,
			Description: spec.Description,
			TimePartitioning: &bigquery.TimePartitioning{
				Type:  spec.PartitionType,
				Field: ColPartitionDate,
			},
		}
		if len(spec.ClusterBy) > 0 {
			meta.Clustering = &bigquery.Clustering{Fields: spec.ClusterBy}
		}
		if err := t.Create(ctx, meta); err != nil {
			var cerr *googleapi.Error
			if !errors.As(err, &cerr) || cerr.Code != http.StatusConflict {
				return fmt.Errorf("create table %s: %w", spec.Name, err)
			}
		} else {
			log.Printf("[bqsink] created table %s", spec.Name)
		}
	} else if missing := MissingColumns(md.Schema, spec.Schema); len(missing) > 0 {
		newSchema := append(md.Schema, missing...)
		if _, err := t.Update(ctx, bigquery.TableMetadataToUpdate{Schema: newSchema}, md.ETag); err != nil {
			return fmt.Errorf("add columns to %s: %w", spec.Name, err)
		}
		log.Printf("[bqsink] added %d column(s) to %s", len(missing), spec.Name)
	}
	s.mu.Lock()
	s.ensured[spec.Name] = true
	s.mu.Unlock()
	return nil
}

// MissingColumns returns fields in want that are not in have, relaxed to NULLABLE so they can be added.
func MissingColumns(have, want bigquery.Schema) bigquery.Schema {
	existing := map[string]bool{}
	for _, f := range have {
		existing[strings.ToLower(f.Name)] = true
	}
	var out bigquery.Schema
	for _, f := range want {
		if !existing[strings.ToLower(f.Name)] {
			c := *f
			c.Required = false
			out = append(out, &c)
		}
	}
	return out
}
