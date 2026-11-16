package firestore

import (
	"context"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestValidateChainDiscountProfilesVATRange(t *testing.T) {
	ok := func(v float64) []domain.ChainDiscountProfile {
		return []domain.ChainDiscountProfile{{Chain: "a", VATRatePct: &v}}
	}
	for _, v := range []float64{0, 14, 22.5, 100} {
		if err := ValidateChainDiscountProfiles(ok(v)); err != nil {
			t.Fatalf("VAT %v must be valid: %v", v, err)
		}
	}
	for _, v := range []float64{-0.1, 100.1} {
		if err := ValidateChainDiscountProfiles(ok(v)); err == nil {
			t.Fatalf("VAT %v must be rejected", v)
		}
	}
	if err := ValidateChainDiscountProfiles([]domain.ChainDiscountProfile{{Chain: "a"}}); err != nil {
		t.Fatalf("unset VAT is valid: %v", err)
	}
}

func TestChainDiscountProfilesKeepVATAcrossSaveAndLoad(t *testing.T) {
	c := NewClient("", true)
	v := 7.0
	doc := &domain.ChainDiscountProfiles{TenantID: "tenant-adeco", Profiles: []domain.ChainDiscountProfile{
		{Chain: "b", InvoiceDiscountPct: 10},
		{Chain: "a", InvoiceDiscountPct: 10, AdditionalDiscountPct: 5, VATRatePct: &v},
	}}
	if err := c.SaveChainDiscountProfiles(context.Background(), doc); err != nil {
		t.Fatal(err)
	}
	got, err := c.GetChainDiscountProfiles(context.Background(), "tenant-adeco")
	if err != nil || len(got.Profiles) != 2 {
		t.Fatalf("load: %v %+v", err, got)
	}
	if got.Profiles[0].Chain != "a" || got.Profiles[0].VATRatePct == nil || *got.Profiles[0].VATRatePct != 7 || got.Profiles[1].VATRatePct != nil {
		t.Fatalf("VAT not preserved: %+v", got.Profiles)
	}
}
