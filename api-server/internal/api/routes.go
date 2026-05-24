package api

import "net/http"

func (app *App) routes() http.Handler {
	mux := http.NewServeMux()

	// Protected endpoint - requires Bearer token authentication.
	mux.HandleFunc("/notify", app.authMiddleware(app.handleNotify))

	// Health check endpoint (unprotected)
	mux.HandleFunc("/healthcheck", app.handleHealthCheck)

	return mux
}
