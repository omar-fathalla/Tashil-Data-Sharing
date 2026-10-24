package security

import (
	"testing"
)

func TestPasswordHashingAndVerification(t *testing.T) {
	rawPassword := "test-only-hash-input"

	hash, err := HashPassword(rawPassword)
	if err != nil {
		t.Fatalf("expected no error hashing password, got %v", err)
	}

	if hash == rawPassword {
		t.Fatalf("expected hash to differ from raw password")
	}

	if !CheckPassword(rawPassword, hash) {
		t.Fatalf("expected CheckPassword to return true for matching password")
	}

	if CheckPassword("WrongPassword123!", hash) {
		t.Fatalf("expected CheckPassword to return false for incorrect password")
	}

	// Empty password should error
	_, err = HashPassword("")
	if err == nil {
		t.Fatalf("expected error when hashing empty password")
	}
}

func TestGenerateTemporaryPassword(t *testing.T) {
	pass1 := GenerateTemporaryPassword(14)
	if len(pass1) != 14 {
		t.Fatalf("expected password length 14, got %d", len(pass1))
	}

	pass2 := GenerateTemporaryPassword(14)
	if pass1 == pass2 {
		t.Fatalf("expected unique passwords across invocations")
	}
}

func TestGenerateResetToken(t *testing.T) {
	token1 := GenerateResetToken()
	token2 := GenerateResetToken()

	if len(token1) != 48 { // 24 bytes hex-encoded = 48 hex chars
		t.Fatalf("expected 48 char hex token, got %d", len(token1))
	}

	if token1 == token2 {
		t.Fatalf("expected reset tokens to be unique")
	}
}
