package api

import (
	"context"
	"fmt"
	"net/http"
	"strings"
)

type contextKey string

const accessTokenContextKey contextKey = "access_token"

// extractBearerToken extracts the Bearer token from the Authorization header
func extractBearerToken(r *http.Request) (string, error) {
	authHeader := r.Header.Get("Authorization")
	if authHeader == "" {
		return "", fmt.Errorf("missing Authorization header")
	}

	parts := strings.SplitN(authHeader, " ", 2)
	if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
		return "", fmt.Errorf("invalid Authorization header format, expected 'Bearer <token>'")
	}

	return parts[1], nil
}

func accessTokenFromContext(ctx context.Context) (string, bool) {
	token, ok := ctx.Value(accessTokenContextKey).(string)
	if !ok || token == "" {
		return "", false
	}
	return token, true
}

// authMiddleware extracts the Bearer token and stores it for downstream SMTP XOAUTH2 auth.
// Token validation is intentionally not performed in this API server.
func (app *App) authMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token, err := extractBearerToken(r)
		if err != nil {
			app.logger.Warn("authentication failed", "error", err)
			http.Error(w, "Unauthorized: invalid authorization token", http.StatusUnauthorized)
			return
		}

		next(w, r.WithContext(context.WithValue(r.Context(), accessTokenContextKey, token)))
	}
}
