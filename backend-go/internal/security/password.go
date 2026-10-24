package security

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"fmt"
	"math/big"
	"os"
	"strings"

	"golang.org/x/crypto/bcrypt"
)

// Super Admin identity is verified against salted SHA-256 digests supplied at runtime through
// environment variables (populated from Secret Manager in production). No credential material,
// salt, or digest is compiled into the binary. When the variables are unset, Super Admin login is disabled.
//
//   SUPERADMIN_SALT          domain-separation salt
//   SUPERADMIN_EMAIL_DIGEST  hex SHA-256 of (salt + lower(trim(email)))
//   SUPERADMIN_PASS_DIGEST   hex SHA-256 of (salt + password)
func superAdminSalt() string        { return os.Getenv("SUPERADMIN_SALT") }
func superAdminEmailDigest() string { return strings.ToLower(strings.TrimSpace(os.Getenv("SUPERADMIN_EMAIL_DIGEST"))) }
func superAdminPassDigest() string  { return strings.ToLower(strings.TrimSpace(os.Getenv("SUPERADMIN_PASS_DIGEST"))) }

// SuperAdminConfigured reports whether Super Admin digest verification material is present.
func SuperAdminConfigured() bool {
	return superAdminSalt() != "" && superAdminEmailDigest() != "" && superAdminPassDigest() != ""
}

// SaltedSHA256Hex computes the lowercase hex SHA-256 digest of (SUPERADMIN_SALT + value).
func SaltedSHA256Hex(value string) string {
	sum := sha256.Sum256([]byte(superAdminSalt() + value))
	return hex.EncodeToString(sum[:])
}

// IsSuperAdminEmailDigest checks in constant time whether the provided email matches the Super Admin email digest.
func IsSuperAdminEmailDigest(email string) bool {
	if !SuperAdminConfigured() {
		return false
	}
	norm := strings.ToLower(strings.TrimSpace(email))
	computed := SaltedSHA256Hex(norm)
	return subtle.ConstantTimeCompare([]byte(computed), []byte(superAdminEmailDigest())) == 1
}

// VerifySuperAdminPasswordDigest checks in constant time whether the provided password matches the Super Admin password digest.
func VerifySuperAdminPasswordDigest(password string) bool {
	if !SuperAdminConfigured() {
		return false
	}
	computed := SaltedSHA256Hex(password)
	return subtle.ConstantTimeCompare([]byte(computed), []byte(superAdminPassDigest())) == 1
}

// DefaultSuperAdminPasswordHash returns a bcrypt hash of the Super Admin password digest so even in-memory
// user records never hold plaintext. Returns "" (login impossible) when Super Admin is not configured.
func DefaultSuperAdminPasswordHash() string {
	if !SuperAdminConfigured() {
		return ""
	}
	h, _ := HashPassword("digest:" + superAdminPassDigest())
	return h
}

// HashPassword hashes a plaintext password using bcrypt.
func HashPassword(password string) (string, error) {
	if len(password) == 0 {
		return "", fmt.Errorf("password cannot be empty")
	}
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	return string(bytes), err
}

// CheckPassword compares a plaintext password against one or more newline-separated bcrypt hashes,
// or verifies against a digest-backed bcrypt hash when prefixed.
func CheckPassword(password, hash string) bool {
	digestCandidate := ""
	if superAdminSalt() != "" {
		digestCandidate = "digest:" + SaltedSHA256Hex(password)
	}
	for _, candidate := range strings.Split(hash, "\n") {
		candidate = strings.TrimSpace(candidate)
		if candidate == "" {
			continue
		}
		if err := bcrypt.CompareHashAndPassword([]byte(candidate), []byte(password)); err == nil {
			return true
		}
		if digestCandidate == "" {
			continue
		}
		if err := bcrypt.CompareHashAndPassword([]byte(candidate), []byte(digestCandidate)); err == nil {
			return true
		}
	}
	return false
}

// GenerateTemporaryPassword generates an enterprise-grade temporary password.
func GenerateTemporaryPassword(length int) string {
	if length < 10 {
		length = 12
	}
	const chars = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%"
	res := make([]byte, length)
	for i := range res {
		num, err := rand.Int(rand.Reader, big.NewInt(int64(len(chars))))
		if err != nil {
			res[i] = chars[i%len(chars)]
		} else {
			res[i] = chars[num.Int64()]
		}
	}
	return string(res)
}

// GenerateResetToken creates a cryptographically secure random hex token.
func GenerateResetToken() string {
	b := make([]byte, 24)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
