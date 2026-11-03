package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

// TradeMarketingHandler serves trade-marketing expense CRUD with tenant RLS.
type TradeMarketingHandler struct {
	repo  firestore.TradeMarketingRepository
	audit firestore.Repository
	sales TradeMarketingSalesSource
}

// NewTradeMarketingHandler constructs a TradeMarketingHandler. audit may be nil.
func NewTradeMarketingHandler(repo firestore.TradeMarketingRepository, audit firestore.Repository) *TradeMarketingHandler {
	return &TradeMarketingHandler{repo: repo, audit: audit}
}

var tmWriteRoles = map[domain.UserRole]bool{
	domain.RoleSuperAdmin: true, domain.RoleVendorAdmin: true, domain.RoleAdmin: true,
	domain.RoleNationalSalesManager: true, domain.RoleChainKAM: true, domain.RoleExecutive: true,
}

type expensePayload struct {
	Year           int     `json:"year"`
	Month          int     `json:"month"`
	ChainName      string  `json:"chain_name"`
	Category       string  `json:"category"`
	BrandName      string  `json:"brand_name"`
	CampaignTitle  string  `json:"campaign_title"`
	VendorOrAgency string  `json:"vendor_or_agency"`
	AmountEGP      float64 `json:"amount_egp"`
	Notes          string  `json:"notes"`
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func tmClaims(w http.ResponseWriter, r *http.Request) (*domain.UserClaims, bool) {
	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok || claims == nil || strings.TrimSpace(claims.TenantID) == "" {
		writeErr(w, http.StatusUnauthorized, "unauthorized tenant context")
		return nil, false
	}
	return claims, true
}

func kamChain(c *domain.UserClaims) string {
	if c.Role == domain.RoleChainKAM {
		return strings.TrimSpace(c.AssignedChain)
	}
	return ""
}

func (p expensePayload) validate() error {
	if p.Year < 2000 || p.Year > 2100 {
		return fmt.Errorf("year must be between 2000 and 2100")
	}
	if p.Month < 1 || p.Month > 12 {
		return fmt.Errorf("month must be 1-12")
	}
	if strings.TrimSpace(p.ChainName) == "" {
		return fmt.Errorf("chain_name is required")
	}
	if !domain.MarketingExpenseCategories[p.Category] {
		return fmt.Errorf("unknown category %q", p.Category)
	}
	if p.AmountEGP <= 0 {
		return fmt.Errorf("amount_egp must be positive")
	}
	return nil
}

func (h *TradeMarketingHandler) recordAudit(r *http.Request, c *domain.UserClaims, action, details string) {
	if h.audit == nil {
		return
	}
	_ = h.audit.SaveAuditLog(r.Context(), &domain.AuditLogEntry{
		TenantID: normalizeAuditTenantID(c.TenantID), UserID: c.UserID, UserEmail: c.Email,
		UserRole: string(c.Role), Action: action, Resource: "trade_marketing_expense",
		Details: details, IPAddress: extractRequestIP(r),
	})
}

// HandleListExpenses serves GET /api/v1/trade-marketing/expenses?year=&month=&chain=
func (h *TradeMarketingHandler) HandleListExpenses(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	q := r.URL.Query()
	year, _ := strconv.Atoi(q.Get("year"))
	month, _ := strconv.Atoi(q.Get("month"))
	chain := q.Get("chain")
	if k := kamChain(c); k != "" {
		chain = k
	}
	items, err := h.repo.ListMarketingExpenses(r.Context(), c.TenantID, domain.MarketingExpenseFilter{Year: year, Month: month, Chain: chain})
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to list expenses")
		return
	}
	total := 0.0
	for _, e := range items {
		total += e.AmountEGP
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"expenses": items, "count": len(items), "total_amount_egp": total})
}

// HandleCreateExpense serves POST /api/v1/trade-marketing/expenses
func (h *TradeMarketingHandler) HandleCreateExpense(w http.ResponseWriter, r *http.Request) {
	h.save(w, r, "")
}

// HandleUpdateExpense serves PUT /api/v1/trade-marketing/expenses/{id}
func (h *TradeMarketingHandler) HandleUpdateExpense(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(r.PathValue("id"))
	if id == "" {
		writeErr(w, http.StatusBadRequest, "missing expense id")
		return
	}
	h.save(w, r, id)
}

func (h *TradeMarketingHandler) save(w http.ResponseWriter, r *http.Request, id string) {
	c, ok := tmWriteClaims(w, r)
	if !ok {
		return
	}
	if !tmWriteRoles[c.Role] {
		writeErr(w, http.StatusForbidden, "role not allowed to modify trade marketing expenses")
		return
	}
	var p expensePayload
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&p); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	p.Category = strings.ToLower(strings.TrimSpace(p.Category))
	if err := p.validate(); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if k := kamChain(c); k != "" && !strings.EqualFold(k, strings.TrimSpace(p.ChainName)) {
		writeErr(w, http.StatusForbidden, "chain KAM can only record expenses for the assigned chain")
		return
	}
	if id != "" {
		existing, err := h.repo.ListMarketingExpenses(r.Context(), c.TenantID, domain.MarketingExpenseFilter{})
		if err != nil {
			writeErr(w, http.StatusInternalServerError, "failed to load expense")
			return
		}
		found := false
		for _, e := range existing {
			if e.ID == id {
				found = true
				if k := kamChain(c); k != "" && !strings.EqualFold(k, e.ChainName) {
					writeErr(w, http.StatusForbidden, "chain KAM can only edit the assigned chain")
					return
				}
			}
		}
		if !found {
			writeErr(w, http.StatusNotFound, "expense not found")
			return
		}
	}
	e := &domain.MarketingExpense{
		ID: id, TenantID: c.TenantID, Year: p.Year, Month: p.Month,
		ChainName: strings.TrimSpace(p.ChainName), Category: p.Category,
		BrandName: strings.TrimSpace(p.BrandName), CampaignTitle: strings.TrimSpace(p.CampaignTitle),
		VendorOrAgency: strings.TrimSpace(p.VendorOrAgency), AmountEGP: p.AmountEGP,
		Notes: strings.TrimSpace(p.Notes), CreatedBy: c.Email,
	}
	if err := h.repo.SaveMarketingExpense(r.Context(), e); err != nil {
		if errors.Is(err, firestore.ErrExpenseNotFound) {
			writeErr(w, http.StatusNotFound, "expense not found")
			return
		}
		writeErr(w, http.StatusInternalServerError, "failed to save expense")
		return
	}
	action, status := "CREATE_MARKETING_EXPENSE", http.StatusCreated
	if id != "" {
		action, status = "UPDATE_MARKETING_EXPENSE", http.StatusOK
	}
	h.recordAudit(r, c, action, fmt.Sprintf("%s %d-%02d %s %.2f EGP", e.ID, e.Year, e.Month, e.ChainName, e.AmountEGP))
	writeJSON(w, status, map[string]interface{}{"expense": e})
}

// HandleDeleteExpense serves DELETE /api/v1/trade-marketing/expenses/{id}
func (h *TradeMarketingHandler) HandleDeleteExpense(w http.ResponseWriter, r *http.Request) {
	c, ok := tmWriteClaims(w, r)
	if !ok {
		return
	}
	if !tmWriteRoles[c.Role] {
		writeErr(w, http.StatusForbidden, "role not allowed to modify trade marketing expenses")
		return
	}
	id := strings.TrimSpace(r.PathValue("id"))
	if k := kamChain(c); k != "" {
		items, err := h.repo.ListMarketingExpenses(r.Context(), c.TenantID, domain.MarketingExpenseFilter{Chain: k})
		if err != nil {
			writeErr(w, http.StatusInternalServerError, "failed to load expense")
			return
		}
		owned := false
		for _, e := range items {
			owned = owned || e.ID == id
		}
		if !owned {
			writeErr(w, http.StatusNotFound, "expense not found")
			return
		}
	}
	if err := h.repo.DeleteMarketingExpense(r.Context(), c.TenantID, id); err != nil {
		if errors.Is(err, firestore.ErrExpenseNotFound) {
			writeErr(w, http.StatusNotFound, "expense not found")
			return
		}
		writeErr(w, http.StatusInternalServerError, "failed to delete expense")
		return
	}
	h.recordAudit(r, c, "DELETE_MARKETING_EXPENSE", id)
	writeJSON(w, http.StatusOK, map[string]interface{}{"deleted": id})
}
