package emailer

import (
	"bytes"
	"embed"
	"errors"
	"fmt"
	"html/template"
	"net/smtp"
	"time"

	"github.com/go-mail/mail/v2"
)

// templateFS holds the embedded email templates.
//
//go:embed "templates"
var templateFS embed.FS

// Mailer handles email delivery using SMTP and embedded templates.
type Mailer struct {
	dialer     *mail.Dialer
	sender     string
	senderName string
}

// NewMailer returns a Mailer configured for SMTP auth. When accessToken is
// provided, it uses XOAUTH2 with the SMTP sender (email address) as the user
// identifier in the auth payload. senderName is the display name shown in the
// From header; the SMTP/XOAUTH2 identity stays the bare sender address.
func NewMailer(host string, port int, senderName string, sender, accessToken string) Mailer {
	dialer := mail.NewDialer(host, port, "", "")
	dialer.Auth = &xoauth2Auth{
		username: sender,
		token:    accessToken,
	}
	dialer.Timeout = 2 * time.Second

	return Mailer{
		dialer:     dialer,
		sender:     sender,
		senderName: senderName,
	}
}

type xoauth2Auth struct {
	username string
	token    string
}

func (a *xoauth2Auth) Start(server *smtp.ServerInfo) (string, []byte, error) {
	if !server.TLS {
		return "", nil, errors.New("xoauth2 requires TLS")
	}

	initialResponse := fmt.Sprintf("user=%s\x01auth=Bearer %s\x01\x01", a.username, a.token)

	return "XOAUTH2", []byte(initialResponse), nil
}

func (a *xoauth2Auth) Next(_ []byte, more bool) ([]byte, error) {
	if more {
		return nil, errors.New("unexpected server challenge during XOAUTH2 authentication")
	}
	return nil, nil
}

// Send renders the specified template with the provided data and delivers
// the email to the recipient. The template file must define "subject",
// "plainBody", and "htmlBody" blocks.
func (m Mailer) Send(recipient, templateFile string, data any) error {
	tmpl, err := template.New("email").ParseFS(templateFS, "templates/"+templateFile)
	if err != nil {
		return err
	}
	return m.send(recipient, tmpl, data)
}

// SendWithCustomTemplate renders a custom template string with the provided data
// and delivers the email to the recipient. The template must define "subject",
// "plainBody", and "htmlBody" blocks.
func (m Mailer) SendWithCustomTemplate(recipient, templateContent string, data any) error {
	tmpl, err := template.New("email").Parse(templateContent)
	if err != nil {
		return err
	}
	return m.send(recipient, tmpl, data)
}

// Message is an email's content as it is sent: no template is applied to it.
// At least one of TextBody and HTMLBody is set.
type Message struct {
	Subject  string
	TextBody string
	HTMLBody string
}

// SendMessage delivers msg to the recipient as written. A message with both
// bodies is sent as multipart/alternative; one with a single body is sent with
// that body alone.
func (m Mailer) SendMessage(recipient string, msg Message) error {
	if msg.TextBody == "" && msg.HTMLBody == "" {
		return errors.New("message has no body")
	}
	return m.deliver(m.build(recipient, msg))
}

// send renders the template's "subject", "plainBody" and "htmlBody" blocks
// with data and delivers the result.
func (m Mailer) send(recipient string, tmpl *template.Template, data any) error {
	var msg Message
	for _, block := range []struct {
		name string
		out  *string
	}{{"subject", &msg.Subject}, {"plainBody", &msg.TextBody}, {"htmlBody", &msg.HTMLBody}} {
		buf := new(bytes.Buffer)
		if err := tmpl.ExecuteTemplate(buf, block.name, data); err != nil {
			return err
		}
		*block.out = buf.String()
	}
	return m.deliver(m.build(recipient, msg))
}

// build assembles the email for one recipient.
func (m Mailer) build(recipient string, msg Message) *mail.Message {
	out := mail.NewMessage()
	out.SetHeader("To", recipient)
	if m.senderName != "" {
		// smtp_username, address (and SMTP/XOAUTH2 identity) from smtp_sender.
		out.SetAddressHeader("From", m.sender, m.senderName)
	} else {
		out.SetHeader("From", m.sender)
	}
	out.SetHeader("Subject", msg.Subject)
	switch {
	case msg.TextBody != "" && msg.HTMLBody != "":
		out.SetBody("text/plain", msg.TextBody)
		out.AddAlternative("text/html", msg.HTMLBody)
	case msg.HTMLBody != "":
		out.SetBody("text/html", msg.HTMLBody)
	default:
		out.SetBody("text/plain", msg.TextBody)
	}
	return out
}

// deliver sends the email, retrying a failed attempt.
func (m Mailer) deliver(msg *mail.Message) error {
	const maxRetries = 3
	const retrySleep = 500 * time.Millisecond

	var err error
	for i := range maxRetries {
		err = m.dialer.DialAndSend(msg)
		if err == nil {
			return nil
		}

		if i < maxRetries-1 {
			time.Sleep(retrySleep)
		}
	}
	return err
}
