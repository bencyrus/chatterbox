// Package proxytoken implements short-lived HMAC-signed tokens that authorize
// the files service streaming proxy endpoints. A token is the capability that
// allows a single upload (op "put") or download (op "get") of a specific id,
// analogous to a GCS signed URL.
package proxytoken

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strconv"
	"strings"
	"time"
)

const version = "v1"

// Operations a token can authorize.
const (
	OpPut = "put"
	OpGet = "get"
)

// Signer signs and verifies proxy tokens using a shared secret.
type Signer struct {
	secret []byte
}

// NewSigner constructs a Signer from the given secret.
func NewSigner(secret string) *Signer {
	return &Signer{secret: []byte(secret)}
}

// Sign returns a token of the form v1.<op>.<id>.<exp>.<sig> authorizing the
// given operation on the given id until now+ttl.
func (s *Signer) Sign(op string, id int64, ttl time.Duration) string {
	exp := time.Now().Add(ttl).Unix()
	payload := fmt.Sprintf("%s.%s.%d.%d", version, op, id, exp)
	return payload + "." + s.mac(payload)
}

// Verify validates the token against the expected operation, checks the
// signature in constant time, and enforces expiry. On success it returns the
// embedded id.
func (s *Signer) Verify(token, expectedOp string) (int64, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 5 {
		return 0, fmt.Errorf("invalid token format")
	}

	ver, op, idStr, expStr, sig := parts[0], parts[1], parts[2], parts[3], parts[4]

	if ver != version {
		return 0, fmt.Errorf("unsupported token version")
	}
	if op != expectedOp {
		return 0, fmt.Errorf("token operation mismatch")
	}

	payload := fmt.Sprintf("%s.%s.%s.%s", ver, op, idStr, expStr)
	expectedSig := s.mac(payload)
	if !hmac.Equal([]byte(sig), []byte(expectedSig)) {
		return 0, fmt.Errorf("invalid token signature")
	}

	exp, err := strconv.ParseInt(expStr, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid token expiry")
	}
	if time.Now().Unix() > exp {
		return 0, fmt.Errorf("token expired")
	}

	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid token id")
	}

	return id, nil
}

func (s *Signer) mac(payload string) string {
	m := hmac.New(sha256.New, s.secret)
	m.Write([]byte(payload))
	return hex.EncodeToString(m.Sum(nil))
}
