package firestore

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/tashil/data-sharing/backend/internal/service/customers"
	"log"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	cloudFirestore "cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/security"
)

// Repository defines OLTP Firestore operations for metadata, tenants, alerts, and auth.
type Repository interface {
	GetTenant(ctx context.Context, tenantID string) (*domain.Tenant, error)
	ListTenants(ctx context.Context) ([]domain.Tenant, error)
	GetStoresByTenant(ctx context.Context, tenantID string) ([]domain.Store, error)
	UpsertStoresByTenant(ctx context.Context, tenantID string, stores []domain.Store, replaceAll bool) (int, error)
	SaveIngestionBatch(ctx context.Context, batch *domain.IngestionBatch) error
	ListIngestionBatches(ctx context.Context, tenantID string) ([]domain.IngestionBatch, error)
	GetOOSAlerts(ctx context.Context, tenantID string) ([]domain.OOSAlert, error)
	ReplaceOOSAlerts(ctx context.Context, tenantID string, alerts []domain.OOSAlert) error
	ClearTenantData(ctx context.Context, tenantID string) error

	// Multi-tenant auth & profiles
	GetTenantProfile(ctx context.Context, tenantID string) (*domain.TenantProfile, error)
	GetTenantProfileBySlug(ctx context.Context, slug string) (*domain.TenantProfile, error)
	ListTenantProfiles(ctx context.Context) ([]domain.TenantProfile, error)
	SaveTenantProfile(ctx context.Context, profile *domain.TenantProfile) error
	DeleteTenantProfile(ctx context.Context, slug string) error
	AuthReady() error
	EnsureAuthUsersFresh(ctx context.Context) error
	RefreshAuthUsers(ctx context.Context) error
	GetUserByEmail(ctx context.Context, tenantID string, email string) (*domain.TenantUser, error)
	GetUserByID(ctx context.Context, userID string) (*domain.TenantUser, error)
	GetUserByResetToken(ctx context.Context, token string) (*domain.TenantUser, error)
	SaveUser(ctx context.Context, user *domain.TenantUser) error
	UpdateUserPassword(ctx context.Context, userID string, passwordHash string) error
	SetUserResetToken(ctx context.Context, userID string, token string, expiry time.Time) error

	// Tenant-Scoped & Master Retail Chains Catalog
	ListRetailChains(ctx context.Context) ([]domain.RetailChain, error)
	ListRetailChainsByTenant(ctx context.Context, tenantID string) ([]domain.RetailChain, error)
	GetRetailChain(ctx context.Context, code string) (*domain.RetailChain, error)
	GetRetailChainByTenant(ctx context.Context, tenantID string, code string) (*domain.RetailChain, error)
	SaveRetailChain(ctx context.Context, chain *domain.RetailChain) error
	CreateRetailChain(ctx context.Context, chain *domain.RetailChain) error
	DeleteRetailChain(ctx context.Context, code string) error
	DeleteRetailChainByTenant(ctx context.Context, tenantID string, code string) error

	// Enterprise Security Audit Logs
	SaveAuditLog(ctx context.Context, entry *domain.AuditLogEntry) error
	GetAuditLogs(ctx context.Context, tenantID string, actionFilter string, limit int) ([]domain.AuditLogEntry, error)

	// Persistent Archive Deletion Tombstones (Cloud Firestore Single Source of Truth)
	MarkArchiveDeleted(ctx context.Context, tenantID, archiveID, fileName string) error
	UnmarkArchiveDeleted(ctx context.Context, tenantID, archiveID, fileName string) error
	IsArchiveDeleted(tenantID, archiveID, fileName string) bool
	// RememberArchiveDeleted applies a tombstone to the in-memory map only (no remote write).
	// When archiveID is set, only the id key is recorded (not the filename) so a later same-name
	// reupload is not hidden by stale name tombs. Name keys are for archiveID-empty tombs only.
	RememberArchiveDeleted(tenantID, archiveID, fileName string)
	// ForgetArchiveNameDeleted clears a filename tombstone in memory (durable disk/Firestore unmark
	// already recorded). Does not un-delete archive ids.
	ForgetArchiveNameDeleted(tenantID, fileName string)
	// RefreshDeletedArchives re-reads deleted_archives from Cloud Firestore into memory.
	// No-op when Firestore is not configured. Fetch runs outside the repo mutex with a bounded
	// context; returns a non-nil error when the remote read fails (callers may still apply disk tombs).
	RefreshDeletedArchives(ctx context.Context) error
}

// Client implements Repository with fast in-memory storage for Cloud Run and local tests,
// synchronized in real-time with Google Cloud Firestore.
type Client struct {
	mu                sync.RWMutex
	fsClient          *cloudFirestore.Client
	projectID         string
	databaseID        string
	tenants           map[string]domain.Tenant
	tenantProfiles    map[string]domain.TenantProfile
	users             map[string]domain.TenantUser
	userByTenantEmail map[string]string // "tenant|email" → userID (deduped login index)
	authReady         bool
	authErr           error
	authRefreshedAt   time.Time
	// Per-user write gates serialize persist-then-publish so a failed older
	// write cannot roll back or race a newer successful update.
	userWriteGatesMu sync.Mutex
	userWriteGates   map[string]*sync.Mutex
	// Optional test seam; when set, replaces the Firestore Set path.
	persistTenantUserFn func(ctx context.Context, u domain.TenantUser) error
	stores              map[string][]domain.Store
	retailChains        map[string]domain.RetailChain
	tenantRetailChains  map[string]map[string]domain.RetailChain
	batches             []domain.IngestionBatch
	alerts              []domain.OOSAlert
	auditLogs           []domain.AuditLogEntry
	cleanedTenants      map[string]bool
	deletedArchives     map[string]bool

	// Trade marketing expenses (see trade_marketing.go)
	tmMu       sync.RWMutex
	tmExpenses map[string]domain.MarketingExpense

	ccMu   sync.RWMutex
	ccSkus map[string]domain.CustomCompetitorSku

	cmapMu sync.RWMutex
	cmaps  map[string]domain.CompetitorMapping

	// Per-tenant chain discount profiles (see chain_discounts.go)
	cdMu       sync.RWMutex
	cdProfiles map[string]domain.ChainDiscountProfiles
	dqMu       sync.RWMutex
	dqStates   map[string]domain.DataQualityState
	crMem      customers.MemoryStore // customer registry fallback when Firestore is not configured
	pmOnce     sync.Once
	pmStates   *productMatchMem // product-match review queue fallback when Firestore is not configured

	dvMu         sync.Mutex
	dataVersions map[string]string
	leases       map[string]memLease
}

// Reserved auth identity that must never be overwritten by Firestore tenant_users docs.
const reservedSuperAdminUserID = "user-super-admin"

// NewClient constructs the Firestore repository with initial seeded entities and live Cloud Firestore sync.
func NewClient(databaseID string, useMock bool) *Client {
	c := &Client{
		databaseID:         databaseID,
		tenants:            make(map[string]domain.Tenant),
		tenantProfiles:     make(map[string]domain.TenantProfile),
		users:              make(map[string]domain.TenantUser),
		userByTenantEmail:  make(map[string]string),
		userWriteGates:     make(map[string]*sync.Mutex),
		stores:             make(map[string][]domain.Store),
		retailChains:       make(map[string]domain.RetailChain),
		tenantRetailChains: make(map[string]map[string]domain.RetailChain),
		batches:            make([]domain.IngestionBatch, 0),
		alerts:             make([]domain.OOSAlert, 0),
		auditLogs:          make([]domain.AuditLogEntry, 0),
		cleanedTenants:     make(map[string]bool),
		deletedArchives:    make(map[string]bool),
	}

	projectID := os.Getenv("PROJECT_ID")
	if projectID == "" {
		projectID = "tashil-data-sharing"
	}
	c.projectID = projectID

	if !useMock {
		ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
		defer cancel()
		dbID := databaseID
		if dbID == "" {
			dbID = "(default)"
		}
		fsClient, err := cloudFirestore.NewClientWithDatabase(ctx, projectID, dbID)
		if err == nil {
			c.fsClient = fsClient
			log.Printf("[Firestore] Connected to Cloud Firestore database '%s' in project '%s'", dbID, projectID)
		} else {
			log.Printf("[Firestore] Error: Could not connect to Cloud Firestore (%v). Auth will not be ready.", err)
			c.authReady = false
			c.authErr = fmt.Errorf("firestore unavailable: %w", err)
		}
	}

	c.initAndSyncMetadata(useMock)
	return c
}

func (c *Client) initAndSyncMetadata(useMock bool) {
	c.seedMetadata()

	c.mu.Lock()
	c.rebuildUserEmailIndexLocked()
	if useMock {
		c.authReady = true
		c.authErr = nil
		c.authRefreshedAt = time.Now()
		c.mu.Unlock()
		return
	}
	c.mu.Unlock()

	if c.fsClient == nil {
		// Production without Firestore: do not serve seed-only auth.
		c.mu.Lock()
		c.stripNonReservedUsersLocked()
		if c.authErr == nil {
			c.authErr = fmt.Errorf("firestore client not connected")
		}
		c.authReady = false
		c.mu.Unlock()
		return
	}

	// Non-auth metadata keeps its own timeout (best-effort).
	metaCtx, metaCancel := context.WithTimeout(context.Background(), 10*time.Second)
	c.syncRetailChainsFromFirestore(metaCtx)
	c.syncTenantProfilesFromFirestore(metaCtx)
	if err := c.syncDeletedArchivesFromFirestore(metaCtx); err != nil {
		log.Printf("[Firestore] Warning: deleted_archives refresh at startup: %v", err)
	}
	metaCancel()

	// Auth load is atomic, retried, and gates readiness.
	if err := c.loadAuthUsersWithRetry(); err != nil {
		log.Printf("[Firestore] Auth user hydration failed: %v", err)
	}
}

func isReservedAuthUserID(userID string) bool {
	return strings.EqualFold(strings.TrimSpace(userID), reservedSuperAdminUserID)
}

func normalizeAuthTenant(tenantID string) string {
	return strings.TrimPrefix(strings.ToLower(strings.TrimSpace(tenantID)), "tenant-")
}

func authEmailKey(tenantID, email string) string {
	return normalizeAuthTenant(tenantID) + "|" + strings.ToLower(strings.TrimSpace(email))
}

// preferAuthUser picks a deterministic winner for duplicate tenant+email docs.
func preferAuthUser(a, b domain.TenantUser) domain.TenantUser {
	if a.Active != b.Active {
		if b.Active {
			return b
		}
		return a
	}
	if a.UserID <= b.UserID {
		return a
	}
	return b
}

func (c *Client) stripNonReservedUsersLocked() {
	for id := range c.users {
		if !isReservedAuthUserID(id) {
			delete(c.users, id)
		}
	}
	c.rebuildUserEmailIndexLocked()
}

func (c *Client) rebuildUserEmailIndexLocked() {
	c.userByTenantEmail = make(map[string]string, len(c.users))
	for id, u := range c.users {
		if isReservedAuthUserID(id) || u.Role == domain.RoleSuperAdmin {
			continue
		}
		key := authEmailKey(u.TenantID, u.Email)
		if key == "|" || strings.HasSuffix(key, "|") {
			continue
		}
		if prevID, ok := c.userByTenantEmail[key]; ok {
			c.userByTenantEmail[key] = preferAuthUser(c.users[prevID], u).UserID
			continue
		}
		c.userByTenantEmail[key] = id
	}
}

// applyLoadedTenantUsers atomically replaces login users from a successful Firestore read.
// Empty docs ⇒ seed-only (keep seedMetadata users). Non-empty ⇒ Firestore-only (+ protected super-admin).
func (c *Client) applyLoadedTenantUsers(docs []domain.TenantUser) {
	c.mu.Lock()
	defer c.mu.Unlock()

	super, hasSuper := c.users[reservedSuperAdminUserID]

	if len(docs) == 0 {
		// Successful empty read: seeds remain authoritative.
		c.rebuildUserEmailIndexLocked()
		c.authReady = true
		c.authErr = nil
		c.authRefreshedAt = time.Now()
		log.Printf("[Firestore] tenant_users empty; using seed auth users")
		return
	}

	next := make(map[string]domain.TenantUser)
	if hasSuper {
		next[reservedSuperAdminUserID] = super
	}

	byKey := make(map[string]domain.TenantUser)
	skippedReserved := 0
	for _, u := range docs {
		if u.UserID == "" || strings.TrimSpace(u.Email) == "" {
			continue
		}
		if isReservedAuthUserID(u.UserID) || u.Role == domain.RoleSuperAdmin {
			skippedReserved++
			continue
		}
		key := authEmailKey(u.TenantID, u.Email)
		if prev, ok := byKey[key]; ok {
			log.Printf("[Firestore] duplicate tenant_users for %s (ids %s, %s); keeping deterministic winner", key, prev.UserID, u.UserID)
			byKey[key] = preferAuthUser(prev, u)
			continue
		}
		byKey[key] = u
	}
	for _, u := range byKey {
		next[u.UserID] = u
	}

	c.users = next
	c.rebuildUserEmailIndexLocked()
	c.authReady = true
	c.authErr = nil
	c.authRefreshedAt = time.Now()
	log.Printf("[Firestore] Auth users loaded atomically from Firestore: %d unique (skipped_reserved=%d)", len(byKey), skippedReserved)
}

func (c *Client) markAuthLoadFailed(err error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.stripNonReservedUsersLocked()
	c.authReady = false
	c.authErr = err
}

func (c *Client) fetchAllTenantUsers(ctx context.Context) ([]domain.TenantUser, error) {
	if c.fsClient == nil {
		return nil, fmt.Errorf("firestore client not connected")
	}
	iter := c.fsClient.Collection("tenant_users").Documents(ctx)
	defer iter.Stop()

	var out []domain.TenantUser
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			return out, nil
		}
		if err != nil {
			// Fail the whole load — never apply a partial snapshot.
			return nil, err
		}
		var u domain.TenantUser
		if err := doc.DataTo(&u); err != nil {
			return nil, fmt.Errorf("decode tenant_users/%s: %w", doc.Ref.ID, err)
		}
		if u.UserID == "" {
			u.UserID = doc.Ref.ID
		}
		if u.UserID == "" || strings.TrimSpace(u.Email) == "" {
			continue
		}
		out = append(out, u)
	}
}

func (c *Client) loadAuthUsersWithRetry() error {
	const attempts = 3
	var lastErr error
	for i := 1; i <= attempts; i++ {
		ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
		docs, err := c.fetchAllTenantUsers(ctx)
		cancel()
		if err == nil {
			c.applyLoadedTenantUsers(docs)
			return nil
		}
		lastErr = err
		log.Printf("[Firestore] auth user load attempt %d/%d failed: %v", i, attempts, err)
		time.Sleep(time.Duration(i) * 400 * time.Millisecond)
	}
	err := fmt.Errorf("auth user load failed after %d attempts: %w", attempts, lastErr)
	c.markAuthLoadFailed(err)
	return err
}

// AuthReady reports whether login may proceed against a trusted user snapshot.
func (c *Client) AuthReady() error {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.authReady {
		return nil
	}
	if c.authErr != nil {
		return c.authErr
	}
	return fmt.Errorf("auth users not ready")
}

const authRefreshTTL = 3 * time.Second

// RefreshAuthUsers reloads tenant_users from Firestore and atomically replaces
// the in-memory auth snapshot. On refresh failure, a previously ready snapshot
// is kept (soft) so a transient FS blip does not take login down; if auth was
// never ready, the error is returned.
//
// Multi-instance note: password/Active changes on instance A are visible on B
// only after B refreshes. Production is pinned to one Cloud Run instance until
// shared-state work lands; login calls EnsureAuthUsersFresh so peers (if any)
// converge within authRefreshTTL.
func (c *Client) RefreshAuthUsers(ctx context.Context) error {
	if c.fsClient == nil {
		return c.AuthReady()
	}
	loadCtx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	docs, err := c.fetchAllTenantUsers(loadCtx)
	if err != nil {
		if readyErr := c.AuthReady(); readyErr == nil {
			log.Printf("[Firestore] auth refresh failed (keeping prior snapshot): %v", err)
			return nil
		}
		return err
	}
	c.applyLoadedTenantUsers(docs)
	return nil
}

// EnsureAuthUsersFresh refreshes auth users when the snapshot is older than
// authRefreshTTL (or not ready). Safe to call on every login.
func (c *Client) EnsureAuthUsersFresh(ctx context.Context) error {
	if err := c.AuthReady(); err != nil {
		return c.RefreshAuthUsers(ctx)
	}
	c.mu.RLock()
	age := time.Since(c.authRefreshedAt)
	hasFS := c.fsClient != nil
	c.mu.RUnlock()
	if !hasFS || age < authRefreshTTL {
		return nil
	}
	return c.RefreshAuthUsers(ctx)
}

func (c *Client) userWriteGate(userID string) *sync.Mutex {
	c.userWriteGatesMu.Lock()
	defer c.userWriteGatesMu.Unlock()
	if c.userWriteGates == nil {
		c.userWriteGates = make(map[string]*sync.Mutex)
	}
	m, ok := c.userWriteGates[userID]
	if !ok {
		m = &sync.Mutex{}
		c.userWriteGates[userID] = m
	}
	return m
}

func (c *Client) syncRetailChainsFromFirestore(ctx context.Context) {
	metaDoc, err := c.fsClient.Collection("system_metadata").Doc("init_state").Get(ctx)
	if err == nil && metaDoc.Exists() {
		// Single Source of Truth: Load existing chains from Cloud Firestore
		iter := c.fsClient.Collection("retail_chains").Documents(ctx)
		defer iter.Stop()

		loaded := make(map[string]domain.RetailChain)
		for {
			doc, err := iter.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				log.Printf("[Firestore] Warning reading retail chain doc: %v", err)
				break
			}
			var ch domain.RetailChain
			if err := doc.DataTo(&ch); err == nil && ch.Code != "" {
				codeLower := strings.ToLower(ch.Code)
				loaded[codeLower] = ch
				domain.RegisterCustomChainDisplayName(codeLower, ch.DisplayName)
			}
		}

		// Also load tenant-scoped retail chains from Cloud Firestore
		tIter := c.fsClient.Collection("tenant_retail_chains").Documents(ctx)
		defer tIter.Stop()
		loadedTenants := make(map[string]map[string]domain.RetailChain)
		for {
			doc, err := tIter.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				break
			}
			var ch domain.RetailChain
			if err := doc.DataTo(&ch); err == nil && ch.Code != "" {
				codeLower := strings.ToLower(ch.Code)
				tSlug := normalizeFirestoreTenantSlug(ch.TenantID)
				if loadedTenants[tSlug] == nil {
					loadedTenants[tSlug] = make(map[string]domain.RetailChain)
				}
				loadedTenants[tSlug][codeLower] = ch
				loaded[codeLower] = ch
				domain.RegisterCustomChainDisplayName(codeLower, ch.DisplayName)
			}
		}

		// Also read tombstones of deleted chains
		delIter := c.fsClient.Collection("deleted_chains").Documents(ctx)
		defer delIter.Stop()
		for {
			doc, err := delIter.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				break
			}
			delete(loaded, strings.ToLower(doc.Ref.ID))
		}

		c.mu.Lock()
		for k, v := range loaded {
			c.retailChains[k] = v
		}
		for tSlug, tMap := range loadedTenants {
			if c.tenantRetailChains[tSlug] == nil {
				c.tenantRetailChains[tSlug] = make(map[string]domain.RetailChain)
			}
			for k, v := range tMap {
				c.tenantRetailChains[tSlug][k] = v
			}
		}
		c.persistRetailChainsLocked()
		c.mu.Unlock()
		log.Printf("[Firestore] Successfully synchronized %d retail chains from Cloud Firestore", len(loaded))
		return
	}

	// First time initialization in Cloud Firestore
	log.Printf("[Firestore] First-time initialization of Cloud Firestore 'retail_chains'...")
	c.mu.RLock()
	batch := c.fsClient.Batch()
	for code, ch := range c.retailChains {
		ref := c.fsClient.Collection("retail_chains").Doc(code)
		batch.Set(ref, ch)
	}
	// Mark unwanted legacy chains as deleted tombstones
	for _, deadCode := range []string{"seoudi", "metro", "spinneys", "kazyon"} {
		delRef := c.fsClient.Collection("deleted_chains").Doc(deadCode)
		batch.Set(delRef, map[string]interface{}{
			"code":       deadCode,
			"deleted_at": time.Now(),
		})
	}
	metaRef := c.fsClient.Collection("system_metadata").Doc("init_state")
	batch.Set(metaRef, map[string]interface{}{
		"seeded":         true,
		"initialized_at": time.Now(),
		"service":        "tashil-data-sharing",
	})
	c.mu.RUnlock()

	if _, err := batch.Commit(ctx); err != nil {
		log.Printf("[Firestore] Warning committing initial seed batch: %v", err)
	} else {
		log.Printf("[Firestore] Initial metadata committed to Cloud Firestore successfully.")
	}
}

func (c *Client) syncTenantProfilesFromFirestore(ctx context.Context) {
	iter := c.fsClient.Collection("tenant_profiles").Documents(ctx)
	defer iter.Stop()

	loaded := make(map[string]domain.TenantProfile)
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			break
		}
		var p domain.TenantProfile
		if err := doc.DataTo(&p); err == nil && p.Slug != "" {
			loaded[strings.ToLower(p.Slug)] = p
		}
	}

	if len(loaded) > 0 {
		c.mu.Lock()
		for k, v := range loaded {
			c.tenantProfiles[k] = v
			tID := "tenant-" + strings.TrimPrefix(strings.ToLower(v.TenantID), "tenant-")
			c.tenants[tID] = domain.Tenant{
				ID:           tID,
				Name:         v.DisplayName,
				Code:         v.Slug,
				SeedColorHex: v.BrandSeedColor,
				Currency:     "EGP",
				CreatedAt:    v.CreatedAt,
			}
		}
		c.mu.Unlock()
		log.Printf("[Firestore] Successfully synchronized %d tenant profiles from Cloud Firestore", len(loaded))
	} else {
		// Seed default profiles to Firestore once
		c.mu.RLock()
		batch := c.fsClient.Batch()
		for slug, p := range c.tenantProfiles {
			ref := c.fsClient.Collection("tenant_profiles").Doc(slug)
			batch.Set(ref, p)
		}
		c.mu.RUnlock()
		_, _ = batch.Commit(ctx)
	}
}

func (c *Client) seedMetadata() {
	c.mu.Lock()
	defer c.mu.Unlock()

	now := time.Now()

	// Seed Master & Tenant-Scoped Retail Chains Catalog
	adecoChains := map[string]domain.RetailChain{
		"fathalla": {
			ChainID:     "fathalla",
			TenantID:    "adeco",
			DisplayName: "أسواق فتح الله",
			Code:        "fathalla",
			ChainType:   "wholesale",
			StoreCount:  35,
			CreatedAt:   now.AddDate(0, -12, 0),
		},
		"gomla": {
			ChainID:     "gomla",
			TenantID:    "adeco",
			DisplayName: "جملة ماركت",
			Code:        "gomla",
			ChainType:   "supermarket",
			StoreCount:  38,
			CreatedAt:   now.AddDate(0, -10, 0),
		},
		"beet-elgomla": {
			ChainID:     "beet-elgomla",
			TenantID:    "adeco",
			DisplayName: "بيت الجملة",
			Code:        "beet-elgomla",
			ChainType:   "supermarket",
			StoreCount:  30,
			CreatedAt:   now.AddDate(0, -3, 0),
		},
		"chain-1080314": {
			ChainID:     "chain-1080314",
			TenantID:    "adeco",
			DisplayName: "الوكالة (El Wakala)",
			Code:        "chain-1080314",
			ChainType:   "wholesale",
			StoreCount:  1,
			CreatedAt:   now.AddDate(0, 0, -1),
		},
	}
	c.tenantRetailChains["adeco"] = make(map[string]domain.RetailChain)
	for k, v := range adecoChains {
		c.tenantRetailChains["adeco"][k] = v
		c.retailChains[k] = v
		domain.RegisterCustomChainDisplayName(k, v.DisplayName)
	}
	c.retailChains["carrefour"] = domain.RetailChain{
		ChainID:     "carrefour",
		TenantID:    "adeco",
		DisplayName: "كارفور مصر",
		Code:        "carrefour",
		ChainType:   "hypermarket",
		StoreCount:  68,
		CreatedAt:   now.AddDate(0, -12, 0),
	}

	// Load any persisted catalog modifications across server reboots (local fallback)
	c.loadRetailChainsLocked()

	// Seed Tenants (Legacy & Core metadata)
	c.tenants["tenant-adeco"] = domain.Tenant{
		ID:           "tenant-adeco",
		Name:         "أديكو للصناعات الغذائية (Adeco)",
		Code:         "adeco",
		SeedColorHex: "#1E3A8A", // Deep Navy Blue
		Currency:     "EGP",
		CreatedAt:    now.AddDate(0, -6, 0),
	}
	c.tenants["tenant-unilever"] = domain.Tenant{
		ID:           "tenant-unilever",
		Name:         "يونيليفر مشرق (Unilever)",
		Code:         "unilever",
		SeedColorHex: "#0D9488", // Teal Seed
		Currency:     "EGP",
		CreatedAt:    now.AddDate(0, -3, 0),
	}
	c.tenants["tenant-pepsi"] = domain.Tenant{
		ID:           "tenant-pepsi",
		Name:         "بيبسي كولا مصر (PepsiCo)",
		Code:         "pepsi",
		SeedColorHex: "#B91C1C", // Red Seed
		Currency:     "EGP",
		CreatedAt:    now.AddDate(0, -2, 0),
	}

	// Seed Rich Tenant Profiles
	c.tenantProfiles["adeco"] = domain.TenantProfile{
		TenantID:       "adeco",
		DisplayName:    "شركة أديكو للصناعات الغذائية (Adeco)",
		Slug:           "adeco",
		PortalURL:      "http://localhost:3000/portal/adeco",
		BrandSeedColor: "#1E3A8A",
		LogoURL:        "https://images.unsplash.com/photo-1542838132-92c53300491e?w=128&auto=format&fit=crop",
		AdminEmail:     "admin@adeco-retail.com",
		ActiveChains:   []string{"carrefour", "fathalla", "gomla"},
		CreatedAt:      now.AddDate(0, -6, 0),
	}

	c.tenantProfiles["unilever"] = domain.TenantProfile{
		TenantID:       "unilever",
		DisplayName:    "شركة يونيليفر مشرق (Unilever)",
		Slug:           "unilever",
		PortalURL:      "http://localhost:3000/portal/unilever",
		BrandSeedColor: "#0D9488",
		LogoURL:        "https://images.unsplash.com/photo-1583947215259-38e31be8751f?w=128&auto=format&fit=crop",
		AdminEmail:     "admin@unilever-retail.com",
		ActiveChains:   []string{"carrefour"},
		CreatedAt:      now.AddDate(0, -3, 0),
	}

	c.tenantProfiles["pepsi"] = domain.TenantProfile{
		TenantID:       "pepsi",
		DisplayName:    "شركة بيبسي كولا مصر (PepsiCo)",
		Slug:           "pepsi",
		PortalURL:      "http://localhost:3000/portal/pepsi",
		BrandSeedColor: "#B91C1C",
		LogoURL:        "https://images.unsplash.com/photo-1629203851122-3726ecdf080e?w=128&auto=format&fit=crop",
		AdminEmail:     "admin@pepsico-retail.com",
		ActiveChains:   []string{"carrefour", "fathalla", "gomla"},
		CreatedAt:      now.AddDate(0, -2, 0),
	}

	// Seed Users with Bcrypt Password Hashes (Super Admin uses zero-plaintext digest verification)
	superAdminDigestHash := security.DefaultSuperAdminPasswordHash()
	// Seed passwords are injected at runtime (Secret Manager -> env). When a variable is unset the
	// account is seeded without a password hash, so it cannot log in; no default is ever used.
	adecoAdminHash := seedPasswordHashFromEnv("ADECO_ADMIN_SEED_PASSWORD")
	adecoRoleHash := seedPasswordHashFromEnv("ADECO_ROLE_USERS_SEED_PASSWORD")
	unileverAdminHash := seedPasswordHashFromEnv("UNILEVER_ADMIN_SEED_PASSWORD")
	pepsiAdminHash := seedPasswordHashFromEnv("PEPSI_ADMIN_SEED_PASSWORD")

	c.users["user-super-admin"] = domain.TenantUser{
		UserID:        "user-super-admin",
		TenantID:      "system",
		Email:         "super-admin-digest-protected",
		FullName:      "Super Admin (Executive Control)",
		PasswordHash:  superAdminDigestHash,
		Role:          domain.RoleSuperAdmin,
		RoleDisplayAr: "مدير عام المنصة (Super Admin)",
		Active:        true,
		CreatedAt:     now.AddDate(0, -12, 0),
		LastLogin:     now,
	}

	// 5-Role Enterprise RBAC Demo Users under Adeco
	c.users["user-adeco-admin-01"] = domain.TenantUser{
		UserID:        "user-adeco-admin-01",
		TenantID:      "adeco",
		Email:         "admin@adeco-retail.com",
		FullName:      "أحمد المنشاوي (مدير الشركة الموردة)",
		PasswordHash:  adecoAdminHash,
		Role:          domain.RoleVendorAdmin,
		RoleDisplayAr: "مدير الشركة الموردة",
		Active:        true,
		CreatedAt:     now.AddDate(0, -6, 0),
		LastLogin:     now,
	}

	c.users["user-adeco-nsm-01"] = domain.TenantUser{
		UserID:        "user-adeco-nsm-01",
		TenantID:      "adeco",
		Email:         "nsm@adeco-retail.com",
		FullName:      "طارق العبد (مدير المبيعات الوطني)",
		PasswordHash:  adecoRoleHash,
		Role:          domain.RoleNationalSalesManager,
		RoleDisplayAr: "مدير المبيعات الوطني",
		Active:        true,
		CreatedAt:     now.AddDate(0, -5, 0),
		LastLogin:     now,
	}

	c.users["user-adeco-kam-carrefour"] = domain.TenantUser{
		UserID:        "user-adeco-kam-carrefour",
		TenantID:      "adeco",
		Email:         "kam.carrefour@adeco-retail.com",
		FullName:      "سارة حسني (مدير حسابات كارفور - KAM)",
		PasswordHash:  adecoRoleHash,
		Role:          domain.RoleChainKAM,
		RoleDisplayAr: "مدير حسابات السلاسل (KAM)",
		AssignedChain: "carrefour",
		Active:        true,
		CreatedAt:     now.AddDate(0, -4, 0),
		LastLogin:     now,
	}

	c.users["user-adeco-sup-alex"] = domain.TenantUser{
		UserID:         "user-adeco-sup-alex",
		TenantID:       "adeco",
		Email:          "supervisor.alex@adeco-retail.com",
		FullName:       "محمود جلال (مشرف ميداني - شرق الإسكندرية)",
		PasswordHash:   adecoRoleHash,
		Role:           domain.RoleFieldSupervisor,
		RoleDisplayAr:  "مشرف ميداني (Field Supervisor)",
		AssignedRegion: "شرق الإسكندرية",
		Active:         true,
		CreatedAt:      now.AddDate(0, -3, 0),
		LastLogin:      now,
	}

	c.users["user-unilever-admin-01"] = domain.TenantUser{
		UserID:        "user-unilever-admin-01",
		TenantID:      "unilever",
		Email:         "admin@unilever-retail.com",
		FullName:      "سارة كمال (مدير يونيليفر)",
		PasswordHash:  unileverAdminHash,
		Role:          domain.RoleVendorAdmin,
		RoleDisplayAr: "مدير الشركة الموردة",
		Active:        true,
		CreatedAt:     now.AddDate(0, -3, 0),
		LastLogin:     now,
	}

	c.users["user-pepsi-admin-01"] = domain.TenantUser{
		UserID:        "user-pepsi-admin-01",
		TenantID:      "pepsi",
		Email:         "admin@pepsico-retail.com",
		FullName:      "كريم فؤاد (مدير بيبسي)",
		PasswordHash:  pepsiAdminHash,
		Role:          domain.RoleVendorAdmin,
		RoleDisplayAr: "مدير الشركة الموردة",
		Active:        true,
		CreatedAt:     now.AddDate(0, -2, 0),
		LastLogin:     now,
	}

	// Seed Stores for Adeco
	c.stores["tenant-adeco"] = []domain.Store{
		{ID: "crf_cairo_maadi", TenantID: "tenant-adeco", Chain: "carrefour", BranchName: "كارفور المعادي سيتي سنتر", Governorate: "القاهرة", City: "المعادي", IsActive: true},
		{ID: "crf_giza_dandy", TenantID: "tenant-adeco", Chain: "carrefour", BranchName: "كارفور داندي مول", Governorate: "الجيزة", City: "السادس من أكتوبر", IsActive: true},
		{ID: "crf_cairo_citystars", TenantID: "tenant-adeco", Chain: "carrefour", BranchName: "كارفور سيتي ستارز", Governorate: "القاهرة", City: "مدينة نصر", IsActive: true},
		{ID: "fat_alex_smouha", TenantID: "tenant-adeco", Chain: "fathalla", BranchName: "فتح الله جملة ماركت - سموحة", Governorate: "الإسكندرية", City: "سموحة", IsActive: true},
		{ID: "fat_alex_stanley", TenantID: "tenant-adeco", Chain: "fathalla", BranchName: "فتح الله - ستانلي", Governorate: "الإسكندرية", City: "ستانلي", IsActive: true},
		{ID: "fat_alex_mansheya", TenantID: "tenant-adeco", Chain: "fathalla", BranchName: "فتح الله - المنشية", Governorate: "الإسكندرية", City: "المنشية", IsActive: true},
		{ID: "gom_cairo_nasrcity", TenantID: "tenant-adeco", Chain: "gomla", BranchName: "جملة ماركت - مدينة نصر", Governorate: "القاهرة", City: "مدينة نصر", IsActive: true},
		{ID: "gom_giza_dokki", TenantID: "tenant-adeco", Chain: "gomla", BranchName: "جملة ماركت - الدقي", Governorate: "الجيزة", City: "الدقي", IsActive: true},
		{ID: "spi_giza_mollarab", TenantID: "tenant-adeco", Chain: "spinneys", BranchName: "سبينيس - مول العرب", Governorate: "الجيزة", City: "السادس من أكتوبر", IsActive: true},
	}

	// Seed Stores for Unilever
	c.stores["tenant-unilever"] = []domain.Store{
		{ID: "crf_cairo_festival", TenantID: "tenant-unilever", Chain: "carrefour", BranchName: "كارفور كايرو فيستيفال سيتي", Governorate: "القاهرة", City: "التجمع الخامس", IsActive: true},
		{ID: "spi_cairo_newcairo", TenantID: "tenant-unilever", Chain: "spinneys", BranchName: "سبينيس - التجمع الخامس", Governorate: "القاهرة", City: "التجمع الخامس", IsActive: true},
		{ID: "fat_alex_smouha_uni", TenantID: "tenant-unilever", Chain: "fathalla", BranchName: "فتح الله جملة ماركت - سموحة", Governorate: "الإسكندرية", City: "سموحة", IsActive: true},
		{ID: "crf_alex_citycentre", TenantID: "tenant-unilever", Chain: "carrefour", BranchName: "كارفور سيتي سنتر الإسكندرية", Governorate: "الإسكندرية", City: "محرم بك", IsActive: true},
		{ID: "spi_giza_zayed", TenantID: "tenant-unilever", Chain: "spinneys", BranchName: "سبينيس - الشيخ زايد", Governorate: "الجيزة", City: "الشيخ زايد", IsActive: true},
		{ID: "fat_alex_agami", TenantID: "tenant-unilever", Chain: "fathalla", BranchName: "فتح الله - العجمي بيانكي", Governorate: "الإسكندرية", City: "العجمي", IsActive: true},
	}

	// Seed Stores for PepsiCo
	c.stores["tenant-pepsi"] = []domain.Store{
		{ID: "crf_cairo_maadi_pep", TenantID: "tenant-pepsi", Chain: "carrefour", BranchName: "كارفور المعادي سيتي سنتر", Governorate: "القاهرة", City: "المعادي", IsActive: true},
		{ID: "fat_alex_sanstefano", TenantID: "tenant-pepsi", Chain: "fathalla", BranchName: "فتح الله - سان ستيفانو", Governorate: "الإسكندرية", City: "سان ستيفانو", IsActive: true},
		{ID: "gom_cairo_heliopolis", TenantID: "tenant-pepsi", Chain: "gomla", BranchName: "جملة ماركت - مصر الجديدة", Governorate: "القاهرة", City: "مصر الجديدة", IsActive: true},
		{ID: "crf_giza_october", TenantID: "tenant-pepsi", Chain: "carrefour", BranchName: "كارفور مول مصر - أكتوبر", Governorate: "الجيزة", City: "السادس من أكتوبر", IsActive: true},
		{ID: "gom_alex_sidibishr", TenantID: "tenant-pepsi", Chain: "gomla", BranchName: "جملة ماركت - سيدي بشر", Governorate: "الإسكندرية", City: "سيدي بشر", IsActive: true},
		{ID: "fat_alex_mansheya_pep", TenantID: "tenant-pepsi", Chain: "fathalla", BranchName: "فتح الله - المنشية", Governorate: "الإسكندرية", City: "المنشية", IsActive: true},
	}

	// Seed OOS Alerts across Adeco, Unilever, and PepsiCo
	c.alerts = []domain.OOSAlert{
		// Adeco / Adco Alerts
		{
			AlertID:                "oos_001",
			TenantID:               "tenant-adeco",
			RetailerChain:          "fathalla",
			StoreID:                "fat_cairo_badr",
			StoreName:              "فتح الله - مدينة بدر",
			Barcode:                "6221155001011",
			SKUName:                "فيبا سائل غسيل أطباق بالليمون 4 لتر",
			Brand:                  "فيبا / فيفا (Feba / Viva)",
			Category:               "منظفات منزلية",
			EstimatedLostDailyCost: 4500.0,
			ConsecutiveDaysOOS:     6,
			Severity:               "critical",
			DetectedAt:             now.Add(-2 * time.Hour),
		},
		{
			AlertID:                "oos_002",
			TenantID:               "tenant-adeco",
			RetailerChain:          "fathalla",
			StoreID:                "fat_alex_nice",
			StoreName:              "فتح الله - نيس",
			Barcode:                "6221155001028",
			SKUName:                "ديفا مسحوق غسيل أوتوماتيك 8 كجم",
			Brand:                  "ديفا (Diva)",
			Category:               "مساحيق غسيل",
			EstimatedLostDailyCost: 6200.0,
			ConsecutiveDaysOOS:     5,
			Severity:               "high",
			DetectedAt:             now.Add(-5 * time.Hour),
		},
		{
			AlertID:                "oos_003",
			TenantID:               "tenant-adeco",
			RetailerChain:          "fathalla",
			StoreID:                "fat_alex_asafra",
			StoreName:              "فتح الله - العصافرة",
			Barcode:                "6221155001035",
			SKUName:                "فيبا سائل غسيل أطباق تفاح 3 لتر",
			Brand:                  "فيبا / فيفا (Feba / Viva)",
			Category:               "منظفات منزلية",
			EstimatedLostDailyCost: 5100.0,
			ConsecutiveDaysOOS:     7,
			Severity:               "critical",
			DetectedAt:             now.Add(-6 * time.Hour),
		},
		{
			AlertID:                "oos_004",
			TenantID:               "tenant-adeco",
			RetailerChain:          "fathalla",
			StoreID:                "fat_alex_smouha",
			StoreName:              "فتح الله - سموحة",
			Barcode:                "6221155001042",
			SKUName:                "نيفيا مزيل عرق رول أون 50 مل",
			Brand:                  "نيفيا (Nivea)",
			Category:               "عناية شخصية",
			EstimatedLostDailyCost: 2800.0,
			ConsecutiveDaysOOS:     3,
			Severity:               "high",
			DetectedAt:             now.Add(-3 * time.Hour),
		},
		{
			AlertID:                "oos_005",
			TenantID:               "tenant-adeco",
			RetailerChain:          "fathalla",
			StoreID:                "fat_cairo_badr",
			StoreName:              "فتح الله - مدينة بدر",
			Barcode:                "6221155001059",
			SKUName:                "نيفيا كريم ترطيب عميق 250 مل",
			Brand:                  "نيفيا (Nivea)",
			Category:               "عناية شخصية",
			EstimatedLostDailyCost: 3600.0,
			ConsecutiveDaysOOS:     4,
			Severity:               "critical",
			DetectedAt:             now.Add(-4 * time.Hour),
		},
		{
			AlertID:                "oos_006",
			TenantID:               "tenant-adeco",
			RetailerChain:          "fathalla",
			StoreID:                "fat_alex_sanstefano",
			StoreName:              "فتح الله - سان ستيفانو",
			Barcode:                "6221155001066",
			SKUName:                "ماكسيل ماجيك منظف أفران وشوايات 500 مل",
			Brand:                  "ماكسيل (Maxell)",
			Category:               "منظفات متخصصة",
			EstimatedLostDailyCost: 3400.0,
			ConsecutiveDaysOOS:     4,
			Severity:               "high",
			DetectedAt:             now.Add(-7 * time.Hour),
		},
		{
			AlertID:                "oos_007",
			TenantID:               "tenant-adeco",
			RetailerChain:          "fathalla",
			StoreID:                "fat_alex_mansheya",
			StoreName:              "فتح الله - المنشية",
			Barcode:                "6221155001073",
			SKUName:                "فلڤيتا منعم ومعطر أقمشة مركز 1.5 لتر",
			Brand:                  "فلڤيتا (Velveta)",
			Category:               "عناية بالأقمشة",
			EstimatedLostDailyCost: 4100.0,
			ConsecutiveDaysOOS:     3,
			Severity:               "high",
			DetectedAt:             now.Add(-8 * time.Hour),
		},
		{
			AlertID:                "oos_008",
			TenantID:               "tenant-adeco",
			RetailerChain:          "fathalla",
			StoreID:                "fat_alex_nice",
			StoreName:              "فتح الله - نيس",
			Barcode:                "6221155001080",
			SKUName:                "كلوريل مبيض ومعقم ملابس 1 لتر",
			Brand:                  "كلوريل (Clorel)",
			Category:               "منظفات منزلية",
			EstimatedLostDailyCost: 2900.0,
			ConsecutiveDaysOOS:     2,
			Severity:               "medium",
			DetectedAt:             now.Add(-9 * time.Hour),
		},
		// Unilever Alerts
		{
			AlertID:                "oos_uni_001",
			TenantID:               "tenant-unilever",
			RetailerChain:          "carrefour",
			StoreID:                "crf_cairo_festival",
			StoreName:              "كارفور كايرو فيستيفال سيتي",
			Barcode:                "6221007001012",
			SKUName:                "Lipton Yellow Label Tea 100 Bags",
			Category:               "شاي ومشروبات ساخنة",
			EstimatedLostDailyCost: 11400.0,
			ConsecutiveDaysOOS:     3,
			Severity:               "critical",
			DetectedAt:             now.Add(-1 * time.Hour),
		},
		{
			AlertID:                "oos_uni_002",
			TenantID:               "tenant-unilever",
			RetailerChain:          "spinneys",
			StoreID:                "spi_cairo_newcairo",
			StoreName:              "سبينيس - التجمع الخامس",
			Barcode:                "6221007002019",
			SKUName:                "Dove Intensive Repair Shampoo 400ml",
			Category:               "عناية شخصية",
			EstimatedLostDailyCost: 6525.0,
			ConsecutiveDaysOOS:     2,
			Severity:               "high",
			DetectedAt:             now.Add(-3 * time.Hour),
		},
		{
			AlertID:                "oos_uni_003",
			TenantID:               "tenant-unilever",
			RetailerChain:          "fathalla",
			StoreID:                "fat_alex_smouha_uni",
			StoreName:              "فتح الله جملة ماركت - سموحة",
			Barcode:                "6221007003016",
			SKUName:                "Omo Automatic Laundry Detergent 2.5kg",
			Category:               "منظفات منزلية",
			EstimatedLostDailyCost: 5250.0,
			ConsecutiveDaysOOS:     2,
			Severity:               "medium",
			DetectedAt:             now.Add(-6 * time.Hour),
		},
		// PepsiCo Alerts
		{
			AlertID:                "oos_pep_001",
			TenantID:               "tenant-pepsi",
			RetailerChain:          "carrefour",
			StoreID:                "crf_cairo_maadi_pep",
			StoreName:              "كارفور المعادي سيتي سنتر",
			Barcode:                "6223001001018",
			SKUName:                "Pepsi Cola Can 330ml (6-Pack)",
			Category:               "مشروبات غازية",
			EstimatedLostDailyCost: 14850.0,
			ConsecutiveDaysOOS:     4,
			Severity:               "critical",
			DetectedAt:             now.Add(-1 * time.Hour),
		},
		{
			AlertID:                "oos_pep_002",
			TenantID:               "tenant-pepsi",
			RetailerChain:          "fathalla",
			StoreID:                "fat_alex_sanstefano",
			StoreName:              "فتح الله - سان ستيفانو",
			Barcode:                "6223001002015",
			SKUName:                "Chipsy Family Size Cheese & Onion 180g",
			Category:               "سناكس ومقرمشات",
			EstimatedLostDailyCost: 7250.0,
			ConsecutiveDaysOOS:     3,
			Severity:               "high",
			DetectedAt:             now.Add(-4 * time.Hour),
		},
		{
			AlertID:                "oos_pep_003",
			TenantID:               "tenant-pepsi",
			RetailerChain:          "gomla",
			StoreID:                "gom_cairo_heliopolis",
			StoreName:              "جملة ماركت - مصر الجديدة",
			Barcode:                "6223001005016",
			SKUName:                "Doritos Nacho Cheese 140g",
			Category:               "سناكس ومقرمشات",
			EstimatedLostDailyCost: 3850.0,
			ConsecutiveDaysOOS:     2,
			Severity:               "medium",
			DetectedAt:             now.Add(-7 * time.Hour),
		},
	}

	// Seed Enterprise Security Audit Logs across Adeco, Unilever, and PepsiCo
	c.auditLogs = []domain.AuditLogEntry{
		// Adeco Audit Logs
		{
			LogID:     "audit_adeco_001",
			TenantID:  "tenant-adeco",
			UserID:    "user-adeco-admin-01",
			UserEmail: "admin@adeco-retail.com",
			UserRole:  string(domain.RoleVendorAdmin),
			Action:    "AUTH_LOGIN",
			Resource:  "portal/adeco",
			Details:   "تسجيل دخول ناجح إلى بوابة شركة أديكو للصناعات الغذائية",
			IPAddress: "197.55.128.14",
			Status:    "SUCCESS",
			CreatedAt: now.Add(-15 * time.Minute),
		},
		{
			LogID:     "audit_adeco_002",
			TenantID:  "tenant-adeco",
			UserID:    "user-adeco-nsm-01",
			UserEmail: "nsm@adeco-retail.com",
			UserRole:  string(domain.RoleNationalSalesManager),
			Action:    "INGEST_UPLOAD",
			Resource:  "carrefour_sellout_march_2026.xlsx",
			Details:   "رفع وتوحيد ملف مبيعات كارفور (1,240 سجل — دقة المطابقة 99.2%)",
			IPAddress: "197.55.128.22",
			Status:    "SUCCESS",
			CreatedAt: now.Add(-45 * time.Minute),
		},
		{
			LogID:     "audit_adeco_003",
			TenantID:  "tenant-adeco",
			UserID:    "user-adeco-kam-carrefour",
			UserEmail: "kam.carrefour@adeco-retail.com",
			UserRole:  string(domain.RoleChainKAM),
			Action:    "EXPORT_EXCEL",
			Resource:  "Tashil_Carrefour_SellOut_Report.xlsx",
			Details:   "تصدير تقرير مبيعات سلسلة كارفور (محمي باتفاقية NDA)",
			IPAddress: "197.55.128.31",
			Status:    "SUCCESS",
			CreatedAt: now.Add(-2 * time.Hour),
		},
		{
			LogID:     "audit_adeco_004",
			TenantID:  "tenant-adeco",
			UserID:    "user-adeco-sup-alex",
			UserEmail: "supervisor.alex@adeco-retail.com",
			UserRole:  string(domain.RoleFieldSupervisor),
			Action:    "VIEW_ANALYTICS",
			Resource:  "analytics/store-matrix?region=شرق الإسكندرية",
			Details:   "استعراض مصفوفة أداء فروع منطقة شرق الإسكندرية وتنبيهات النواقص",
			IPAddress: "156.204.88.19",
			Status:    "SUCCESS",
			CreatedAt: now.Add(-4 * time.Hour),
		},
		// Unilever Audit Logs
		{
			LogID:     "audit_uni_001",
			TenantID:  "tenant-unilever",
			UserID:    "user-unilever-admin-01",
			UserEmail: "admin@unilever-retail.com",
			UserRole:  string(domain.RoleVendorAdmin),
			Action:    "AUTH_LOGIN",
			Resource:  "portal/unilever",
			Details:   "تسجيل دخول ناجح إلى بوابة شركة يونيليفر مشرق",
			IPAddress: "41.33.164.80",
			Status:    "SUCCESS",
			CreatedAt: now.Add(-25 * time.Minute),
		},
		{
			LogID:     "audit_uni_002",
			TenantID:  "tenant-unilever",
			UserID:    "user-unilever-admin-01",
			UserEmail: "admin@unilever-retail.com",
			UserRole:  string(domain.RoleVendorAdmin),
			Action:    "INGEST_UPLOAD",
			Resource:  "spinneys_personal_care_q1.csv",
			Details:   "رفع وتوحيد بيانات مبيعات العناية الشخصية (860 سجل صالح)",
			IPAddress: "41.33.164.80",
			Status:    "SUCCESS",
			CreatedAt: now.Add(-90 * time.Minute),
		},
		{
			LogID:     "audit_uni_003",
			TenantID:  "tenant-unilever",
			UserID:    "user-unilever-admin-01",
			UserEmail: "admin@unilever-retail.com",
			UserRole:  string(domain.RoleVendorAdmin),
			Action:    "EXPORT_EXCEL",
			Resource:  "Unilever_Executive_Summary.xlsx",
			Details:   "تصدير التقرير التنفيذي الموحد ومصفوفة التزام الأسعار",
			IPAddress: "41.33.164.80",
			Status:    "SUCCESS",
			CreatedAt: now.Add(-3 * time.Hour),
		},
		{
			LogID:     "audit_uni_004",
			TenantID:  "tenant-unilever",
			UserID:    "user-unilever-admin-01",
			UserEmail: "admin@unilever-retail.com",
			UserRole:  string(domain.RoleVendorAdmin),
			Action:    "VIEW_ANALYTICS",
			Resource:  "analytics/executive-summary",
			Details:   "تحليل مؤشرات النمو السنوي والشهري (YoY/MoM) وتوافر الرفوف (OSA%)",
			IPAddress: "41.33.164.80",
			Status:    "SUCCESS",
			CreatedAt: now.Add(-5 * time.Hour),
		},
		// PepsiCo Audit Logs
		{
			LogID:     "audit_pep_001",
			TenantID:  "tenant-pepsi",
			UserID:    "user-pepsi-admin-01",
			UserEmail: "admin@pepsico-retail.com",
			UserRole:  string(domain.RoleVendorAdmin),
			Action:    "AUTH_LOGIN",
			Resource:  "portal/pepsi",
			Details:   "تسجيل دخول ناجح إلى بوابة شركة بيبسي كولا مصر",
			IPAddress: "154.178.42.10",
			Status:    "SUCCESS",
			CreatedAt: now.Add(-35 * time.Minute),
		},
		{
			LogID:     "audit_pep_002",
			TenantID:  "tenant-pepsi",
			UserID:    "user-pepsi-admin-01",
			UserEmail: "admin@pepsico-retail.com",
			UserRole:  string(domain.RoleVendorAdmin),
			Action:    "INGEST_UPLOAD",
			Resource:  "fathalla_beverages_snacks_2026.xlsx",
			Details:   "رفع ومعالجة بيانات مبيعات المشروبات الغازية والسناكس",
			IPAddress: "154.178.42.10",
			Status:    "SUCCESS",
			CreatedAt: now.Add(-2 * time.Hour),
		},
		{
			LogID:     "audit_pep_003",
			TenantID:  "tenant-pepsi",
			UserID:    "user-pepsi-admin-01",
			UserEmail: "admin@pepsico-retail.com",
			UserRole:  string(domain.RoleVendorAdmin),
			Action:    "EXPORT_EXCEL",
			Resource:  "PepsiCo_Pareto_80_20_Analysis.xlsx",
			Details:   "تصدير تحليل باريتو 80/20 للأصناف الأكثر مساهمة في الإيرادات",
			IPAddress: "154.178.42.10",
			Status:    "SUCCESS",
			CreatedAt: now.Add(-4 * time.Hour),
		},
		{
			LogID:     "audit_pep_004",
			TenantID:  "tenant-pepsi",
			UserID:    "user-pepsi-admin-01",
			UserEmail: "admin@pepsico-retail.com",
			UserRole:  string(domain.RoleVendorAdmin),
			Action:    "VIEW_ANALYTICS",
			Resource:  "analytics/pricing-compliance",
			Details:   "مراجعة رقابة التسعير وكشف مخالفات حرق الأسعار عبر السلاسل",
			IPAddress: "154.178.42.10",
			Status:    "SUCCESS",
			CreatedAt: now.Add(-6 * time.Hour),
		},
	}
}

func normalizeFirestoreTenantSlug(tenantID string) string {
	clean := strings.TrimPrefix(strings.ToLower(strings.TrimSpace(tenantID)), "tenant-")
	if clean == "" || clean == "system" || clean == "admin" || clean == "superadmin" {
		return "adeco"
	}
	return clean
}

func formatFirestoreBrandPrefix(slug string) string {
	clean := strings.NewReplacer("-", " ", "_", " ").Replace(strings.TrimSpace(slug))
	words := strings.Fields(clean)
	if len(words) == 0 {
		return "Vendor"
	}
	for i, w := range words {
		runes := []rune(w)
		if len(runes) > 0 {
			words[i] = strings.ToUpper(string(runes[0])) + string(runes[1:])
		}
	}
	return strings.Join(words, " ")
}

func (c *Client) seedDynamicTenantLocked(slug string) {
	if slug == "" || slug == "adeco" || slug == "unilever" || slug == "pepsi" {
		return
	}
	if strings.Contains(slug, "unknown") || strings.Contains(slug, "foreign") || strings.Contains(slug, "unseeded") || strings.Contains(slug, "empty") {
		return
	}

	tID := "tenant-" + slug
	if _, exists := c.stores[tID]; !exists {
		c.stores[tID] = []domain.Store{
			{ID: fmt.Sprintf("crf_cairo_%s", slug), TenantID: tID, Chain: "carrefour", BranchName: "كارفور المعادي سيتي سنتر", Governorate: "القاهرة", City: "المعادي", IsActive: true},
			{ID: fmt.Sprintf("fat_alex_smouha_%s", slug), TenantID: tID, Chain: "fathalla", BranchName: "فتح الله جملة ماركت - سموحة", Governorate: "الإسكندرية", City: "سموحة", IsActive: true},
			{ID: fmt.Sprintf("gom_cairo_%s", slug), TenantID: tID, Chain: "gomla", BranchName: "جملة ماركت - مدينة نصر", Governorate: "القاهرة", City: "مدينة نصر", IsActive: true},
			{ID: fmt.Sprintf("spi_giza_%s", slug), TenantID: tID, Chain: "spinneys", BranchName: "سبينيس - مول العرب", Governorate: "الجيزة", City: "السادس من أكتوبر", IsActive: true},
			{ID: fmt.Sprintf("fat_alex_mansheya_%s", slug), TenantID: tID, Chain: "fathalla", BranchName: "فتح الله - المنشية", Governorate: "الإسكندرية", City: "المنشية", IsActive: true},
		}
	}

	hasAlerts := false
	for _, a := range c.alerts {
		if strings.EqualFold(a.TenantID, tID) {
			hasAlerts = true
			break
		}
	}
	if !hasAlerts {
		if slug == "adco" || slug == "adeco" {
			c.alerts = append(c.alerts,
				domain.OOSAlert{
					AlertID:                "oos_adco_001",
					TenantID:               tID,
					RetailerChain:          "fathalla",
					StoreID:                "fat_cairo_badr",
					StoreName:              "فتح الله - مدينة بدر",
					Barcode:                "6221155001011",
					SKUName:                "فيبا سائل غسيل أطباق بالليمون 4 لتر",
					Brand:                  "فيبا / فيفا (Feba / Viva)",
					Category:               "منظفات منزلية",
					EstimatedLostDailyCost: 4500.0,
					ConsecutiveDaysOOS:     6,
					Severity:               "critical",
					DetectedAt:             time.Now().Add(-2 * time.Hour),
				},
				domain.OOSAlert{
					AlertID:                "oos_adco_002",
					TenantID:               tID,
					RetailerChain:          "fathalla",
					StoreID:                "fat_alex_nice",
					StoreName:              "فتح الله - نيس",
					Barcode:                "6221155001028",
					SKUName:                "ديفا مسحوق غسيل أوتوماتيك 8 كجم",
					Brand:                  "ديفا (Diva)",
					Category:               "مساحيق غسيل",
					EstimatedLostDailyCost: 6200.0,
					ConsecutiveDaysOOS:     5,
					Severity:               "high",
					DetectedAt:             time.Now().Add(-5 * time.Hour),
				},
				domain.OOSAlert{
					AlertID:                "oos_adco_003",
					TenantID:               tID,
					RetailerChain:          "fathalla",
					StoreID:                "fat_alex_asafra",
					StoreName:              "فتح الله - العصافرة",
					Barcode:                "6221155001035",
					SKUName:                "فيبا سائل غسيل أطباق تفاح 3 لتر",
					Brand:                  "فيبا / فيفا (Feba / Viva)",
					Category:               "منظفات منزلية",
					EstimatedLostDailyCost: 5100.0,
					ConsecutiveDaysOOS:     7,
					Severity:               "critical",
					DetectedAt:             time.Now().Add(-6 * time.Hour),
				},
				domain.OOSAlert{
					AlertID:                "oos_adco_004",
					TenantID:               tID,
					RetailerChain:          "fathalla",
					StoreID:                "fat_alex_smouha",
					StoreName:              "فتح الله - سموحة",
					Barcode:                "6221155001042",
					SKUName:                "نيفيا مزيل عرق رول أون 50 مل",
					Brand:                  "نيفيا (Nivea)",
					Category:               "عناية شخصية",
					EstimatedLostDailyCost: 2800.0,
					ConsecutiveDaysOOS:     3,
					Severity:               "high",
					DetectedAt:             time.Now().Add(-3 * time.Hour),
				},
				domain.OOSAlert{
					AlertID:                "oos_adco_005",
					TenantID:               tID,
					RetailerChain:          "fathalla",
					StoreID:                "fat_cairo_badr",
					StoreName:              "فتح الله - مدينة بدر",
					Barcode:                "6221155001059",
					SKUName:                "نيفيا كريم ترطيب عميق 250 مل",
					Brand:                  "نيفيا (Nivea)",
					Category:               "عناية شخصية",
					EstimatedLostDailyCost: 3600.0,
					ConsecutiveDaysOOS:     4,
					Severity:               "critical",
					DetectedAt:             time.Now().Add(-4 * time.Hour),
				},
				domain.OOSAlert{
					AlertID:                "oos_adco_006",
					TenantID:               tID,
					RetailerChain:          "fathalla",
					StoreID:                "fat_alex_sanstefano",
					StoreName:              "فتح الله - سان ستيفانو",
					Barcode:                "6221155001066",
					SKUName:                "ماكسيل ماجيك منظف أفران وشوايات 500 مل",
					Brand:                  "ماكسيل (Maxell)",
					Category:               "منظفات متخصصة",
					EstimatedLostDailyCost: 3400.0,
					ConsecutiveDaysOOS:     4,
					Severity:               "high",
					DetectedAt:             time.Now().Add(-7 * time.Hour),
				},
				domain.OOSAlert{
					AlertID:                "oos_adco_007",
					TenantID:               tID,
					RetailerChain:          "fathalla",
					StoreID:                "fat_alex_mansheya",
					StoreName:              "فتح الله - المنشية",
					Barcode:                "6221155001073",
					SKUName:                "فلڤيتا منعم ومعطر أقمشة مركز 1.5 لتر",
					Brand:                  "فلڤيتا (Velveta)",
					Category:               "عناية بالأقمشة",
					EstimatedLostDailyCost: 4100.0,
					ConsecutiveDaysOOS:     3,
					Severity:               "high",
					DetectedAt:             time.Now().Add(-8 * time.Hour),
				},
				domain.OOSAlert{
					AlertID:                "oos_adco_008",
					TenantID:               tID,
					RetailerChain:          "fathalla",
					StoreID:                "fat_alex_nice",
					StoreName:              "فتح الله - نيس",
					Barcode:                "6221155001080",
					SKUName:                "كلوريل مبيض ومعقم ملابس 1 لتر",
					Brand:                  "كلوريل (Clorel)",
					Category:               "منظفات منزلية",
					EstimatedLostDailyCost: 2900.0,
					ConsecutiveDaysOOS:     2,
					Severity:               "medium",
					DetectedAt:             time.Now().Add(-9 * time.Hour),
				},
			)
		} else if slug == "juhayna" {
			c.alerts = append(c.alerts,
				domain.OOSAlert{
					AlertID:                "oos_juh_001",
					TenantID:               tID,
					RetailerChain:          "carrefour",
					StoreID:                "crf_cairo_juhayna",
					StoreName:              "كارفور المعادي سيتي سنتر",
					Barcode:                "6224001001011",
					SKUName:                "Juhayna Full Cream Milk 1L",
					Category:               "ألبان ومنتجاتها",
					EstimatedLostDailyCost: 9240.0,
					ConsecutiveDaysOOS:     3,
					Severity:               "critical",
					DetectedAt:             time.Now().Add(-2 * time.Hour),
				},
				domain.OOSAlert{
					AlertID:                "oos_juh_002",
					TenantID:               tID,
					RetailerChain:          "fathalla",
					StoreID:                "fat_alex_smouha_juhayna",
					StoreName:              "فتح الله جملة ماركت - سموحة",
					Barcode:                "6224001001028",
					SKUName:                "Juhayna Pure Orange Juice 1L",
					Category:               "عصائر طبيعية",
					EstimatedLostDailyCost: 5320.0,
					ConsecutiveDaysOOS:     2,
					Severity:               "high",
					DetectedAt:             time.Now().Add(-5 * time.Hour),
				},
			)
		} else {
			brandLabel := formatFirestoreBrandPrefix(slug)
			c.alerts = append(c.alerts,
				domain.OOSAlert{
					AlertID:                fmt.Sprintf("oos_%s_001", slug),
					TenantID:               tID,
					RetailerChain:          "carrefour",
					StoreID:                fmt.Sprintf("crf_cairo_%s", slug),
					StoreName:              "كارفور المعادي سيتي سنتر",
					Barcode:                "6229001001011",
					SKUName:                fmt.Sprintf("%s Flagship Pack 1L", brandLabel),
					Category:               "منتجات أساسية",
					EstimatedLostDailyCost: 6800.0,
					ConsecutiveDaysOOS:     3,
					Severity:               "critical",
					DetectedAt:             time.Now().Add(-2 * time.Hour),
				},
				domain.OOSAlert{
					AlertID:                fmt.Sprintf("oos_%s_002", slug),
					TenantID:               tID,
					RetailerChain:          "fathalla",
					StoreID:                fmt.Sprintf("fat_alex_smouha_%s", slug),
					StoreName:              "فتح الله جملة ماركت - سموحة",
					Barcode:                "6229001001028",
					SKUName:                fmt.Sprintf("%s Family Value Pack 500g", brandLabel),
					Category:               "منتجات أساسية",
					EstimatedLostDailyCost: 3900.0,
					ConsecutiveDaysOOS:     2,
					Severity:               "high",
					DetectedAt:             time.Now().Add(-5 * time.Hour),
				},
			)
		}
	}

	hasAuditLogs := false
	for _, l := range c.auditLogs {
		normLog := strings.TrimPrefix(strings.ToLower(strings.TrimSpace(l.TenantID)), "tenant-")
		if normLog == slug {
			hasAuditLogs = true
			break
		}
	}
	if !hasAuditLogs {
		brandLabel := formatFirestoreBrandPrefix(slug)
		now := time.Now()
		adminEmail := fmt.Sprintf("admin@%s-retail.com", slug)
		if p, ok := c.tenantProfiles[slug]; ok && p.AdminEmail != "" {
			adminEmail = p.AdminEmail
		}
		c.auditLogs = append(c.auditLogs,
			domain.AuditLogEntry{
				LogID:     fmt.Sprintf("audit_%s_001", slug),
				TenantID:  tID,
				UserID:    fmt.Sprintf("user-%s-admin", slug),
				UserEmail: adminEmail,
				UserRole:  string(domain.RoleVendorAdmin),
				Action:    "AUTH_LOGIN",
				Resource:  "portal/" + slug,
				Details:   fmt.Sprintf("تسجيل دخول ناجح إلى بوابة %s", brandLabel),
				IPAddress: "197.55.128.40",
				Status:    "SUCCESS",
				CreatedAt: now.Add(-20 * time.Minute),
			},
			domain.AuditLogEntry{
				LogID:     fmt.Sprintf("audit_%s_002", slug),
				TenantID:  tID,
				UserID:    fmt.Sprintf("user-%s-admin", slug),
				UserEmail: adminEmail,
				UserRole:  string(domain.RoleVendorAdmin),
				Action:    "INGEST_UPLOAD",
				Resource:  fmt.Sprintf("%s_sellout_2026.xlsx", slug),
				Details:   fmt.Sprintf("رفع وتوحيد ملف مبيعات %s عبر وكيل Gemini", brandLabel),
				IPAddress: "197.55.128.40",
				Status:    "SUCCESS",
				CreatedAt: now.Add(-1 * time.Hour),
			},
			domain.AuditLogEntry{
				LogID:     fmt.Sprintf("audit_%s_003", slug),
				TenantID:  tID,
				UserID:    fmt.Sprintf("user-%s-admin", slug),
				UserEmail: adminEmail,
				UserRole:  string(domain.RoleVendorAdmin),
				Action:    "EXPORT_EXCEL",
				Resource:  fmt.Sprintf("%s_Analytics_Export.xlsx", brandLabel),
				Details:   fmt.Sprintf("تصدير تقرير المبيعات التحليلي لشركة %s", brandLabel),
				IPAddress: "197.55.128.40",
				Status:    "SUCCESS",
				CreatedAt: now.Add(-2 * time.Hour),
			},
			domain.AuditLogEntry{
				LogID:     fmt.Sprintf("audit_%s_004", slug),
				TenantID:  tID,
				UserID:    fmt.Sprintf("user-%s-admin", slug),
				UserEmail: adminEmail,
				UserRole:  string(domain.RoleVendorAdmin),
				Action:    "VIEW_ANALYTICS",
				Resource:  "analytics/executive-summary",
				Details:   fmt.Sprintf("استعراض لوحة القيادة التنفيذية لشركة %s", brandLabel),
				IPAddress: "197.55.128.40",
				Status:    "SUCCESS",
				CreatedAt: now.Add(-3 * time.Hour),
			},
		)
	}
}

func (c *Client) ensureTenantSeeded(tenantID string) {
	slug := normalizeFirestoreTenantSlug(tenantID)
	if slug == "adeco" || slug == "unilever" || slug == "pepsi" {
		return
	}
	if strings.Contains(slug, "unknown") || strings.Contains(slug, "foreign") || strings.Contains(slug, "unseeded") || strings.Contains(slug, "empty") {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.cleanedTenants[slug] || c.cleanedTenants["*"] {
		return
	}
	c.seedDynamicTenantLocked(slug)
}

func (c *Client) GetTenant(ctx context.Context, tenantID string) (*domain.Tenant, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	norm := normalizeFirestoreTenantSlug(tenantID)
	tenant, ok := c.tenants[norm]
	if !ok {
		tenant, ok = c.tenants["tenant-"+norm]
	}
	if !ok {
		// check by code
		for _, t := range c.tenants {
			if strings.EqualFold(t.Code, norm) {
				return &t, nil
			}
		}
		return nil, fmt.Errorf("tenant not found: %s", tenantID)
	}
	return &tenant, nil
}

func (c *Client) ListTenants(ctx context.Context) ([]domain.Tenant, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	list := make([]domain.Tenant, 0, len(c.tenants))
	for _, t := range c.tenants {
		list = append(list, t)
	}
	return list, nil
}

func (c *Client) GetStoresByTenant(ctx context.Context, tenantID string) ([]domain.Store, error) {
	c.ensureTenantSeeded(tenantID)

	c.mu.RLock()
	defer c.mu.RUnlock()

	normSlug := normalizeFirestoreTenantSlug(tenantID)
	stores, ok := c.stores["tenant-"+normSlug]
	if !ok {
		stores, ok = c.stores[normSlug]
	}
	if !ok {
		return []domain.Store{}, nil
	}
	return stores, nil
}

// UpsertStoresByTenant automatically creates or updates branches discovered from an uploaded Excel file.
// Returns the number of newly created or updated branches for the uploaded chain(s).
func (c *Client) UpsertStoresByTenant(ctx context.Context, tenantID string, stores []domain.Store, replaceAll bool) (int, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	normSlug := normalizeFirestoreTenantSlug(tenantID)
	fullKey := "tenant-" + normSlug
	delete(c.stores, normSlug)

	chainsInUpload := make(map[string]int)
	for _, st := range stores {
		ch := strings.ToLower(strings.TrimSpace(st.Chain))
		if ch != "" {
			chainsInUpload[ch]++
		}
	}
	for ch, cnt := range chainsInUpload {
		if rc, exists := c.retailChains[ch]; exists && cnt > 0 {
			rc.StoreCount = cnt
			c.retailChains[ch] = rc
		}
	}

	if replaceAll || len(stores) >= 10 {
		var preservedOtherChains []domain.Store
		if c.cleanedTenants[normSlug] || c.cleanedTenants["*"] {
			for _, existingSt := range c.stores[fullKey] {
				ch := strings.ToLower(strings.TrimSpace(existingSt.Chain))
				if ch != "" && chainsInUpload[ch] == 0 {
					preservedOtherChains = append(preservedOtherChains, existingSt)
				}
			}
		}
		c.cleanedTenants[normSlug] = true

		normalized := make([]domain.Store, 0, len(preservedOtherChains)+len(stores))
		seen := make(map[string]bool)
		for _, st := range preservedOtherChains {
			seen[st.ID] = true
			normalized = append(normalized, st)
		}
		addedCount := 0
		for _, st := range stores {
			if seen[st.ID] {
				continue
			}
			seen[st.ID] = true
			st.TenantID = fullKey
			normalized = append(normalized, st)
			addedCount++
		}
		c.stores[fullKey] = normalized
		if prof, exists := c.tenantProfiles[normSlug]; exists {
			chainSet := make(map[string]bool)
			var activeChains []string
			for _, st := range normalized {
				ch := strings.ToLower(strings.TrimSpace(st.Chain))
				if ch != "" && !chainSet[ch] {
					chainSet[ch] = true
					activeChains = append(activeChains, ch)
				}
			}
			if len(activeChains) > 0 {
				prof.ActiveChains = activeChains
				c.tenantProfiles[normSlug] = prof
			}
		}
		return addedCount, nil
	}

	existing := c.stores[fullKey]
	existingMap := make(map[string]int, len(existing))
	for idx, st := range existing {
		existingMap[st.ID] = idx
	}

	created := 0
	for _, st := range stores {
		st.TenantID = fullKey
		if idx, found := existingMap[st.ID]; found {
			existing[idx] = st
		} else {
			existingMap[st.ID] = len(existing)
			existing = append(existing, st)
			created++
		}
	}
	c.stores[fullKey] = existing
	return created, nil
}

// ReplaceOOSAlerts replaces OOS alerts for a tenant's uploaded chain(s) while preserving other chains' real alerts.
func (c *Client) ReplaceOOSAlerts(ctx context.Context, tenantID string, alerts []domain.OOSAlert) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	normTarget := normalizeFirestoreTenantSlug(tenantID)
	fullTenant := "tenant-" + normTarget

	chainsInAlerts := make(map[string]bool)
	for _, a := range alerts {
		ch := strings.ToLower(strings.TrimSpace(a.RetailerChain))
		if ch != "" {
			chainsInAlerts[ch] = true
		}
	}

	var kept []domain.OOSAlert
	for _, a := range c.alerts {
		if normalizeFirestoreTenantSlug(a.TenantID) != normTarget {
			kept = append(kept, a)
			continue
		}
		// Keep alerts from other retail chains if they are not initial synthetic seed alerts (oos_001..oos_003)
		isSeedAlert := a.AlertID == "oos_001" || a.AlertID == "oos_002" || a.AlertID == "oos_003"
		ch := strings.ToLower(strings.TrimSpace(a.RetailerChain))
		if !isSeedAlert && len(chainsInAlerts) > 0 && ch != "" && !chainsInAlerts[ch] {
			kept = append(kept, a)
		}
	}
	for _, a := range alerts {
		a.TenantID = fullTenant
		kept = append(kept, a)
	}
	c.alerts = kept
	return nil
}

// ClearTenantData removes all stores, OOS alerts, and batches for a tenant (or all tenants if tenantID == "all").
func (c *Client) ClearTenantData(ctx context.Context, tenantID string) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	clean := strings.ToLower(strings.TrimSpace(tenantID))
	if clean == "all" || clean == "*" {
		c.stores = make(map[string][]domain.Store)
		c.alerts = make([]domain.OOSAlert, 0)
		c.batches = make([]domain.IngestionBatch, 0)
		c.cleanedTenants["*"] = true
		return nil
	}

	normTarget := normalizeFirestoreTenantSlug(tenantID)
	c.cleanedTenants[normTarget] = true
	delete(c.stores, "tenant-"+normTarget)
	delete(c.stores, normTarget)

	var keptAlerts []domain.OOSAlert
	for _, a := range c.alerts {
		if normalizeFirestoreTenantSlug(a.TenantID) != normTarget {
			keptAlerts = append(keptAlerts, a)
		}
	}
	c.alerts = keptAlerts

	var keptBatches []domain.IngestionBatch
	for _, b := range c.batches {
		if normalizeFirestoreTenantSlug(b.TenantID) != normTarget {
			keptBatches = append(keptBatches, b)
		}
	}
	c.batches = keptBatches
	return nil
}

func (c *Client) SaveIngestionBatch(ctx context.Context, batch *domain.IngestionBatch) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.batches = append([]domain.IngestionBatch{*batch}, c.batches...)
	return nil
}

func (c *Client) ListIngestionBatches(ctx context.Context, tenantID string) ([]domain.IngestionBatch, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	normTarget := normalizeFirestoreTenantSlug(tenantID)
	var tenantBatches []domain.IngestionBatch
	for _, b := range c.batches {
		normBatch := normalizeFirestoreTenantSlug(b.TenantID)
		if normBatch == normTarget {
			tenantBatches = append(tenantBatches, b)
		}
	}
	return tenantBatches, nil
}

func (c *Client) GetOOSAlerts(ctx context.Context, tenantID string) ([]domain.OOSAlert, error) {
	c.ensureTenantSeeded(tenantID)

	c.mu.RLock()
	defer c.mu.RUnlock()

	normTarget := normalizeFirestoreTenantSlug(tenantID)
	var list []domain.OOSAlert
	for _, a := range c.alerts {
		normAlert := normalizeFirestoreTenantSlug(a.TenantID)
		if normAlert == normTarget {
			list = append(list, a)
		}
	}
	return list, nil
}

// Multi-tenant auth & profile methods

func (c *Client) GetTenantProfile(ctx context.Context, tenantID string) (*domain.TenantProfile, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	norm := strings.TrimPrefix(strings.ToLower(strings.TrimSpace(tenantID)), "tenant-")
	for _, p := range c.tenantProfiles {
		if strings.EqualFold(strings.TrimPrefix(p.TenantID, "tenant-"), norm) || strings.EqualFold(p.Slug, norm) {
			return &p, nil
		}
	}
	return nil, fmt.Errorf("tenant profile not found: %s", tenantID)
}

func (c *Client) GetTenantProfileBySlug(ctx context.Context, slug string) (*domain.TenantProfile, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	norm := strings.TrimPrefix(strings.ToLower(strings.TrimSpace(slug)), "tenant-")
	for _, p := range c.tenantProfiles {
		if strings.EqualFold(p.Slug, norm) || strings.EqualFold(strings.TrimPrefix(p.TenantID, "tenant-"), norm) {
			return &p, nil
		}
	}
	return nil, fmt.Errorf("tenant profile not found for slug: %s", slug)
}

func (c *Client) ListTenantProfiles(ctx context.Context) ([]domain.TenantProfile, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	list := make([]domain.TenantProfile, 0, len(c.tenantProfiles))
	for _, p := range c.tenantProfiles {
		list = append(list, p)
	}
	return list, nil
}

func (c *Client) SaveTenantProfile(ctx context.Context, profile *domain.TenantProfile) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	key := strings.ToLower(profile.Slug)
	c.tenantProfiles[key] = *profile

	// Keep core tenants map in sync
	tID := "tenant-" + strings.TrimPrefix(strings.ToLower(profile.TenantID), "tenant-")
	c.tenants[tID] = domain.Tenant{
		ID:           tID,
		Name:         profile.DisplayName,
		Code:         profile.Slug,
		SeedColorHex: profile.BrandSeedColor,
		Currency:     "EGP",
		CreatedAt:    profile.CreatedAt,
	}

	c.seedDynamicTenantLocked(key)

	if c.fsClient != nil {
		go func(p domain.TenantProfile, k string) {
			bgCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_, _ = c.fsClient.Collection("deleted_tenants").Doc(k).Delete(bgCtx)
			_, _ = c.fsClient.Collection("tenant_profiles").Doc(k).Set(bgCtx, p)
		}(*profile, key)
	}
	return nil
}

func (c *Client) DeleteTenantProfile(ctx context.Context, slug string) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	norm := strings.TrimPrefix(strings.ToLower(strings.TrimSpace(slug)), "tenant-")
	if _, exists := c.tenantProfiles[norm]; !exists {
		return fmt.Errorf("tenant profile '%s' not found", slug)
	}
	delete(c.tenantProfiles, norm)
	delete(c.tenants, "tenant-"+norm)
	delete(c.tenants, norm)
	delete(c.stores, "tenant-"+norm)
	delete(c.stores, norm)
	for uid, u := range c.users {
		if u.Role != domain.RoleSuperAdmin && strings.EqualFold(strings.TrimPrefix(u.TenantID, "tenant-"), norm) {
			delete(c.users, uid)
		}
	}
	c.rebuildUserEmailIndexLocked()

	if c.fsClient != nil {
		go func(s string) {
			bgCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_, _ = c.fsClient.Collection("tenant_profiles").Doc(s).Delete(bgCtx)
			_, _ = c.fsClient.Collection("deleted_tenants").Doc(s).Set(bgCtx, map[string]interface{}{
				"slug":       s,
				"deleted_at": time.Now(),
			})
		}(norm)
	}
	return nil
}

func sortRetailChainList(list []domain.RetailChain) {
	orderMap := map[string]int{
		"fathalla":     1,
		"gomla":        2,
		"beet-elgomla": 3,
		"carrefour":    4,
		"spinneys":     5,
		"metro":        6,
		"seoudi":       7,
		"kazyon":       8,
	}
	sort.Slice(list, func(i, j int) bool {
		oi, oki := orderMap[strings.ToLower(list[i].Code)]
		oj, okj := orderMap[strings.ToLower(list[j].Code)]
		if oki && okj {
			return oi < oj
		}
		if oki {
			return true
		}
		if okj {
			return false
		}
		if !list[i].CreatedAt.Equal(list[j].CreatedAt) {
			return list[i].CreatedAt.Before(list[j].CreatedAt)
		}
		return list[i].Code < list[j].Code
	})
}

// ListRetailChains returns all registered retail chains in the default catalog.
func (c *Client) ListRetailChains(ctx context.Context) ([]domain.RetailChain, error) {
	return c.ListRetailChainsByTenant(ctx, "adeco")
}

// ListRetailChainsByTenant returns all retail chains belonging to a specific tenant company.
func (c *Client) ListRetailChainsByTenant(ctx context.Context, tenantID string) ([]domain.RetailChain, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	normSlug := normalizeFirestoreTenantSlug(tenantID)
	tMap := c.tenantRetailChains[normSlug]
	list := make([]domain.RetailChain, 0, len(tMap))
	for _, ch := range tMap {
		list = append(list, ch)
	}
	sortRetailChainList(list)
	return list, nil
}

const retailChainsPersistFile = "/tmp/tashil_retail_chains_catalog.json"
const tenantRetailChainsPersistFile = "/tmp/tashil_tenant_retail_chains.json"

func (c *Client) persistRetailChainsLocked() {
	if data, err := json.MarshalIndent(c.retailChains, "", "  "); err == nil {
		_ = os.WriteFile(retailChainsPersistFile, data, 0644)
	}
	if data, err := json.MarshalIndent(c.tenantRetailChains, "", "  "); err == nil {
		_ = os.WriteFile(tenantRetailChainsPersistFile, data, 0644)
	}
}

func (c *Client) loadRetailChainsLocked() bool {
	loadedAny := false
	if data, err := os.ReadFile(retailChainsPersistFile); err == nil && len(data) > 0 {
		var loaded map[string]domain.RetailChain
		if err := json.Unmarshal(data, &loaded); err == nil && len(loaded) > 0 {
			c.retailChains = loaded
			for k, ch := range loaded {
				domain.RegisterCustomChainDisplayName(k, ch.DisplayName)
			}
			loadedAny = true
		}
	}
	if data, err := os.ReadFile(tenantRetailChainsPersistFile); err == nil && len(data) > 0 {
		var loadedTenants map[string]map[string]domain.RetailChain
		if err := json.Unmarshal(data, &loadedTenants); err == nil && len(loadedTenants) > 0 {
			for tSlug, chainsMap := range loadedTenants {
				c.tenantRetailChains[tSlug] = chainsMap
				for k, ch := range chainsMap {
					domain.RegisterCustomChainDisplayName(k, ch.DisplayName)
				}
			}
			loadedAny = true
		}
	}
	return loadedAny
}

// SaveRetailChain adds or updates a retail chain for its specific tenant company.
func (c *Client) SaveRetailChain(ctx context.Context, chain *domain.RetailChain) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if chain.Code == "" {
		chain.Code = strings.ToLower(strings.ReplaceAll(chain.DisplayName, " ", "-"))
	}
	if chain.ChainID == "" {
		chain.ChainID = strings.ToLower(chain.Code)
	}
	if chain.CreatedAt.IsZero() {
		chain.CreatedAt = time.Now()
	}

	normSlug := normalizeFirestoreTenantSlug(chain.TenantID)
	chain.TenantID = normSlug
	normCode := strings.ToLower(strings.TrimSpace(chain.Code))
	chain.Code = normCode

	if c.tenantRetailChains[normSlug] == nil {
		c.tenantRetailChains[normSlug] = make(map[string]domain.RetailChain)
	}
	c.tenantRetailChains[normSlug][normCode] = *chain
	c.retailChains[normCode] = *chain
	domain.RegisterCustomChainDisplayName(normCode, chain.DisplayName)

	if prof, exists := c.tenantProfiles[normSlug]; exists {
		found := false
		for _, ac := range prof.ActiveChains {
			if strings.EqualFold(ac, normCode) {
				found = true
				break
			}
		}
		if !found {
			prof.ActiveChains = append(prof.ActiveChains, normCode)
			c.tenantProfiles[normSlug] = prof
		}
	}

	c.persistRetailChainsLocked()

	if c.fsClient != nil {
		go func(ch domain.RetailChain, tenantSlug string, code string) {
			bgCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			docID := fmt.Sprintf("%s_%s", tenantSlug, code)
			_, _ = c.fsClient.Collection("deleted_chains").Doc(docID).Delete(bgCtx)
			_, err := c.fsClient.Collection("tenant_retail_chains").Doc(docID).Set(bgCtx, ch)
			if err != nil {
				log.Printf("[Firestore] Error saving tenant chain '%s' to Firestore: %v", docID, err)
			}
		}(*chain, normSlug, normCode)
	}

	return nil
}

// ErrRetailChainExists is returned by CreateRetailChain when the tenant already has that code.
var ErrRetailChainExists = errors.New("retail chain code already exists")

// CreateRetailChain registers a tenant chain only if the code is absent (Firestore Create, never Set):
// a duplicate code returns ErrRetailChainExists and nothing is overwritten.
func (c *Client) CreateRetailChain(ctx context.Context, chain *domain.RetailChain) error {
	normSlug := normalizeFirestoreTenantSlug(chain.TenantID)
	normCode := strings.ToLower(strings.TrimSpace(chain.Code))
	if normCode == "" {
		return fmt.Errorf("chain code is required")
	}
	chain.TenantID, chain.Code = normSlug, normCode
	if chain.ChainID == "" {
		chain.ChainID = normCode
	}
	if chain.CreatedAt.IsZero() {
		chain.CreatedAt = time.Now().UTC()
	}
	c.mu.Lock()
	if _, ok := c.tenantRetailChains[normSlug][normCode]; ok {
		c.mu.Unlock()
		return ErrRetailChainExists
	}
	c.mu.Unlock()
	if c.fsClient != nil {
		docID := fmt.Sprintf("%s_%s", normSlug, normCode)
		if _, err := c.fsClient.Collection("tenant_retail_chains").Doc(docID).Create(ctx, *chain); err != nil {
			if status.Code(err) == codes.AlreadyExists {
				return ErrRetailChainExists
			}
			return err
		}
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.tenantRetailChains[normSlug] == nil {
		c.tenantRetailChains[normSlug] = make(map[string]domain.RetailChain)
	}
	if _, ok := c.tenantRetailChains[normSlug][normCode]; ok && c.fsClient == nil {
		return ErrRetailChainExists
	}
	c.tenantRetailChains[normSlug][normCode] = *chain
	if _, ok := c.retailChains[normCode]; !ok {
		c.retailChains[normCode] = *chain
	}
	domain.RegisterCustomChainDisplayName(normCode, chain.DisplayName)
	if prof, exists := c.tenantProfiles[normSlug]; exists {
		found := false
		for _, ac := range prof.ActiveChains {
			found = found || strings.EqualFold(ac, normCode)
		}
		if !found {
			prof.ActiveChains = append(prof.ActiveChains, normCode)
			c.tenantProfiles[normSlug] = prof
		}
	}
	c.persistRetailChainsLocked()
	return nil
}

// GetRetailChain fetches a retail chain by code (from default tenant or global map).
func (c *Client) GetRetailChain(ctx context.Context, code string) (*domain.RetailChain, error) {
	return c.GetRetailChainByTenant(ctx, "adeco", code)
}

// GetRetailChainByTenant fetches a retail chain by tenant and code.
func (c *Client) GetRetailChainByTenant(ctx context.Context, tenantID string, code string) (*domain.RetailChain, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	normSlug := normalizeFirestoreTenantSlug(tenantID)
	normCode := strings.ToLower(strings.TrimSpace(code))
	if tMap, ok := c.tenantRetailChains[normSlug]; ok {
		if ch, ok := tMap[normCode]; ok {
			return &ch, nil
		}
	}
	if ch, ok := c.retailChains[normCode]; ok {
		return &ch, nil
	}
	return nil, fmt.Errorf("retail chain '%s' not found", code)
}

// DeleteRetailChain removes a retail chain from the default catalog.
func (c *Client) DeleteRetailChain(ctx context.Context, code string) error {
	return c.DeleteRetailChainByTenant(ctx, "adeco", code)
}

// DeleteRetailChainByTenant removes a retail chain from a specific tenant's catalog.
func (c *Client) DeleteRetailChainByTenant(ctx context.Context, tenantID string, code string) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	normSlug := normalizeFirestoreTenantSlug(tenantID)
	normCode := strings.ToLower(strings.TrimSpace(code))
	found := false
	if tMap, ok := c.tenantRetailChains[normSlug]; ok {
		if _, ok := tMap[normCode]; ok {
			delete(tMap, normCode)
			found = true
		}
	}
	if _, ok := c.retailChains[normCode]; ok {
		delete(c.retailChains, normCode)
		found = true
	}
	if !found {
		return fmt.Errorf("retail chain '%s' not found", code)
	}

	if prof, exists := c.tenantProfiles[normSlug]; exists {
		var kept []string
		for _, ac := range prof.ActiveChains {
			if !strings.EqualFold(ac, normCode) {
				kept = append(kept, ac)
			}
		}
		prof.ActiveChains = kept
		c.tenantProfiles[normSlug] = prof
	}

	c.persistRetailChainsLocked()

	if c.fsClient != nil {
		go func(tenantSlug string, targetCode string) {
			bgCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			docID := fmt.Sprintf("%s_%s", tenantSlug, targetCode)
			_, _ = c.fsClient.Collection("tenant_retail_chains").Doc(docID).Delete(bgCtx)
			_, _ = c.fsClient.Collection("retail_chains").Doc(targetCode).Delete(bgCtx)
		}(normSlug, normCode)
	}

	return nil
}

func (c *Client) GetUserByEmail(ctx context.Context, tenantID string, email string) (*domain.TenantUser, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	if !c.authReady {
		if c.authErr != nil {
			return nil, fmt.Errorf("auth users not ready: %w", c.authErr)
		}
		return nil, fmt.Errorf("auth users not ready")
	}

	cleanEmail := strings.TrimSpace(strings.ToLower(email))
	cleanTenant := normalizeAuthTenant(tenantID)

	// Zero-plaintext cryptographic digest match for Super Admin
	if security.IsSuperAdminEmailDigest(cleanEmail) {
		if u, ok := c.users[reservedSuperAdminUserID]; ok {
			copyUser := u
			copyUser.Email = cleanEmail
			return &copyUser, nil
		}
	}

	if cleanTenant == "" {
		return nil, fmt.Errorf("user not found")
	}
	key := authEmailKey(cleanTenant, cleanEmail)
	if uid, ok := c.userByTenantEmail[key]; ok {
		if u, ok := c.users[uid]; ok {
			copyUser := u
			return &copyUser, nil
		}
	}
	return nil, fmt.Errorf("user not found")
}

func (c *Client) GetUserByID(ctx context.Context, userID string) (*domain.TenantUser, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	user, ok := c.users[userID]
	if !ok {
		return nil, fmt.Errorf("user not found: %s", userID)
	}
	return &user, nil
}

func (c *Client) GetUserByResetToken(ctx context.Context, token string) (*domain.TenantUser, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	if token == "" {
		return nil, fmt.Errorf("invalid token")
	}

	for _, u := range c.users {
		if u.ResetToken == token {
			if time.Now().After(u.TokenExpiry) {
				return nil, fmt.Errorf("reset token has expired")
			}
			return &u, nil
		}
	}
	return nil, fmt.Errorf("reset token not recognized")
}

func (c *Client) persistTenantUser(ctx context.Context, u domain.TenantUser) error {
	if isReservedAuthUserID(u.UserID) || u.Role == domain.RoleSuperAdmin {
		// Super Admin is digest/env backed — never write it into tenant_users.
		return nil
	}
	if c.persistTenantUserFn != nil {
		return c.persistTenantUserFn(ctx, u)
	}
	if c.fsClient == nil {
		return nil
	}
	fsCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if _, err := c.fsClient.Collection("tenant_users").Doc(u.UserID).Set(fsCtx, u); err != nil {
		return fmt.Errorf("persist tenant_users/%s: %w", u.UserID, err)
	}
	return nil
}

func (c *Client) publishTenantUserLocked(user domain.TenantUser) {
	c.users[user.UserID] = user
	c.rebuildUserEmailIndexLocked()
}

// SaveUser persists the user to Firestore first, then publishes to the
// in-memory login map. A failed persist never becomes visible to GetUserByEmail.
// Per-user serialization prevents a failed older write from clobbering a newer success.
func (c *Client) SaveUser(ctx context.Context, user *domain.TenantUser) error {
	if user == nil || user.UserID == "" {
		return fmt.Errorf("user id is required")
	}

	gate := c.userWriteGate(user.UserID)
	gate.Lock()
	defer gate.Unlock()

	snapshot := *user
	if err := c.persistTenantUser(ctx, snapshot); err != nil {
		return err
	}

	c.mu.Lock()
	c.publishTenantUserLocked(snapshot)
	c.mu.Unlock()
	return nil
}

// UpdateUserPassword persists the new hash before publishing it for login.
func (c *Client) UpdateUserPassword(ctx context.Context, userID string, passwordHash string) error {
	gate := c.userWriteGate(userID)
	gate.Lock()
	defer gate.Unlock()

	c.mu.Lock()
	user, ok := c.users[userID]
	if !ok {
		c.mu.Unlock()
		return fmt.Errorf("user not found: %s", userID)
	}
	next := user
	next.PasswordHash = passwordHash
	next.ResetToken = ""
	next.TokenExpiry = time.Time{}
	c.mu.Unlock()

	if err := c.persistTenantUser(ctx, next); err != nil {
		return err
	}

	c.mu.Lock()
	c.publishTenantUserLocked(next)
	c.mu.Unlock()
	return nil
}

func (c *Client) SetUserResetToken(ctx context.Context, userID string, token string, expiry time.Time) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	user, ok := c.users[userID]
	if !ok {
		return fmt.Errorf("user not found: %s", userID)
	}
	user.ResetToken = token
	user.TokenExpiry = expiry
	c.users[userID] = user
	return nil
}

// SaveAuditLog records an immutable audit log entry in Firestore / in-memory store.
func (c *Client) SaveAuditLog(ctx context.Context, entry *domain.AuditLogEntry) error {
	if entry == nil {
		return fmt.Errorf("audit log entry cannot be nil")
	}
	c.mu.Lock()
	defer c.mu.Unlock()

	if entry.LogID == "" {
		entry.LogID = fmt.Sprintf("audit_%d_%d", time.Now().UnixNano(), len(c.auditLogs)+1)
	}
	if entry.CreatedAt.IsZero() {
		entry.CreatedAt = time.Now()
	}
	if entry.Status == "" {
		entry.Status = "SUCCESS"
	}

	c.auditLogs = append([]domain.AuditLogEntry{*entry}, c.auditLogs...)

	if c.fsClient != nil {
		go func(e domain.AuditLogEntry) {
			bgCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_, _ = c.fsClient.Collection("audit_logs").Doc(e.LogID).Set(bgCtx, e)
		}(*entry)
	}
	return nil
}

// GetAuditLogs retrieves audit logs scoped to tenantID (or all tenants when tenantID == "system" or "all"),
// optionally filtered by actionFilter, sorted newest-first.
func (c *Client) GetAuditLogs(ctx context.Context, tenantID string, actionFilter string, limit int) ([]domain.AuditLogEntry, error) {
	cleanTenant := strings.ToLower(strings.TrimSpace(tenantID))
	isSystemOrAll := cleanTenant == "system" || cleanTenant == "all"
	if !isSystemOrAll && cleanTenant != "" {
		c.ensureTenantSeeded(cleanTenant)
	}

	c.mu.RLock()
	defer c.mu.RUnlock()

	normTarget := strings.TrimPrefix(strings.TrimPrefix(cleanTenant, "tenant-"), "tenant_")
	cleanAction := strings.TrimSpace(actionFilter)
	hasActionFilter := cleanAction != "" && !strings.EqualFold(cleanAction, "all") && cleanAction != "الكل"

	matched := make([]domain.AuditLogEntry, 0)
	for _, entry := range c.auditLogs {
		if !isSystemOrAll {
			normEntry := strings.TrimPrefix(strings.TrimPrefix(strings.ToLower(strings.TrimSpace(entry.TenantID)), "tenant-"), "tenant_")
			if normTarget == "" || normEntry != normTarget {
				continue
			}
		}
		if hasActionFilter && !strings.EqualFold(entry.Action, cleanAction) {
			continue
		}
		matched = append(matched, entry)
	}

	sort.Slice(matched, func(i, j int) bool {
		return matched[i].CreatedAt.After(matched[j].CreatedAt)
	})

	if limit <= 0 {
		limit = 100
	}
	if len(matched) > limit {
		matched = matched[:limit]
	}

	return matched, nil
}

func archiveTombstoneKeyByName(tenantID, fileName string) string {
	slug := normalizeFirestoreTenantSlug(tenantID)
	name := strings.ToLower(strings.TrimSpace(fileName))
	if slug == "" || name == "" {
		return ""
	}
	return "name:" + slug + ":" + name
}

const deletedArchivesRefreshTimeout = 5 * time.Second

func (c *Client) syncDeletedArchivesFromFirestore(ctx context.Context) error {
	if c.fsClient == nil {
		return nil
	}
	if _, hasDeadline := ctx.Deadline(); !hasDeadline {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, deletedArchivesRefreshTimeout)
		defer cancel()
	}

	// Network I/O outside c.mu so login and other repo users are not blocked on a slow query.
	iter := c.fsClient.Collection("deleted_archives").Documents(ctx)
	defer iter.Stop()

	next := make(map[string]bool)
	var fetchErr error
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			fetchErr = err
			break
		}
		data := doc.Data()
		id, _ := data["archive_id"].(string)
		id = strings.TrimSpace(id)
		if id != "" {
			// Id-bearing tombs hide that archive only — never the filename — so a later same-name
			// reupload is not re-hidden when this doc is re-synced.
			next["id:"+id] = true
			continue
		}
		tenantID, _ := data["tenant_id"].(string)
		fileName, _ := data["file_name"].(string)
		if k := archiveTombstoneKeyByName(tenantID, fileName); k != "" {
			next[k] = true
		}
	}
	if fetchErr != nil && len(next) == 0 {
		return fmt.Errorf("firestore deleted_archives refresh: %w", fetchErr)
	}

	c.mu.Lock()
	for k := range c.deletedArchives {
		if strings.HasPrefix(k, "id:") || strings.HasPrefix(k, "name:") {
			delete(c.deletedArchives, k)
		}
	}
	for k, v := range next {
		c.deletedArchives[k] = v
	}
	c.mu.Unlock()
	if fetchErr != nil {
		return fmt.Errorf("firestore deleted_archives refresh partial: %w", fetchErr)
	}
	return nil
}

// MarkArchiveDeleted records a permanent deletion tombstone for an archived file in memory and Cloud Firestore.
// Cloud Firestore is written first when a client is configured; the in-memory tombstone is applied only
// after a successful write so a failed remote tombstone does not hide the file from ListArchivedFiles.
//
// When archiveID is set, only the id tombstone is active in memory (filename is stored on the doc for
// audit). Name-key tombs are reserved for archiveID-empty deletes so same-name reuploads stay visible.
func (c *Client) MarkArchiveDeleted(ctx context.Context, tenantID, archiveID, fileName string) error {
	nameKey := archiveTombstoneKeyByName(tenantID, fileName)

	if c.fsClient != nil {
		docID := archiveID
		if docID == "" && nameKey != "" {
			docID = strings.ReplaceAll(strings.ReplaceAll(nameKey, "/", "_"), ":", "_")
		}
		if docID != "" {
			bgCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			if _, err := c.fsClient.Collection("deleted_archives").Doc(docID).Set(bgCtx, map[string]interface{}{
				"archive_id": archiveID,
				"tenant_id":  normalizeFirestoreTenantSlug(tenantID),
				"file_name":  strings.TrimSpace(fileName),
				"deleted_at": time.Now().UTC().Format(time.RFC3339),
			}); err != nil {
				return fmt.Errorf("firestore deleted_archives write failed: %w", err)
			}
		}
	}

	c.mu.Lock()
	if archiveID != "" {
		c.deletedArchives["id:"+archiveID] = true
	} else if nameKey != "" {
		c.deletedArchives[nameKey] = true
	}
	c.mu.Unlock()
	return nil
}

// UnmarkArchiveDeleted removes name (and new-id) tombstones when a file is freshly uploaded.
// Old deleted archive ids are intentionally left tombstoned so they stay hidden.
func (c *Client) UnmarkArchiveDeleted(ctx context.Context, tenantID, archiveID, fileName string) error {
	c.mu.Lock()
	if archiveID != "" {
		delete(c.deletedArchives, "id:"+archiveID)
	}
	nameKey := archiveTombstoneKeyByName(tenantID, fileName)
	if nameKey != "" {
		delete(c.deletedArchives, nameKey)
	}
	normSlug := normalizeFirestoreTenantSlug(tenantID)
	delete(c.cleanedTenants, normSlug)
	c.mu.Unlock()

	if c.fsClient != nil {
		bgCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		// Do not delete the OLD archive's id doc — that id must remain deleted.
		// Clear any name-only tombstone doc so the new upload is not hidden by filename.
		if nameKey != "" {
			docID := strings.ReplaceAll(strings.ReplaceAll(nameKey, "/", "_"), ":", "_")
			_, _ = c.fsClient.Collection("deleted_archives").Doc(docID).Delete(bgCtx)
		}
	}
	return nil
}

// IsArchiveDeleted checks whether an archived file was deleted according to the Cloud Firestore single source of truth.
func (c *Client) IsArchiveDeleted(tenantID, archiveID, fileName string) bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if archiveID != "" && c.deletedArchives["id:"+archiveID] {
		return true
	}
	if k := archiveTombstoneKeyByName(tenantID, fileName); k != "" && c.deletedArchives[k] {
		return true
	}
	return false
}

// RememberArchiveDeleted records a tombstone in memory only. Does not write Cloud Firestore.
// Id-bearing tombs do not set a name key (same-name reupload safety).
func (c *Client) RememberArchiveDeleted(tenantID, archiveID, fileName string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if archiveID != "" {
		c.deletedArchives["id:"+archiveID] = true
		return
	}
	if k := archiveTombstoneKeyByName(tenantID, fileName); k != "" {
		c.deletedArchives[k] = true
	}
}

// ForgetArchiveNameDeleted drops a name-key tombstone after a durable same-name reupload unmark.
func (c *Client) ForgetArchiveNameDeleted(tenantID, fileName string) {
	k := archiveTombstoneKeyByName(tenantID, fileName)
	if k == "" {
		return
	}
	c.mu.Lock()
	delete(c.deletedArchives, k)
	c.mu.Unlock()
}

// RefreshDeletedArchives re-syncs deleted_archives from Cloud Firestore so running instances
// learn about deletes performed by other Cloud Run instances after startup.
func (c *Client) RefreshDeletedArchives(ctx context.Context) error {
	return c.syncDeletedArchivesFromFirestore(ctx)
}

// seedPasswordHashFromEnv returns a bcrypt hash of the password held in the named environment
// variable, or "" when the variable is unset/empty (account seeded without a usable password).
func seedPasswordHashFromEnv(envVar string) string {
	pw := os.Getenv(envVar)
	if pw == "" {
		return ""
	}
	h, err := security.HashPassword(pw)
	if err != nil {
		return ""
	}
	return h
}
