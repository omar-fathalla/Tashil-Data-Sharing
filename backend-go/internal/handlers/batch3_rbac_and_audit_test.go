package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

func TestFiveRoleRBACLoginAndJWTClaims(t *testing.T) {
	_, authMW, authHandler := setupAuthTest()

	testCases := []struct {
		name           string
		tenantID       string
		email          string
		password       string
		expectedRole   domain.UserRole
		expectedChain  string
		expectedRegion string
		expectedAr     string
	}{
		{
			name:         "Super Admin",
			tenantID:     "system",
			email:        testSuperAdminEmail,
			password:     testSuperAdminPassword,
			expectedRole: domain.RoleSuperAdmin,
			expectedAr:   "مدير عام المنصة (Super Admin)",
		},
		{
			name:         "Adeco Vendor Admin",
			tenantID:     "adeco",
			email:        "admin@adeco-retail.com",
			password:     testAdecoAdminPassword,
			expectedRole: domain.RoleVendorAdmin,
			expectedAr:   "مدير الشركة الموردة",
		},
		{
			name:         "Adeco National Sales Manager",
			tenantID:     "adeco",
			email:        "nsm@adeco-retail.com",
			password:     testAdecoRolePassword,
			expectedRole: domain.RoleNationalSalesManager,
			expectedAr:   "مدير المبيعات الوطني",
		},
		{
			name:          "Adeco Carrefour Chain KAM",
			tenantID:      "adeco",
			email:         "kam.carrefour@adeco-retail.com",
			password:      testAdecoRolePassword,
			expectedRole:  domain.RoleChainKAM,
			expectedChain: "carrefour",
			expectedAr:    "مدير حسابات السلاسل (KAM)",
		},
		{
			name:           "Adeco East Alexandria Field Supervisor",
			tenantID:       "adeco",
			email:          "supervisor.alex@adeco-retail.com",
			password:       testAdecoRolePassword,
			expectedRole:   domain.RoleFieldSupervisor,
			expectedRegion: "شرق الإسكندرية",
			expectedAr:     "مشرف ميداني (Field Supervisor)",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			body, _ := json.Marshal(domain.LoginRequest{
				TenantID: tc.tenantID,
				Email:    tc.email,
				Password: tc.password,
			})
			req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(body))
			rec := httptest.NewRecorder()

			authHandler.HandleLogin(rec, req)
			if rec.Code != http.StatusOK {
				t.Fatalf("expected HTTP 200 for %s, got %d: %s", tc.email, rec.Code, rec.Body.String())
			}

			var resp domain.LoginResponse
			if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
				t.Fatalf("failed to decode response: %v", err)
			}

			if resp.User.Role != tc.expectedRole {
				t.Errorf("expected role %s, got %s", tc.expectedRole, resp.User.Role)
			}
			if resp.User.AssignedChain != tc.expectedChain {
				t.Errorf("expected assigned_chain %q, got %q", tc.expectedChain, resp.User.AssignedChain)
			}
			if resp.User.AssignedRegion != tc.expectedRegion {
				t.Errorf("expected assigned_region %q, got %q", tc.expectedRegion, resp.User.AssignedRegion)
			}
			if resp.User.RoleDisplayAr != tc.expectedAr {
				t.Errorf("expected role_display_ar %q, got %q", tc.expectedAr, resp.User.RoleDisplayAr)
			}

			// Verify JWT token carries the RBAC claims through AuthMiddleware
			var capturedClaims *domain.UserClaims
			next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				capturedClaims, _ = middleware.GetUserClaims(r.Context())
				w.WriteHeader(http.StatusOK)
			})
			protectedReq := httptest.NewRequest(http.MethodGet, "/api/v1/analytics/executive-summary", nil)
			protectedReq.Header.Set("Authorization", "Bearer "+resp.Token)
			protectedRec := httptest.NewRecorder()

			authMW.Handler(next).ServeHTTP(protectedRec, protectedReq)
			if protectedRec.Code != http.StatusOK || capturedClaims == nil {
				t.Fatalf("expected valid JWT verification, code=%d", protectedRec.Code)
			}
			if capturedClaims.Role != tc.expectedRole {
				t.Errorf("expected JWT role %s, got %s", tc.expectedRole, capturedClaims.Role)
			}
			if capturedClaims.AssignedChain != tc.expectedChain {
				t.Errorf("expected JWT assigned_chain %q, got %q", tc.expectedChain, capturedClaims.AssignedChain)
			}
			if capturedClaims.AssignedRegion != tc.expectedRegion {
				t.Errorf("expected JWT assigned_region %q, got %q", tc.expectedRegion, capturedClaims.AssignedRegion)
			}
		})
	}
}

func TestChainKAMNDAProtectionAndFieldSupervisorScoping(t *testing.T) {
	bqClient := bigquery.NewClient("test-project", "test-dataset", true)
	analyticsHandler := NewAnalyticsHandler(bqClient)

	kamClaims := &domain.UserClaims{
		UserID:        "user-adeco-kam-carrefour",
		TenantID:      "tenant-adeco",
		Email:         "kam.carrefour@adeco-retail.com",
		Role:          domain.RoleChainKAM,
		Name:          "سارة حسني",
		AssignedChain: "carrefour",
	}

	// 1. Executive Summary masks non-Carrefour chains with NDA redaction
	reqExec := httptest.NewRequest(http.MethodGet, "/api/v1/analytics/executive-summary?period=MTD", nil)
	reqExec = reqExec.WithContext(context.WithValue(reqExec.Context(), middleware.UserClaimsContextKey, kamClaims))
	recExec := httptest.NewRecorder()

	analyticsHandler.HandleExecutiveSummary(recExec, reqExec)
	if recExec.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200, got %d", recExec.Code)
	}

	var kpis domain.ExecutiveKPIs
	if err := json.NewDecoder(recExec.Body).Decode(&kpis); err != nil {
		t.Fatalf("failed to decode ExecutiveKPIs: %v", err)
	}

	sawCarrefour := false
	sawRedacted := false
	for _, cs := range kpis.ChainShares {
		if strings.EqualFold(cs.RetailerChain, "carrefour") {
			sawCarrefour = true
			if cs.DisplayName == "سلسلة تجزئة منافسة (محمي بـ NDA)" {
				t.Errorf("assigned chain carrefour should not be redacted")
			}
		} else {
			sawRedacted = true
			if cs.RetailerChain != "nda_redacted" {
				t.Errorf("expected competitor chain code to be 'nda_redacted', got %q", cs.RetailerChain)
			}
			if cs.DisplayName != "سلسلة تجزئة منافسة (محمي بـ NDA)" {
				t.Errorf("expected competitor display_name to be 'سلسلة تجزئة منافسة (محمي بـ NDA)', got %q", cs.DisplayName)
			}
		}
	}
	if !sawCarrefour || !sawRedacted {
		t.Errorf("expected both carrefour and redacted competitor chains, sawCarrefour=%v sawRedacted=%v", sawCarrefour, sawRedacted)
	}

	// 2. Records, StoreMatrix, and PricingCompliance override chain filter to KAM's AssignedChain
	reqRecs := httptest.NewRequest(http.MethodGet, "/api/v1/analytics/records?chain=fathalla", nil)
	reqRecs = reqRecs.WithContext(context.WithValue(reqRecs.Context(), middleware.UserClaimsContextKey, kamClaims))
	recRecs := httptest.NewRecorder()
	analyticsHandler.HandleRecords(recRecs, reqRecs)

	var recsPayload struct {
		Records []domain.SellOutFact `json:"records"`
	}
	_ = json.NewDecoder(recRecs.Body).Decode(&recsPayload)
	if len(recsPayload.Records) == 0 {
		t.Fatalf("expected carrefour records for KAM, got 0")
	}
	for _, r := range recsPayload.Records {
		if !strings.EqualFold(r.RetailerChain, "carrefour") {
			t.Errorf("KAM leaked non-carrefour record: %s", r.RetailerChain)
		}
	}

	reqStores := httptest.NewRequest(http.MethodGet, "/api/v1/analytics/store-matrix?chain=fathalla", nil)
	reqStores = reqStores.WithContext(context.WithValue(reqStores.Context(), middleware.UserClaimsContextKey, kamClaims))
	recStores := httptest.NewRecorder()
	analyticsHandler.HandleStoreMatrix(recStores, reqStores)

	var kamStores []domain.StoreBenchmarkItem
	_ = json.NewDecoder(recStores.Body).Decode(&kamStores)
	if len(kamStores) == 0 {
		t.Fatalf("expected carrefour stores for KAM, got 0")
	}
	for _, s := range kamStores {
		if !strings.EqualFold(s.RetailerChain, "carrefour") {
			t.Errorf("KAM store matrix leaked non-carrefour store: %s", s.RetailerChain)
		}
	}

	reqPricing := httptest.NewRequest(http.MethodGet, "/api/v1/analytics/pricing-compliance?chain=spinneys", nil)
	reqPricing = reqPricing.WithContext(context.WithValue(reqPricing.Context(), middleware.UserClaimsContextKey, kamClaims))
	recPricing := httptest.NewRecorder()
	analyticsHandler.HandlePricingCompliance(recPricing, reqPricing)

	var kamPricing []domain.PricingComplianceItem
	_ = json.NewDecoder(recPricing.Body).Decode(&kamPricing)
	if len(kamPricing) == 0 {
		t.Fatalf("expected carrefour pricing items for KAM, got 0")
	}
	for _, p := range kamPricing {
		if !strings.EqualFold(p.RetailerChain, "carrefour") {
			t.Errorf("KAM pricing compliance leaked non-carrefour item: %s", p.RetailerChain)
		}
	}

	// 3. Field Supervisor Regional Scoping in HandleStoreMatrix
	supClaims := &domain.UserClaims{
		UserID:         "user-adeco-sup-alex",
		TenantID:       "tenant-adeco",
		Email:          "supervisor.alex@adeco-retail.com",
		Role:           domain.RoleFieldSupervisor,
		Name:           "محمود جلال",
		AssignedRegion: "شرق الإسكندرية",
	}

	reqSupStores := httptest.NewRequest(http.MethodGet, "/api/v1/analytics/store-matrix?region=القاهرة+الكبرى", nil)
	reqSupStores = reqSupStores.WithContext(context.WithValue(reqSupStores.Context(), middleware.UserClaimsContextKey, supClaims))
	recSupStores := httptest.NewRecorder()
	analyticsHandler.HandleStoreMatrix(recSupStores, reqSupStores)

	var supStores []domain.StoreBenchmarkItem
	_ = json.NewDecoder(recSupStores.Body).Decode(&supStores)
	if len(supStores) == 0 {
		t.Fatalf("expected East Alexandria stores for Field Supervisor, got 0")
	}
	for _, s := range supStores {
		if s.Region != "شرق الإسكندرية" {
			t.Errorf("Field Supervisor store matrix leaked store outside شرق الإسكندرية: %s (%s)", s.StoreName, s.Region)
		}
	}

	// 4. Verify X-Simulated-Role, X-Assigned-Chain, and X-Assigned-Region headers via AuthMiddleware
	authMW := middleware.NewAuthMiddleware("test-secret", true)
	simReq := httptest.NewRequest(http.MethodGet, "/api/v1/analytics/executive-summary", nil)
	simReq.Header.Set("Authorization", "Bearer demo-adeco-token")
	simReq.Header.Set("X-Simulated-Role", string(domain.RoleChainKAM))
	simReq.Header.Set("X-Assigned-Chain", "fathalla")
	simRec := httptest.NewRecorder()

	authMW.Handler(http.HandlerFunc(analyticsHandler.HandleExecutiveSummary)).ServeHTTP(simRec, simReq)
	if simRec.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200 on simulated KAM request, got %d", simRec.Code)
	}
	var simKPIs domain.ExecutiveKPIs
	_ = json.NewDecoder(simRec.Body).Decode(&simKPIs)
	for _, cs := range simKPIs.ChainShares {
		if !strings.EqualFold(cs.RetailerChain, "fathalla") && cs.RetailerChain != "nda_redacted" {
			t.Errorf("expected non-fathalla chain to be nda_redacted under simulated KAM, got %s", cs.RetailerChain)
		}
	}
}

func TestEnterpriseAuditLogsRLSAndEndpoints(t *testing.T) {
	fsClient := firestore.NewClient("test-db", true)
	auditHandler := NewAuditHandler(fsClient)

	adecoClaims := &domain.UserClaims{
		UserID:   "user-adeco-admin-01",
		TenantID: "tenant-adeco",
		Email:    "admin@adeco-retail.com",
		Role:     domain.RoleVendorAdmin,
		Name:     "أحمد المنشاوي",
	}

	// 1. GET /api/v1/audit/logs for Adeco returns only Adeco logs
	reqGet := httptest.NewRequest(http.MethodGet, "/api/v1/audit/logs?tenant_id=unilever", nil)
	reqGet = reqGet.WithContext(context.WithValue(reqGet.Context(), middleware.UserClaimsContextKey, adecoClaims))
	recGet := httptest.NewRecorder()

	auditHandler.HandleGetAuditLogs(recGet, reqGet)
	if recGet.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200, got %d: %s", recGet.Code, recGet.Body.String())
	}

	var adecoLogs []domain.AuditLogEntry
	if err := json.NewDecoder(recGet.Body).Decode(&adecoLogs); err != nil {
		t.Fatalf("failed to decode audit logs: %v", err)
	}
	if len(adecoLogs) < 4 {
		t.Fatalf("expected at least 4 seeded audit logs for adeco, got %d", len(adecoLogs))
	}
	for _, entry := range adecoLogs {
		if entry.TenantID != "tenant-adeco" {
			t.Errorf("RLS violation: adeco user received audit log for tenant %s", entry.TenantID)
		}
	}

	// 2. POST /api/v1/audit/logs records a new audit entry scoped to caller's tenant
	postBody, _ := json.Marshal(domain.CreateAuditLogRequest{
		Action:   "EXPORT_EXCEL",
		Resource: "executive_pareto_report.xlsx",
		Details:  "تصدير تقرير باريتو 80/20 ومساهمة الفئات",
	})
	reqPost := httptest.NewRequest(http.MethodPost, "/api/v1/audit/logs", bytes.NewReader(postBody))
	reqPost = reqPost.WithContext(context.WithValue(reqPost.Context(), middleware.UserClaimsContextKey, adecoClaims))
	recPost := httptest.NewRecorder()

	auditHandler.HandleCreateAuditLog(recPost, reqPost)
	if recPost.Code != http.StatusCreated {
		t.Fatalf("expected HTTP 201 Created, got %d: %s", recPost.Code, recPost.Body.String())
	}

	var createdEntry domain.AuditLogEntry
	if err := json.NewDecoder(recPost.Body).Decode(&createdEntry); err != nil {
		t.Fatalf("failed to decode created audit log: %v", err)
	}
	if createdEntry.TenantID != "tenant-adeco" || createdEntry.Action != "EXPORT_EXCEL" {
		t.Errorf("unexpected created audit log entry: %+v", createdEntry)
	}

	// 3. Filter GET /api/v1/audit/logs?action=EXPORT_EXCEL
	reqFilter := httptest.NewRequest(http.MethodGet, "/api/v1/audit/logs?action=EXPORT_EXCEL", nil)
	reqFilter = reqFilter.WithContext(context.WithValue(reqFilter.Context(), middleware.UserClaimsContextKey, adecoClaims))
	recFilter := httptest.NewRecorder()

	auditHandler.HandleGetAuditLogs(recFilter, reqFilter)
	var exportLogs []domain.AuditLogEntry
	_ = json.NewDecoder(recFilter.Body).Decode(&exportLogs)
	if len(exportLogs) < 2 {
		t.Fatalf("expected at least 2 EXPORT_EXCEL logs for adeco after POST, got %d", len(exportLogs))
	}
	for _, entry := range exportLogs {
		if entry.Action != "EXPORT_EXCEL" {
			t.Errorf("expected action EXPORT_EXCEL, got %s", entry.Action)
		}
	}

	// 4. Verify Unilever tenant cannot see Adeco's newly created log
	unileverClaims := &domain.UserClaims{
		UserID:   "user-unilever-admin-01",
		TenantID: "tenant-unilever",
		Email:    "admin@unilever-retail.com",
		Role:     domain.RoleVendorAdmin,
	}
	reqUni := httptest.NewRequest(http.MethodGet, "/api/v1/audit/logs", nil)
	reqUni = reqUni.WithContext(context.WithValue(reqUni.Context(), middleware.UserClaimsContextKey, unileverClaims))
	recUni := httptest.NewRecorder()
	auditHandler.HandleGetAuditLogs(recUni, reqUni)

	var uniLogs []domain.AuditLogEntry
	_ = json.NewDecoder(recUni.Body).Decode(&uniLogs)
	if len(uniLogs) == 0 {
		t.Fatalf("expected seeded logs for unilever, got 0")
	}
	for _, entry := range uniLogs {
		if entry.TenantID != "tenant-unilever" {
			t.Errorf("RLS violation: unilever user received log for %s", entry.TenantID)
		}
	}

	// 5. Verify Super Admin with system tenant sees logs across all tenants
	superClaims := &domain.UserClaims{
		UserID:   "user-super-admin-io",
		TenantID: "system",
		Email:    "superadmin@tashil.io",
		Role:     domain.RoleSuperAdmin,
	}
	reqSuper := httptest.NewRequest(http.MethodGet, "/api/v1/audit/logs", nil)
	reqSuper = reqSuper.WithContext(context.WithValue(reqSuper.Context(), middleware.UserClaimsContextKey, superClaims))
	recSuper := httptest.NewRecorder()
	auditHandler.HandleGetAuditLogs(recSuper, reqSuper)

	var allLogs []domain.AuditLogEntry
	_ = json.NewDecoder(recSuper.Body).Decode(&allLogs)
	if len(allLogs) < 12 {
		t.Errorf("expected Super Admin to see >= 12 logs across all tenants, got %d", len(allLogs))
	}
}
