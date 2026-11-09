package gemini

import (
	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/ingestanomaly"
)

// attachPhaseBAnomalies runs post-parse Phase B detectors (negatives, duplicates,
// unit-price outliers, MoM spikes) and merges them into payload.AnomaliesDetected.
// Advisory only — does not drop records or write durable state.
func attachPhaseBAnomalies(payload *domain.NormalizedRetailIngestionPayload) {
	if payload == nil {
		return
	}
	payload.AnomaliesDetected = ingestanomaly.Detect(payload.NormalizedRecords, payload.AnomaliesDetected)
}
