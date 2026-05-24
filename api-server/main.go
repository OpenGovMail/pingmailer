package main

import (
	"flag"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/Silver-Mail-Platform/pingmailer/internal/api"
)

func main() {
	var cfg api.Config
	flag.IntVar(&cfg.Port, "port", 8443, "API server HTTPS port")
	flag.StringVar(&cfg.Version, "version", "0.1.0", "Version")
	flag.StringVar(&cfg.CertFile, "cert", "", "Path to TLS certificate file (e.g., /path/to/fullchain.pem)")
	flag.StringVar(&cfg.KeyFile, "key", "", "Path to TLS key file (e.g., /path/to/privkey.pem)")

	flag.Parse()

	logger := slog.New(slog.NewTextHandler(os.Stdout, nil))

	// Keep a shared HTTP client for future integrations.
	httpClient := &http.Client{
		Timeout: 10 * time.Second,
	}
	app := api.New(cfg, logger, httpClient)

	err := app.Serve()
	if err != nil {
		logger.Error(err.Error())
		os.Exit(1)
	}
}
