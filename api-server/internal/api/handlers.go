package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/mail"
	"strconv"

	"github.com/Silver-Mail-Platform/pingmailer/internal/emailer"
)

// handleHealth provides a simple health check endpoint
func (app *App) handleHealthCheck(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(map[string]string{
		"status":  "ok",
		"version": app.config.Version,
	}); err != nil {
		app.logger.Error("failed to encode health response", "error", err)
	}
}

type user struct {
	Name  string
	Email string
	APP   string
}

type recipient struct {
	Name  string `json:"name"`
	Email string `json:"email"`
}

type notifyRequest struct {
	SMTPHost       string         `json:"smtp_host"`
	SMTPPort       int            `json:"smtp_port"`
	SMTPUsername   string         `json:"smtp_username"`
	SMTPSender     string         `json:"smtp_sender"`
	Recipients     []recipient    `json:"recipients,omitempty"`
	RecipientName  string         `json:"recipient_name"`
	RecipientEmail string         `json:"recipient_email"`
	AppName        string         `json:"app_name"`
	Template       string         `json:"template,omitempty"`      // Optional: custom template content
	TemplateData   map[string]any `json:"template_data,omitempty"` // Optional: custom template data
}

func (app *App) handleNotify(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, http.StatusText(http.StatusMethodNotAllowed), http.StatusMethodNotAllowed)
		return
	}

	req, err := decodeNotifyRequest(r)
	if err != nil {
		app.logger.Error("failed to decode request body", "error", err)
		http.Error(w, "Invalid request body: "+err.Error(), http.StatusBadRequest)
		return
	}

	if !validateNotifyRequest(w, req) {
		return
	}
	applyNotifyDefaults(&req)

	accessToken, _ := accessTokenFromContext(r.Context())
	if accessToken == "" {
		http.Error(w, "Unauthorized: missing access token", http.StatusUnauthorized)
		return
	}

	// Create a new mailer instance with the provided SMTP configuration
	mailer := emailer.NewMailer(req.SMTPHost, req.SMTPPort, req.SMTPUsername, req.SMTPSender, accessToken)

	recipients := buildRecipients(req)

	app.background(func() {
		if err := sendNotifyEmail(mailer, req, recipients); err != nil {
			app.logger.Error("failed to send email", "error", err)
		} else {
			app.logger.Info("email sent successfully", "recipient_count", len(recipients))
		}
	})

	// Send 202 Accepted response
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	if err := json.NewEncoder(w).Encode(map[string]string{
		"message": "Email queued successfully",
		"status":  "ok",
	}); err != nil {
		app.logger.Error("failed to encode notify response", "error", err)
	}
}

func decodeNotifyRequest(r *http.Request) (notifyRequest, error) {
	var req notifyRequest
	err := json.NewDecoder(r.Body).Decode(&req)
	return req, err
}

func validateNotifyRequest(w http.ResponseWriter, req notifyRequest) bool {
	required := func(ok bool, message string) bool {
		if ok {
			return true
		}
		http.Error(w, message, http.StatusBadRequest)
		return false
	}
	if !required(req.SMTPHost != "", "Missing required field: smtp_host") {
		return false
	}
	if !required(req.SMTPPort != 0, "Missing required field: smtp_port") {
		return false
	}
	if !required(req.SMTPUsername != "", "Missing required field: smtp_username") {
		return false
	}
	if !required(req.SMTPSender != "", "Missing required field: smtp_sender") {
		return false
	}
	if !required(len(req.Recipients) > 0 || req.RecipientEmail != "", "Missing required recipient field: recipient_email or recipients") {
		return false
	}

	if _, err := mail.ParseAddress(req.SMTPSender); err != nil {
		http.Error(w, "Invalid smtp_sender email format: "+err.Error(), http.StatusBadRequest)
		return false
	}
	if req.RecipientEmail != "" {
		if _, err := mail.ParseAddress(req.RecipientEmail); err != nil {
			http.Error(w, "Invalid recipient_email format: "+err.Error(), http.StatusBadRequest)
			return false
		}
	}

	for i, rcp := range req.Recipients {
		if rcp.Email == "" {
			http.Error(w, "Missing recipients["+strconv.Itoa(i)+"].email", http.StatusBadRequest)
			return false
		}
		if _, err := mail.ParseAddress(rcp.Email); err != nil {
			http.Error(w, "Invalid recipients["+strconv.Itoa(i)+"].email format: "+err.Error(), http.StatusBadRequest)
			return false
		}
	}

	return true
}

func applyNotifyDefaults(req *notifyRequest) {
	if req.RecipientName == "" {
		req.RecipientName = "User"
	}
	if req.AppName == "" {
		req.AppName = "Application"
	}

	for i := range req.Recipients {
		if req.Recipients[i].Name == "" {
			req.Recipients[i].Name = "User"
		}
	}
}

func buildRecipients(req notifyRequest) []user {
	recipients := make([]user, 0, len(req.Recipients)+1)

	if req.RecipientEmail != "" {
		recipients = append(recipients, user{
			Name:  req.RecipientName,
			Email: req.RecipientEmail,
			APP:   req.AppName,
		})
	}

	for _, rcp := range req.Recipients {
		recipients = append(recipients, user{
			Name:  rcp.Name,
			Email: rcp.Email,
			APP:   req.AppName,
		})
	}

	return recipients
}

func sendNotifyEmail(mailer emailer.Mailer, req notifyRequest, recipients []user) error {
	var sendErrors []error

	for _, recipient := range recipients {
		if req.Template == "" {
			if err := mailer.Send(recipient.Email, "welcome.tmpl", recipient); err != nil {
				sendErrors = append(sendErrors, fmt.Errorf("recipient %s: %w", recipient.Email, err))
			}
			continue
		}

		templateData := any(recipient)
		if len(req.TemplateData) > 0 {
			templateData = req.TemplateData
		}

		if err := mailer.SendWithCustomTemplate(recipient.Email, req.Template, templateData); err != nil {
			sendErrors = append(sendErrors, fmt.Errorf("recipient %s: %w", recipient.Email, err))
		}
	}

	return errors.Join(sendErrors...)
}
