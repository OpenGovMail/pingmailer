package main

import (
	"flag"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/OpenGovMail/pingmailer/internal/api"
)

func main() {
	var cfg api.Config
	flag.IntVar(&cfg.Port, "port", 8000, "API server port")
	flag.StringVar(&cfg.Version, "version", "0.1.0", "Version")

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
