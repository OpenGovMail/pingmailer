package api

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func validRequest() notifyRequest {
	return notifyRequest{
		SMTPHost:     "smtp.example.com",
		SMTPPort:     587,
		SMTPUsername: "no-reply@example.com",
		SMTPSender:   "no-reply@example.com",
		Recipients:   []recipient{{Email: "to@example.com"}},
	}
}

// Content sent as written needs a body, and can't be combined with a template.
func TestValidateNotifyRequest_Content(t *testing.T) {
	for name, tc := range map[string]struct {
		edit func(*notifyRequest)
		want int
	}{
		"template only":   {func(r *notifyRequest) { r.Template = `{{define "subject"}}s{{end}}` }, http.StatusOK},
		"text body":       {func(r *notifyRequest) { r.Subject, r.TextBody = "s", "hello" }, http.StatusOK},
		"html body":       {func(r *notifyRequest) { r.Subject, r.HTMLBody = "s", "<p>hello</p>" }, http.StatusOK},
		"subject only":    {func(r *notifyRequest) { r.Subject = "s" }, http.StatusBadRequest},
		"with a template": {func(r *notifyRequest) { r.TextBody, r.Template = "hello", "t" }, http.StatusBadRequest},
	} {
		t.Run(name, func(t *testing.T) {
			req := validRequest()
			tc.edit(&req)
			w := httptest.NewRecorder()

			ok := validateNotifyRequest(w, req)

			if got := map[bool]int{true: http.StatusOK, false: w.Code}[ok]; got != tc.want {
				t.Errorf("got %d, want %d (%s)", got, tc.want, w.Body.String())
			}
		})
	}
}
