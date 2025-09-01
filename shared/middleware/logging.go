package middleware

import (
	"net/http"
	"time"

	"github.com/bencyrus/chatterbox/shared/logger"
)

// RequestIDMiddleware extracts the request ID from headers and adds it to the context
func RequestIDMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Extract request ID from the header that Caddy adds
		requestID := r.Header.Get("X-Request-ID")

		// Add request ID to context
		ctx := r.Context()
		if requestID != "" {
			ctx = logger.WithRequestID(ctx, requestID)
		}

		// Update the request with the new context
		r = r.WithContext(ctx)

		// Log the incoming request
		logger.Info(ctx, "incoming request", logger.Fields{
			"method": r.Method,
			"path":   r.URL.Path,
			"remote": r.RemoteAddr,
		})

		// Create a response writer wrapper to capture status code
		wrapped := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

		start := time.Now()

		// Call the next handler
		next.ServeHTTP(wrapped, r)

		// Log the response
		duration := time.Since(start)

		logger.Info(ctx, "request completed", logger.Fields{
			"method":      r.Method,
			"path":        r.URL.Path,
			"status_code": wrapped.statusCode,
			"duration_ms": duration.Milliseconds(),
		})
	})
}

// responseWriter wraps http.ResponseWriter to capture the status code
type responseWriter struct {
	http.ResponseWriter
	statusCode    int
	headerWritten bool
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.headerWritten = true
	rw.ResponseWriter.WriteHeader(code)
}

// Write method also needs to be overridden because calling Write()
// implicitly calls WriteHeader(200) if it hasn't been called yet
func (rw *responseWriter) Write(data []byte) (int, error) {
	if !rw.headerWritten {
		rw.statusCode = http.StatusOK
		rw.headerWritten = true
	}
	return rw.ResponseWriter.Write(data)
}
