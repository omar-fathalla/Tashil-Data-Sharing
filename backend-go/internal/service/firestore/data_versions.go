package firestore

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const dataVersionsCollection = "data_versions"

// DataVersionStore is a tiny shared counter per (tenant, dataset kind). Every instance that changes
// durable data bumps it; other Cloud Run instances poll it and reload when it differs.
type DataVersionStore interface {
	GetDataVersion(ctx context.Context, tenantID, kind string) (string, error)
	BumpDataVersion(ctx context.Context, tenantID, kind string) (string, error)
}

var _ DataVersionStore = (*Client)(nil)

type dataVersionDoc struct {
	Version   string    `firestore:"version"`
	UpdatedAt time.Time `firestore:"updated_at"`
}

func dataVersionDocID(tenantID, kind string) string {
	return normalizeFirestoreTenantSlug(tenantID) + "__" + kind
}

// GetDataVersion returns "" when nothing was ever bumped.
func (c *Client) GetDataVersion(ctx context.Context, tenantID, kind string) (string, error) {
	id := dataVersionDocID(tenantID, kind)
	if c.fsClient != nil {
		snap, err := c.fsClient.Collection(dataVersionsCollection).Doc(id).Get(ctx)
		if err != nil {
			if status.Code(err) == codes.NotFound {
				return "", nil
			}
			return "", fmt.Errorf("firestore get data version: %w", err)
		}
		var d dataVersionDoc
		if err := snap.DataTo(&d); err != nil {
			return "", fmt.Errorf("decode data version: %w", err)
		}
		return d.Version, nil
	}
	c.dvMu.Lock()
	defer c.dvMu.Unlock()
	return c.dataVersions[id], nil
}

// BumpDataVersion stores a new unique version and returns it.
func (c *Client) BumpDataVersion(ctx context.Context, tenantID, kind string) (string, error) {
	id := dataVersionDocID(tenantID, kind)
	now := time.Now().UTC()
	v := strconv.FormatInt(now.UnixNano(), 10)
	if c.fsClient != nil {
		if _, err := c.fsClient.Collection(dataVersionsCollection).Doc(id).Set(ctx, dataVersionDoc{Version: v, UpdatedAt: now}); err != nil {
			return "", fmt.Errorf("firestore bump data version: %w", err)
		}
		return v, nil
	}
	c.dvMu.Lock()
	defer c.dvMu.Unlock()
	if c.dataVersions == nil {
		c.dataVersions = map[string]string{}
	}
	c.dataVersions[id] = v
	return v, nil
}
