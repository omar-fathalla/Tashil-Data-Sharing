package dataquality

import (
	"archive/zip"
	"bytes"
	"context"
	"io"
	"os"
	"regexp"
	"sync"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

const realMaster = "../../../data/product_master/adeco_product_master_2026_08_01.xlsx"

type memStore struct {
	mu sync.Mutex
	m  map[string]*domain.DataQualityState
}

func (s *memStore) GetDataQualityState(_ context.Context, t string) (*domain.DataQualityState, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if d, ok := s.m[t]; ok {
		cp := *d
		cp.Issues = append([]domain.DataQualityIssue(nil), d.Issues...)
		cp.Runs = append([]domain.DataQualityRun(nil), d.Runs...)
		return &cp, nil
	}
	return &domain.DataQualityState{TenantID: t}, nil
}

func (s *memStore) SaveDataQualityState(_ context.Context, d *domain.DataQualityState) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.m == nil {
		s.m = map[string]*domain.DataQualityState{}
	}
	s.m[d.TenantID] = d
	return nil
}

func loadReal(t *testing.T) []byte {
	t.Helper()
	raw, err := os.ReadFile(realMaster) // read-only
	if err != nil {
		t.Skipf("real master not available: %v", err)
	}
	return raw
}

// setCells returns a copy of the xlsx with the given sheet1 cells replaced (value "" empties,
// "#N/A" makes an error cell, anything else an inline string).
func setCells(t *testing.T, raw []byte, cells map[string]string) []byte {
	t.Helper()
	zr, err := zip.NewReader(bytes.NewReader(raw), int64(len(raw)))
	if err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	zw := zip.NewWriter(&out)
	for _, f := range zr.File {
		rc, _ := f.Open()
		b, _ := io.ReadAll(rc)
		rc.Close()
		if f.Name == "xl/worksheets/sheet1.xml" {
			for ref, v := range cells {
				re := regexp.MustCompile(`<c r="` + ref + `"(?:[^>]*/>|[^>]*>.*?</c>)`)
				if !re.Match(b) {
					t.Fatalf("cell %s not found", ref)
				}
				repl := `<c r="` + ref + `"/>`
				switch {
				case v == "#N/A":
					repl = `<c r="` + ref + `" t="e"><v>#N/A</v></c>`
				case v != "":
					repl = `<c r="` + ref + `" t="inlineStr"><is><t>` + v + `</t></is></c>`
				}
				b = re.ReplaceAllLiteral(b, []byte(repl))
			}
		}
		w, _ := zw.Create(f.Name)
		w.Write(b)
	}
	zw.Close()
	return out.Bytes()
}

func countOpen(st *domain.DataQualityState) int {
	n := 0
	for _, i := range st.Issues {
		if i.Status == domain.DQStatusOpen {
			n++
		}
	}
	return n
}

func TestRealMasterCounts(t *testing.T) {
	raw := loadReal(t)
	res, err := CheckProductMaster("adeco_product_master_2026_08_01.xlsx", raw)
	if err != nil {
		t.Fatal(err)
	}
	by := map[string]int{}
	for _, i := range res.Issues {
		by[i.Type]++
	}
	t.Logf("rows=%d critical_rows=%d issues=%d by_type=%v", res.TotalRows, res.CriticalRows, len(res.Issues), by)
	want := map[string]int{domain.DQTypeDuplicateBarcode: 45, domain.DQTypeMissingBarcode: 3, domain.DQTypeMalformedBarcode: 2, domain.DQTypeNACell: 18}
	for k, v := range want {
		if by[k] != v {
			t.Errorf("%s = %d, want %d", k, by[k], v)
		}
	}
	if res.TotalRows != 389 || len(res.Issues) != 68 {
		t.Errorf("rows=%d issues=%d, want 389/68", res.TotalRows, len(res.Issues))
	}
	// edited-in-app values equal to the file must not change anything
	if again, _ := CheckProductMaster("adeco_product_master_2026_08_01.xlsx", raw, domain.ProductMasterItem{ItemCode: "FGHC-0700-0214", Barcode: "x"}); again == nil {
		t.Fatal("nil result")
	}
}

func TestEveryCheckOnMutatedCopy(t *testing.T) {
	raw := loadReal(t)
	base, _ := CheckProductMaster("m.xlsx", raw)
	for _, i := range base.Issues {
		if i.Row == 10 {
			t.Fatalf("row 10 expected clean in real master, has %s", i.Type)
		}
	}
	cases := []struct {
		name  string
		cells map[string]string
		typ   string
	}{
		{"missing code", map[string]string{"B10": ""}, domain.DQTypeMissingCode},
		{"missing barcode", map[string]string{"C10": ""}, domain.DQTypeMissingBarcode},
		{"malformed barcode", map[string]string{"C10": "6223000123"}, domain.DQTypeMalformedBarcode},
		{"zero price", map[string]string{"K10": "0"}, domain.DQTypeInvalidPrice},
		{"negative price", map[string]string{"N10": "-5"}, domain.DQTypeInvalidPrice},
		{"carton mismatch", map[string]string{"O10": "1"}, domain.DQTypeCartonPriceMismatch},
		{"vat not 14", map[string]string{"H10": "0.1"}, domain.DQTypeVATNot14},
		{"discount out of range", map[string]string{"E10": "0.9"}, domain.DQTypeInvoiceDiscountRange},
		{"missing pack type", map[string]string{"I10": ""}, domain.DQTypeMissingPackType},
		{"missing units per carton", map[string]string{"J10": ""}, domain.DQTypeMissingUnitsPerCarton},
		{"#N/A cell", map[string]string{"D10": "#N/A"}, domain.DQTypeNACell},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			res, err := CheckProductMaster("m.xlsx", setCells(t, raw, c.cells))
			if err != nil {
				t.Fatal(err)
			}
			for _, i := range res.Issues {
				if i.Row == 10 && i.Type == c.typ {
					return
				}
			}
			t.Errorf("no %s issue on row 10", c.typ)
		})
	}
	// duplicate: copy row 11's barcode into row 10
	_, rows, _ := readFirstSheet(raw)
	var bc string
	for _, r := range rows {
		if r.Num == 11 {
			bc = r.Cells[2]
		}
	}
	res, _ := CheckProductMaster("m.xlsx", setCells(t, raw, map[string]string{"C10": bc}))
	found := false
	for _, i := range res.Issues {
		if i.Row == 10 && i.Type == domain.DQTypeDuplicateBarcode {
			found = true
		}
	}
	if !found {
		t.Error("no duplicate_barcode on row 10")
	}
}

// End-to-end: a known duplicate barcode auto-resolves when fixed in a temp copy, status persists.
func TestE2EAutoResolveOnFix(t *testing.T) {
	raw := loadReal(t)
	ctx := context.Background()
	store := &memStore{}
	svc := NewService(store, nil)
	now := time.Date(2026, 10, 25, 9, 0, 0, 0, time.UTC)
	svc.now = func() time.Time { return now }
	const tenant = "adeco"

	if _, err := svc.RunProductMaster(ctx, tenant, "m.xlsx", raw); err != nil {
		t.Fatal(err)
	}
	before, _ := svc.Summary(ctx, tenant)
	st, _ := store.GetDataQualityState(ctx, tenant)
	openBefore := countOpen(st)
	var dup []domain.DataQualityIssue
	for _, i := range st.Issues {
		if i.Type == domain.DQTypeDuplicateBarcode && i.Barcode == "6223000233436" && i.Status == domain.DQStatusOpen {
			dup = append(dup, i)
		}
	}
	if len(dup) != 2 {
		t.Fatalf("known duplicate 6223000233436 issues = %d, want 2", len(dup))
	}
	// manual ignore on an unrelated issue must survive the re-run
	var ignoredID string
	for _, i := range st.Issues {
		if i.Type == domain.DQTypeMissingBarcode {
			ignoredID = i.ID
			break
		}
	}
	if _, err := svc.UpdateStatus(ctx, tenant, ignoredID, domain.DQStatusIgnored, "", "u"); err == nil {
		t.Fatal("ignore without reason must fail")
	}
	if _, err := svc.UpdateStatus(ctx, tenant, ignoredID, domain.DQStatusIgnored, "صنف جديد بدون باركود", "u"); err != nil {
		t.Fatal(err)
	}
	afterIgnore := countOpen(mustState(t, store, tenant))

	// fix: give FGHC-0700-0214 (row 299) its own valid GTIN
	fixed := setCells(t, raw, map[string]string{"C299": "6223000299999"})
	now = now.Add(time.Hour)
	if _, err := svc.RunProductMaster(ctx, tenant, "m.xlsx", fixed); err != nil {
		t.Fatal(err)
	}
	after, _ := svc.Summary(ctx, tenant)
	st2 := mustState(t, store, tenant)
	openAfter := countOpen(st2)
	for _, i := range st2.Issues {
		for _, d := range dup {
			if i.ID == d.ID && (i.Status != domain.DQStatusResolved || !i.AutoClosed || i.ResolvedAt == nil) {
				t.Errorf("%s not auto-resolved: %s", i.ItemCode, i.Status)
			}
		}
		if i.ID == ignoredID && i.Status != domain.DQStatusIgnored {
			t.Errorf("manual ignore lost: %s", i.Status)
		}
	}
	if afterIgnore-openAfter != 2 {
		t.Errorf("open dropped by %d, want 2", afterIgnore-openAfter)
	}
	if after.CleanlinessPc <= before.CleanlinessPc {
		t.Errorf("cleanliness did not rise: %.2f -> %.2f", before.CleanlinessPc, after.CleanlinessPc)
	}
	open, _ := svc.ListIssues(ctx, tenant, IssueFilter{Status: domain.DQStatusOpen})
	for _, i := range open {
		if i.Barcode == "6223000233436" && i.Type == domain.DQTypeDuplicateBarcode {
			t.Error("resolved issue still in open view")
		}
	}
	t.Logf("BEFORE open=%d critical_rows=%d cleanliness=%.2f%% | after ignore open=%d | AFTER fix open=%d critical_rows=%d cleanliness=%.2f%% resolved=%d",
		openBefore, before.CriticalRows, before.CleanlinessPc, afterIgnore, openAfter, after.CriticalRows, after.CleanlinessPc, after.Resolved)

	// reverting the fix reopens the issues
	now = now.Add(time.Hour)
	svc.RunProductMaster(ctx, tenant, "m.xlsx", raw)
	for _, i := range mustState(t, store, tenant).Issues {
		for _, d := range dup {
			if i.ID == d.ID && (i.Status != domain.DQStatusOpen || i.ResolvedAt != nil) {
				t.Errorf("%s not reopened", i.ItemCode)
			}
		}
	}
}

// In-app master edit (no new upload) + debounced source-change hook closes the issue.
func TestE2EAutoResolveOnMasterEdit(t *testing.T) {
	raw := loadReal(t)
	ctx := context.Background()
	store := &memStore{}
	master := &fakeMaster{}
	svc := NewService(store, nil).WithMaster(master)
	old := RerunDelay
	RerunDelay = 10 * time.Millisecond
	defer func() { RerunDelay = old }()
	svc.SetProductMasterFile("adeco", "m.xlsx", raw)
	svc.RerunAll(ctx)
	before := countOpen(mustState(t, store, "adeco"))

	items := parsedItems(t, raw)
	for i := range items {
		if items[i].ItemCode == "FGHC-0700-0214" {
			items[i].Barcode = "6223000299999"
		}
	}
	master.set(items)
	svc.OnSourceChanged()
	svc.OnSourceChanged() // burst collapses
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if countOpen(mustState(t, store, "adeco")) == before-2 {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("open after edit = %d, want %d", countOpen(mustState(t, store, "adeco")), before-2)
}

func TestReconcileKeepsFirstSeen(t *testing.T) {
	st := &domain.DataQualityState{}
	t0 := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	a := domain.DataQualityIssue{ID: "a", Source: domain.DQSourceProductMaster, Status: domain.DQStatusOpen}
	Reconcile(st, domain.DQSourceProductMaster, []domain.DataQualityIssue{a}, t0)
	Reconcile(st, domain.DQSourceProductMaster, []domain.DataQualityIssue{a}, t0.Add(time.Hour))
	if !st.Issues[0].FirstSeen.Equal(t0) {
		t.Errorf("first_seen changed: %v", st.Issues[0].FirstSeen)
	}
	Reconcile(st, "sell_out", nil, t0.Add(2*time.Hour))
	if st.Issues[0].Status != domain.DQStatusOpen {
		t.Error("other source run must not close product master issues")
	}
}

func mustState(t *testing.T, s *memStore, tenant string) *domain.DataQualityState {
	st, err := s.GetDataQualityState(context.Background(), tenant)
	if err != nil {
		t.Fatal(err)
	}
	return st
}

func TestSummaryWithoutRunsUsesIssueCounts(t *testing.T) {
	store := &memStore{m: map[string]*domain.DataQualityState{
		"adeco": {
			TenantID: "adeco",
			Issues: []domain.DataQualityIssue{
				{ID: "1", Source: domain.DQSourceProductMaster, Type: domain.DQTypeDuplicateBarcode, TypeLabel: "باركود مكرر",
					Severity: domain.DQSeverityCritical, Row: 10, Status: domain.DQStatusOpen},
				{ID: "2", Source: domain.DQSourceProductMaster, Type: domain.DQTypeDuplicateBarcode, TypeLabel: "باركود مكرر",
					Severity: domain.DQSeverityCritical, Row: 11, Status: domain.DQStatusOpen},
				{ID: "3", Source: domain.DQSourceProductMaster, Type: domain.DQTypeMissingBarcode, TypeLabel: "باركود ناقص",
					Severity: domain.DQSeverityCritical, Row: 12, Status: domain.DQStatusResolved},
				{ID: "4", Source: DQSourceSellInUploadPrefix + "in.xlsx", Type: DQTypeUnknownItem, TypeLabel: "صنف مش موجود",
					Severity: domain.DQSeverityWarning, Row: 0, Status: domain.DQStatusOpen},
			},
			// Runs intentionally empty — matches prod after restart when PM file was never re-registered.
		},
	}}
	svc := NewService(store, nil)
	sum, err := svc.Summary(context.Background(), "adeco")
	if err != nil {
		t.Fatal(err)
	}
	if sum.Open != 3 || sum.Resolved != 1 {
		t.Fatalf("open/resolved = %d/%d, want 3/1", sum.Open, sum.Resolved)
	}
	if sum.TotalRows <= 0 {
		t.Fatalf("TotalRows=%d, want >0 when open issues exist without Runs", sum.TotalRows)
	}
	if sum.CriticalRows < 2 {
		t.Fatalf("CriticalRows=%d, want >=2", sum.CriticalRows)
	}
	if sum.CleanlinessPc >= 100 {
		t.Fatalf("cleanliness=%.2f, want <100 with open critical rows", sum.CleanlinessPc)
	}
}

func TestRecordSellInUnknownItemsWritesRun(t *testing.T) {
	store := &memStore{}
	svc := NewService(store, nil)
	err := svc.RecordSellInUnknownItems(context.Background(), "adeco", "plan.xlsx", []UnknownItem{
		{ItemCode: "X1", Barcode: "1", ItemName: "a", Rows: 41, Value: 100},
		{ItemCode: "X2", Barcode: "2", ItemName: "b", Rows: 31, Value: 50},
		{ItemCode: "X3", Barcode: "3", ItemName: "c", Rows: 6, Value: 10},
	})
	if err != nil {
		t.Fatal(err)
	}
	st := mustState(t, store, "adeco")
	if len(st.Runs) != 1 || st.Runs[0].TotalRows != 78 {
		t.Fatalf("runs=%+v, want one run with 78 rows", st.Runs)
	}
	sum, err := svc.Summary(context.Background(), "adeco")
	if err != nil {
		t.Fatal(err)
	}
	if sum.Open != 3 || sum.TotalRows != 78 {
		t.Fatalf("summary open=%d total=%d, want 3/78", sum.Open, sum.TotalRows)
	}
	if sum.CleanlinessPc != 100 {
		t.Fatalf("warnings-only cleanliness=%.2f, want 100", sum.CleanlinessPc)
	}
}
