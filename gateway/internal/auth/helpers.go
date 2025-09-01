package auth

import (
	"context"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/bencyrus/chatterbox/gateway/internal/config"
	"github.com/golang-jwt/jwt/v5"
)

// AccessTokenSecondsRemaining parses the Authorization Bearer token and returns
// seconds remaining until expiration. Second return is false when the token is
// missing/invalid or has no expiry.
func AccessTokenSecondsRemaining(cfg config.Config, headers http.Header, now time.Time) (int, bool) {
	log.Println("AccessTokenSecondsRemaining")
	authz := headers.Get("Authorization")
	log.Println("authz", authz)
	if authz == "" {
		log.Println("AccessTokenSecondsRemaining: authz == \"\"")
		return 0, false
	}
	const bearerPrefix = "Bearer "
	if !strings.HasPrefix(authz, bearerPrefix) {
		log.Println("AccessTokenSecondsRemaining: !strings.HasPrefix(authz, bearerPrefix)")
		return 0, false
	}
	tokenStr := strings.TrimSpace(strings.TrimPrefix(authz, bearerPrefix))
	log.Println("tokenStr", tokenStr)
	if tokenStr == "" {
		log.Println("AccessTokenSecondsRemaining: tokenStr == \"\"")
		return 0, false
	}

	token, err := jwt.ParseWithClaims(tokenStr, jwt.MapClaims{}, func(token *jwt.Token) (any, error) {
		log.Println("ParseWithClaims")
		return []byte(cfg.JWTSecret), nil
	}, jwt.WithValidMethods([]string{"HS256"}))
	if err != nil {
		log.Println("ParseWithClaims: error", err)
		return 0, false
	}
	// Extract exp from claims as a float64 Unix timestamp
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || claims == nil {
		log.Println("ParseWithClaims: claims not MapClaims")
		return 0, false
	}
	rawExp, exists := claims["exp"].(float64)
	if !exists {
		log.Println("ParseWithClaims: exp claim missing or invalid")
		return 0, false
	}
	expUnix := int64(rawExp)
	remaining := int(time.Unix(expUnix, 0).Sub(now).Seconds())
	log.Println("remaining", remaining)
	return remaining, true
}

// ShouldRefreshAccessToken returns true when the access token is present and
// will expire within cfg.RefreshThresholdSeconds.
func ShouldRefreshAccessToken(cfg config.Config, headers http.Header, now time.Time) bool {
	remaining, ok := AccessTokenSecondsRemaining(cfg, headers, now)
	if !ok {
		return false
	}
	return remaining <= cfg.RefreshThresholdSeconds
}

// PreflightRefresh attempts a token refresh within maxWait. Returns nil on timeout or error.
func PreflightRefresh(ctx context.Context, cfg config.Config, requestHeaders http.Header, maxWait time.Duration) *RefreshResult {
	ctx2, cancel := context.WithTimeout(ctx, maxWait)
	defer cancel()
	res, err := RefreshIfPresent(ctx2, cfg, requestHeaders)
	if err != nil || res == nil {
		return nil
	}
	return res
}

// AttachRefreshedTokens sets response headers with refreshed tokens when present.
func AttachRefreshedTokens(responseHeaders http.Header, cfg config.Config, result *RefreshResult) {
	if result == nil {
		return
	}
	responseHeaders.Set(cfg.NewAccessTokenHeaderOut, result.AccessToken)
	responseHeaders.Set(cfg.NewRefreshTokenHeaderOut, result.RefreshToken)
}
