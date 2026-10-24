package handlers

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"strings"
	"testing"
)

// Test-only credentials. These are NOT real passwords; they exist solely to exercise the login flow.
const (
	testSuperAdminEmail    = "superadmin@test.invalid"
	testSuperAdminPassword = "test-only-superadmin-pw"
	testSuperAdminSalt     = "test-only-salt"
	testAdecoAdminPassword = "test-only-adeco-admin-pw"
	testAdecoRolePassword  = "test-only-adeco-role-pw"
)

func testDigest(salt, v string) string {
	sum := sha256.Sum256([]byte(salt + v))
	return hex.EncodeToString(sum[:])
}

func TestMain(m *testing.M) {
	os.Setenv("SUPERADMIN_SALT", testSuperAdminSalt)
	os.Setenv("SUPERADMIN_EMAIL_DIGEST", testDigest(testSuperAdminSalt, strings.ToLower(testSuperAdminEmail)))
	os.Setenv("SUPERADMIN_PASS_DIGEST", testDigest(testSuperAdminSalt, testSuperAdminPassword))
	os.Setenv("ADECO_ADMIN_SEED_PASSWORD", testAdecoAdminPassword)
	os.Setenv("ADECO_ROLE_USERS_SEED_PASSWORD", testAdecoRolePassword)
	os.Setenv("UNILEVER_ADMIN_SEED_PASSWORD", "test-only-unilever-pw")
	os.Setenv("PEPSI_ADMIN_SEED_PASSWORD", "test-only-pepsi-pw")
	os.Exit(m.Run())
}
