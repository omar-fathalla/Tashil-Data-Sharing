package gemini

import (
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/ingestanomaly"
)

func TestAttachPhaseBAnomalies_MergesIntoPayload(t *testing.T) {
	payload := &domain.NormalizedRetailIngestionPayload{
		AnomaliesDetected: []domain.IngestionAnomaly{{
			RowNumber: 1, IssueType: "invalid_barcode", Description: "short",
		}},
		NormalizedRecords: []domain.NormalizedRecord{
			{Barcode: "6221001", ResolvedStoreID: "crf_maadi", TransactionDate: "2026-01-15", QuantitySold: 10, NetRevenue: 100},
			{Barcode: "6221001", ResolvedStoreID: "crf_maadi", TransactionDate: "2026-01-15", QuantitySold: 10, NetRevenue: 100}, // dup of row 1
			{Barcode: "6221001", ResolvedStoreID: "crf_maadi", TransactionDate: "2026-01-10", QuantitySold: 10, NetRevenue: 100},
			{Barcode: "6221999", ResolvedStoreID: "crf_maadi", TransactionDate: "2026-01-10", QuantitySold: 10, NetRevenue: 100},
			{Barcode: "6221999", ResolvedStoreID: "crf_maadi", TransactionDate: "2026-02-10", QuantitySold: 10, NetRevenue: 500}, // +400% MoM
		},
	}
	attachPhaseBAnomalies(payload)

	var hasDup, hasMom, hasInvalid bool
	for _, a := range payload.AnomaliesDetected {
		switch a.IssueType {
		case ingestanomaly.TypeDuplicateRow:
			hasDup = true
		case ingestanomaly.TypeMomSpike:
			hasMom = true
		case "invalid_barcode":
			hasInvalid = true
		}
	}
	if !hasDup || !hasMom || !hasInvalid {
		t.Fatalf("expected invalid_barcode + duplicate_row + mom_spike, got %+v", payload.AnomaliesDetected)
	}
}

func TestApplyGuardrailEvents_RunsPhaseB(t *testing.T) {
	payload := &domain.NormalizedRetailIngestionPayload{
		NormalizedRecords: []domain.NormalizedRecord{
			{Barcode: "6221001", ResolvedStoreID: "s", TransactionDate: "2026-01-01", QuantitySold: -1, NetRevenue: 10},
		},
	}
	applyGuardrailEvents(payload, nil)
	if len(payload.AnomaliesDetected) == 0 {
		t.Fatal("expected Phase B anomalies even when Events is nil")
	}
	if payload.AnomaliesDetected[0].IssueType != ingestanomaly.TypeNegativeSales {
		t.Fatalf("got %+v", payload.AnomaliesDetected)
	}
}
