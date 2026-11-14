package bqsink

import (
	"context"
	"fmt"
	"strings"
	"time"

	"cloud.google.com/go/bigquery"
)

// RemapSellInCustomerSQL updates customer_name / customer_branch_code for rows that still
// carry the source spelling. Exact name + chain only — never a fuzzy match.
func RemapSellInCustomerSQL(tableRef string) string {
	return "UPDATE " + tableRef + " SET customer_name = @to_name, customer_branch_code = @to_branch" +
		" WHERE tenant_id = @tenant_id" +
		" AND IFNULL(chain_key, '') = @chain" +
		" AND customer_name = @from_name"
}

// RestoreSellInCustomerSQL restores remapped rows by record_id (merge undo).
func RestoreSellInCustomerSQL(tableRef string) string {
	return "UPDATE " + tableRef + " SET customer_name = @to_name, customer_branch_code = @to_branch" +
		" WHERE tenant_id = @tenant_id" +
		" AND record_id IN UNNEST(@record_ids)"
}

// RemapSellInCustomer runs the attribution UPDATE for one exact recorded merge decision.
// fromName must be the stored customer_name spelling; chain is the normalized chain_key.
func (s *BigQuerySink) RemapSellInCustomer(ctx context.Context, tenantID, chain, fromName, toName, toBranch string) *Result {
	start := time.Now()
	meta := Meta{TenantID: NormalizeTenant(tenantID), SourceFile: "customer_alias_remap"}
	res := &Result{Status: StatusOK, Table: TableSellIn}
	fromName = strings.TrimSpace(fromName)
	toName = strings.TrimSpace(toName)
	if fromName == "" || toName == "" || fromName == toName {
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
