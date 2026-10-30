package emailer

import (
	"bytes"
	"strings"
	"testing"
)

func render(t *testing.T, msg Message) string {
	t.Helper()
	var buf bytes.Buffer
	if _, err := NewMailer("smtp.example.com", 587, "", "no-reply@example.com", "token").build("to@example.com", msg).WriteTo(&buf); err != nil {
		t.Fatal(err)
	}
	return buf.String()
}

// A message is sent as written: nothing in it is escaped or run as a template.
func TestBuild_SendsTheContentAsWritten(t *testing.T) {
	out := render(t, Message{
		Subject:  "Tom & Jerry's {{.Order}}",
		TextBody: "Dear <Name>, a & b",
		HTMLBody: "<p>Dear <b>Tom</b> &amp; {{.Order}}</p>",
	})

	for _, want := range []string{
		"Subject: Tom & Jerry's {{.Order}}",
		"Content-Type: multipart/alternative",
		"Dear <Name>, a & b",
		"<p>Dear <b>Tom</b> &amp; {{.Order}}</p>",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("message lacks %q:\n%s", want, out)
		}
	}
}

// A message with one body is sent with that body alone.
func TestBuild_OneBody(t *testing.T) {
	for name, tc := range map[string]struct {
		msg      Message
		wantType string
	}{
		"text only": {Message{Subject: "s", TextBody: "hello"}, "Content-Type: text/plain"},
		"html only": {Message{Subject: "s", HTMLBody: "<p>hello</p>"}, "Content-Type: text/html"},
	} {
		t.Run(name, func(t *testing.T) {
			out := render(t, tc.msg)
			if !strings.Contains(out, tc.wantType) || strings.Contains(out, "multipart/alternative") {
				t.Errorf("want a single %q part:\n%s", tc.wantType, out)
			}
		})
	}
}

func TestSendMessage_RequiresABody(t *testing.T) {
	err := NewMailer("smtp.example.com", 587, "", "no-reply@example.com", "token").SendMessage("to@example.com", Message{Subject: "s"})
	if err == nil {
		t.Fatal("want an error for a message without a body")
	}
}
