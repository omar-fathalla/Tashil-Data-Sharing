package security

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"fmt"
	"math/big"
	"strings"

	"golang.org/x/crypto/bcrypt"
)

const (
	// superAdminSalt is the cryptographic domain separator for Super Admin identity verification.
	superAdminSalt = "TashilZeroTrust#2026$"
	// superAdminEmailDigest is the SHA-256 hex digest of (superAdminSalt + lower(email)).
	// Neither the username/email nor the password exists in plaintext in source code.
	superAdminEmailDigest = "61ee72585b69ceb7b91162cac5497cbc154a2db0960d552b22074855596c44e3"
	// superAdminPassDigest is the SHA-256 hex digest of (superAdminSalt + password).
	superAdminPassDigest = "f7bfe577dbc57526d0a91980d66af0e6e026b43194ed2bae7e3166c7a8edd023"
)

// SaltedSHA256Hex computes the lowercase hex SHA-256 digest of (superAdminSalt + value).
func SaltedSHA256Hex(value string) string {
	sum := sha256.Sum256([]byte(superAdminSalt + value))
	return hex.EncodeToString(sum[:])
}

// IsSuperAdminEmailDigest checks in constant time whether the provided email matches the Super Admin email digest.
func IsSuperAdminEmailDigest(email string) bool {
	norm := strings.ToLower(strings.TrimSpace(email))
	computed := SaltedSHA256Hex(norm)
	return subtle.ConstantTimeCompare([]byte(computed), []byte(superAdminEmailDigest)) == 1
}

// VerifySuperAdminPasswordDigest checks in constant time whether the provided password matches the Super Admin password digest.
func VerifySuperAdminPasswordDigest(password string) bool {
	computed := SaltedSHA256Hex(password)
	return subtle.ConstantTimeCompare([]byte(computed), []byte(superAdminPassDigest)) == 1
}

// DefaultSuperAdminPasswordHash returns a bcrypt hash of the Super Admin password digest so even in-memory user records never hold plaintext.
func DefaultSuperAdminPasswordHash() string {
	h, _ := HashPassword("digest:" + superAdminPassDigest)
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
	digestCandidate := "digest:" + SaltedSHA256Hex(password)
	for _, candidate := range strings.Split(hash, "\n") {
		candidate = strings.TrimSpace(candidate)
		if candidate == "" {
			continue
		}
		if err := bcrypt.CompareHashAndPassword([]byte(candidate), []byte(password)); err == nil {
			return true
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
