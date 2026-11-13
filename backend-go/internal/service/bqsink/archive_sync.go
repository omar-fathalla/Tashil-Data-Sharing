package bqsink

import (
	"context"
	"fmt"
	"strings"
	"time"

	"cloud.google.com/go/bigquery"
	"google.golang.org/api/iterator"
)

// DeleteArchiveSQL removes every row of one uploaded file: its archive_id, its batch, and legacy rows
// (written before archive ids were recorded) with the same source file name.
func DeleteArchiveSQL(tableRef string) string {
	return "DELETE FROM " + tableRef + " WHERE " + archiveDeleteWhere
}

// ArchiveRows is the stored row count of one file in one sink table.
type ArchiveRows struct {
	Kind       Kind
	ArchiveID  string // empty for legacy rows
	SourceFile string
	Rows       int
	// Units is SUM(quantity_sold) of the tenant's own rows (Sell-Out only): the same scope as the
	// file's net Sell-Out (own brand, or rows without a supplier).
	Units float64
	// Cases / Tons are SUM(net_qty_cases) / SUM(weight_tons) of the file's rows (Sell-In only).
	Cases float64
	Tons  float64
}

// ArchiveReconciler is implemented by sinks that can compare stored rows with the upload archive.
type ArchiveReconciler interface {
	ArchiveRowCounts(ctx context.Context, tenantID string) ([]ArchiveRows, error)
	DeleteOrphans(ctx context.Context, kind Kind, tenantID string, liveArchiveIDs, liveFiles []string) *Result
}

// ArchiveRowCountsSQL counts stored rows per (archive_id, source_file) of one tenant.
func ArchiveRowCountsSQL(tableRef string) string {
	return "SELECT IFNULL(archive_id, '') archive_id, IFNULL(source_file, '') source_file, COUNT(*) n FROM " + tableRef +
		" WHERE tenant_id = @tenant_id GROUP BY 1, 2"
}

// ArchiveFileTotalsSQL is ArchiveRowCountsSQL plus the per-file quantity totals shown in the upload
// lists: own-brand units for Sell-Out, cases and tons for Sell-In (0 for other kinds). Raw stored
// rows of each archive_id, the same rows COUNT(*) counts; analytics reads are unchanged.
func ArchiveFileTotalsSQL(kind Kind, tableRef string) string {
	totals := "CAST(0 AS FLOAT64) units, CAST(0 AS FLOAT64) cases, CAST(0 AS FLOAT64) tons"
	switch kind {
	case KindSellOut:
		totals = "CAST(IFNULL(SUM(IF(IFNULL(is_own_brand, FALSE) OR IFNULL(supplier, '') = '', quantity_sold, 0)), 0) AS FLOAT64) units," +
			" CAST(0 AS FLOAT64) cases, CAST(0 AS FLOAT64) tons"
	case KindSellIn:
		totals = "CAST(0 AS FLOAT64) units, IFNULL(SUM(net_qty_cases), 0) cases, IFNULL(SUM(weight_tons), 0) tons"
	}
	return "SELECT IFNULL(archive_id, '') archive_id, IFNULL(source_file, '') source_file, COUNT(*) n, " + totals +
		" FROM " + tableRef + " WHERE tenant_id = @tenant_id GROUP BY 1, 2"
}

// DeleteOrphansSQL removes rows whose file is no longer in the archive (deleted or replaced uploads):
// rows with an archive_id not in @live_ids, and legacy rows whose source file is not in @live_files.
func DeleteOrphansSQL(tableRef string) string {
	return "DELETE FROM " + tableRef + " WHERE tenant_id = @tenant_id AND (" +
		"(IFNULL(archive_id, '') != '' AND archive_id NOT IN UNNEST(@live_ids))" +
		" OR (IFNULL(archive_id, '') = '' AND LOWER(IFNULL(source_file, '')) NOT IN UNNEST(@live_files)))"
}

// ArchiveRowCounts returns stored row counts per file for Sell-Out, Sell-In and Product Master.
func (s *BigQuerySink) ArchiveRowCounts(ctx context.Context, tenantID string) ([]ArchiveRows, error) {
	var out []ArchiveRows
	for _, kind := range []Kind{KindSellOut, KindSellIn, KindProductMaster} {
		q := s.client.Query(ArchiveFileTotalsSQL(kind, s.ref(TableForKind(kind).Name)))
		q.Parameters = []bigquery.QueryParameter{{Name: "tenant_id", Value: NormalizeTenant(tenantID)}}
		it, err := q.Read(ctx)
		if err != nil {
			if strings.Contains(err.Error(), "notFound") || strings.Contains(err.Error(), "Not found: Table") {
				continue
			}
			return nil, fmt.Errorf("count %s rows: %w", kind, err)
		}
		for {
			var row struct {
				ArchiveID  string  `bigquery:"archive_id"`
				SourceFile string  `bigquery:"source_file"`
				N          int64   `bigquery:"n"`
				Units      float64 `bigquery:"units"`
				Cases      float64 `bigquery:"cases"`
				Tons       float64 `bigquery:"tons"`
			}
			err := it.Next(&row)
			if err == iterator.Done {
				break
			}
			if err != nil {
				return nil, fmt.Errorf("count %s rows: %w", kind, err)
			}
			out = append(out, ArchiveRows{Kind: kind, ArchiveID: row.ArchiveID, SourceFile: row.SourceFile, Rows: int(row.N),
				Units: row.Units, Cases: row.Cases, Tons: row.Tons})
		}
	}
	return out, nil
}

// DeleteOrphans removes rows of files that are no longer in the archive. An empty live set is refused
// (it would wipe the tenant); use DeleteTenant for that.
func (s *BigQuerySink) DeleteOrphans(ctx context.Context, kind Kind, tenantID string, liveArchiveIDs, liveFiles []string) *Result {
	start := time.Now()
	spec := TableForKind(kind)
	res := &Result{Status: StatusOK, Table: spec.Name}
	if len(liveArchiveIDs) == 0 {
		res.Status = StatusSkipped
		return res
	}
	files := make([]string, 0, len(liveFiles))
	for _, f := range liveFiles {
		files = append(files, strings.ToLower(f))
	}
	meta := Meta{TenantID: NormalizeTenant(tenantID), BatchID: "orphans"}
	err := func() error {
		if err := s.ensureTable(ctx, spec); err != nil {
			return err
		}
		return s.runQuery(ctx, DeleteOrphansSQL(s.ref(spec.Name)), []bigquery.QueryParameter{
			{Name: "tenant_id", Value: meta.TenantID},
			{Name: "live_ids", Value: liveArchiveIDs},
			{Name: "live_files", Value: files},
		})
	}()
	s.finish(ctx, res, err, start, kind, "delete_orphans", meta)
	return res
}
