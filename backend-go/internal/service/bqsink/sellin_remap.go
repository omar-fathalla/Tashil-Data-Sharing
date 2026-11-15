package bqsink

import (
	"context"
	"fmt"
	"strings"
	"time"

	"cloud.google.com/go/bigquery"
)

// RemapSellInCustomerSQL updates customer_name / customer_branch_code for rows that still
// carry the source spelling or the source fat_auto branch code. Exact match only — never LIKE/fuzzy.
// Matching by branch_code covers glued-digit spelling drift (الدوار2 vs الدوار 2) when the registry
// decision recorded one form and BigQuery still holds the other under the same fat_auto_* id.
func RemapSellInCustomerSQL(tableRef string) string {
	return "UPDATE " + tableRef + " SET customer_name = @to_name, customer_branch_code = @to_branch" +
		" WHERE tenant_id = @tenant_id" +
		" AND IFNULL(chain_key, '') = @chain" +
		" AND (customer_name = @from_name" +
		" OR (@from_branch != '' AND IFNULL(customer_branch_code, '') = @from_branch))"
}

// RestoreSellInCustomerSQL restores remapped rows by record_id (merge undo).
func RestoreSellInCustomerSQL(tableRef string) string {
	return "UPDATE " + tableRef + " SET customer_name = @to_name, customer_branch_code = @to_branch" +
		" WHERE tenant_id = @tenant_id" +
		" AND record_id IN UNNEST(@record_ids)"
}

// RemapSellInCustomer runs the attribution UPDATE for one exact recorded merge decision.
// fromName is the registry source spelling; fromBranch is its fat_auto_* code (optional but
// preferred). chain is the normalized chain_key.
func (s *BigQuerySink) RemapSellInCustomer(ctx context.Context, tenantID, chain, fromName, toName, toBranch string) *Result {
	return s.RemapSellInCustomerWithBranch(ctx, tenantID, chain, fromName, "", toName, toBranch)
}

// RemapSellInCustomerWithBranch is RemapSellInCustomer plus an optional source branch_code match.
func (s *BigQuerySink) RemapSellInCustomerWithBranch(ctx context.Context, tenantID, chain, fromName, fromBranch, toName, toBranch string) *Result {
	start := time.Now()
	meta := Meta{TenantID: NormalizeTenant(tenantID), SourceFile: "customer_alias_remap"}
	res := &Result{Status: StatusOK, Table: TableSellIn}
	fromName = strings.TrimSpace(fromName)
	fromBranch = strings.TrimSpace(fromBranch)
	toName = strings.TrimSpace(toName)
	if (fromName == "" && fromBranch == "") || toName == "" || (fromName != "" && fromName == toName) {
		res.Status = StatusSkipped
		return res
	}
	chain = strings.ToLower(strings.TrimSpace(chain))
	if chain == "" {
		chain = "fathalla"
	}
	err := func() error {
		if err := s.ensureTable(ctx, SellInSpec()); err != nil {
			return err
		}
		return s.runQuery(ctx, RemapSellInCustomerSQL(s.ref(TableSellIn)), []bigquery.QueryParameter{
			{Name: "tenant_id", Value: meta.TenantID},
			{Name: "chain", Value: chain},
			{Name: "from_name", Value: fromName},
			{Name: "from_branch", Value: fromBranch},
			{Name: "to_name", Value: toName},
			{Name: "to_branch", Value: strings.TrimSpace(toBranch)},
		})
	}()
	s.finish(ctx, res, err, start, KindSellIn, "remap_customer", meta)
	if err == nil {
		res.RowsWritten = 1 // DML does not return a row count here; version bump still needed
	}
	return res
}

// RestoreSellInCustomerByIDs restores attribution for previously remapped record_ids.
func (s *BigQuerySink) RestoreSellInCustomerByIDs(ctx context.Context, tenantID, toName, toBranch string, recordIDs []string) *Result {
	start := time.Now()
	meta := Meta{TenantID: NormalizeTenant(tenantID), SourceFile: "customer_alias_restore"}
	res := &Result{Status: StatusOK, Table: TableSellIn}
	toName = strings.TrimSpace(toName)
	if toName == "" || len(recordIDs) == 0 {
		res.Status = StatusSkipped
		return res
	}
	err := func() error {
		if err := s.ensureTable(ctx, SellInSpec()); err != nil {
			return err
		}
		return s.runQuery(ctx, RestoreSellInCustomerSQL(s.ref(TableSellIn)), []bigquery.QueryParameter{
			{Name: "tenant_id", Value: meta.TenantID},
			{Name: "to_name", Value: toName},
			{Name: "to_branch", Value: strings.TrimSpace(toBranch)},
			{Name: "record_ids", Value: recordIDs},
		})
	}()
	s.finish(ctx, res, err, start, KindSellIn, "restore_customer", meta)
	if err == nil {
		res.RowsWritten = len(recordIDs)
	}
	return res
}

// SellInAttributionRemapper is the durable half of customer merge re-attribution.
type SellInAttributionRemapper interface {
	RemapSellInCustomer(ctx context.Context, tenantID, chain, fromName, toName, toBranch string) *Result
	RemapSellInCustomerWithBranch(ctx context.Context, tenantID, chain, fromName, fromBranch, toName, toBranch string) *Result
	RestoreSellInCustomerByIDs(ctx context.Context, tenantID, toName, toBranch string, recordIDs []string) *Result
}

// Compile-time check.
var _ SellInAttributionRemapper = (*BigQuerySink)(nil)

// RemapSQLGuard documents that remap SQL never touches other tenants/chains.
func RemapSQLGuard(sql string) error {
	if !strings.Contains(sql, "tenant_id = @tenant_id") {
		return fmt.Errorf("remap SQL must scope tenant_id")
	}
	return nil
}
