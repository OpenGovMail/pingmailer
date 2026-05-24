package api

import (
	"log/slog"
	"net/http"
	"sync"
)

// Config holds API server configuration.
type Config struct {
	Port     int
	Version  string
	CertFile string
	KeyFile  string
	OAuth2   OAuth2Config
}

// OAuth2Config holds the OAuth2 server configuration.
type OAuth2Config struct {
	IntrospectURL string
}

// App contains dependencies and config for serving API requests.
type App struct {
	config     Config
	logger     *slog.Logger
	httpClient *http.Client
	wg         sync.WaitGroup
}

// New builds an App with injected dependencies.
func New(config Config, logger *slog.Logger, httpClient *http.Client) *App {
	return &App{
		config:     config,
		logger:     logger,
		httpClient: httpClient,
	}
}
