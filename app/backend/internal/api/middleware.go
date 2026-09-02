package api

import (
	"log/slog"
	"net/http"
	"time"
)

// withLogging logs each request's method, path, and duration, and recovers
// from panics in handlers so one bad request can't take the whole server
// down - important for a process that's supposed to stay up indefinitely
// under systemd.
func withLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				slog.Error("panic recovered in handler", "err", rec, "path", r.URL.Path)
				http.Error(w, "internal error", http.StatusInternalServerError)
			}
		}()

		start := time.Now()
		next.ServeHTTP(w, r)
		slog.Info("request", "method", r.Method, "path", r.URL.Path, "duration", time.Since(start))
	})
}
