package bqsink

import (
	"strings"
	"testing"
)

func TestArchiveSQLIsTenantScoped(t *testing.T) {
	for _, sql := range []string{DeleteArchiveSQL("`p.d.t`"), DeleteOrphansSQL("`p.d.t`"), ArchiveRowCountsSQL("`p.d.t`")} {
		if !strings.Contains(sql, "tenant_id = @tenant_id") {
			t.Fatalf("not tenant scoped: %s", sql)
		}
	}
	if !strings.Contains(DeleteArchiveSQL("`t`"), "archive_id = @archive_id") {
		t.Fatal("archive delete must key on archive_id")
	}
	if !strings.Contains(DeleteOrphansSQL("`t`"), "NOT IN UNNEST(@live_ids)") {
		t.Fatal("orphans must be relative to live archive ids")
	}
}

func TestReadViewsResolveOverlap(t *testing.T) {
	so := SellOutReadSQL("`t`")
	for _, want := range []string{"write_mode", "ARRAY_AGG", "QUALIFY ROW_NUMBER() OVER (PARTITION BY", "tenant_id = @tenant_id"} {
		if !strings.Contains(so, want) {
			t.Fatalf("sell-out view missing %q: %s", want, so)
		}
	}
	si := SellInReadSQL("`t`")
	if !strings.Contains(si, "t.batch_id = win.wb") || !strings.Contains(si, "tenant_id = @tenant_id") {
		t.Fatalf("sell-in view must serve the latest batch per chain/month: %s", si)
	}
}
