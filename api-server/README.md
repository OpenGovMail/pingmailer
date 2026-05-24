# PingMailer API Server

A simple REST API service for sending emails via SMTP. Part of the Silver Mail Platform.

## Quick Start

### Deploy with Docker Compose (Recommended)

```bash
# 1. Configure your environment
cp .env.example .env

# 2. Edit .env and update these values:
#    - DOMAIN: your actual domain name
#    - CERT_PATH: path to your SSL certificates

# 3. Start the service
docker compose -f docker-compose.https.yml up -d

# View logs
docker logs pingmailer-api-server -f
```

The API will be available at `https://your-domain:8443/notify`

## API Usage

### Send Email

**Endpoint:** `POST /notify`

**Example Request:**

```bash
curl -X POST https://your-domain:8443/notify \
  -H "Authorization: Bearer <access-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "smtp_host": "smtp-server-container",
    "smtp_port": 587,
    "smtp_username": "user@yourdomain.com",
    "smtp_sender": "noreply@yourdomain.com",
    "recipients": [
      {
        "email": "recipient1@example.com",
        "name": "John Doe"
      },
      {
        "email": "recipient2@example.com",
        "name": "Jane Doe"
      }
    ],
    "app_name": "MyApp"
  }'
```

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `smtp_host` | string | SMTP server hostname |
| `smtp_port` | integer | SMTP server port (587 for TLS) |
| `smtp_username` | string | SMTP authentication username |
| `smtp_sender` | string | Sender email address |
| `recipients` or `recipient_email` | array or string | Recipient list or a single recipient email (legacy) |

The request must include an `Authorization: Bearer <access-token>` header. The
API forwards this token to SMTP using XOAUTH2 and does not validate it locally.

### Optional Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `recipient_name` | string | "User" | Recipient's name |
| `recipients` | array | - | List of recipients: `{ "email": "...", "name": "..." }` |
| `app_name` | string | "Application" | Application name for email template |
| `template` | string | - | Custom email template |
| `template_data` | object | - | Data for custom template |

## Custom Templates

You can use custom email templates by providing the `template` and `template_data` fields.

### Template Format

Templates use Go's `text/template` syntax with three parts:

```go
{{define "subject"}}Your Subject Here{{end}}

{{define "plainBody"}}
Plain text version of your email
{{end}}

{{define "htmlBody"}}
<!doctype html>
<html>
<body>
HTML version of your email
</body>
</html>
{{end}}
```

### Template Variables

Access custom data in your template using `{{.FieldName}}`:

```bash
curl -X POST https://your-domain:8443/notify \
  -H "Authorization: Bearer <access-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "smtp_host": "smtp-server",
    "smtp_port": 587,
    "smtp_username": "user@domain.com",
    "smtp_sender": "noreply@domain.com",
    "recipients": [
      {
        "email": "user@example.com",
        "name": "John"
      }
    ],
    "template": "{{define \"subject\"}}Password Reset{{end}}{{define \"plainBody\"}}Hi {{.Name}}, your code is {{.Code}}{{end}}{{define \"htmlBody\"}}<p>Hi {{.Name}}, your code is <strong>{{.Code}}</strong></p>{{end}}",
    "template_data": {
      "Name": "John",
      "Code": "123456"
    }
  }'
```

## API Responses

### Success Response

**Status:** `202 Accepted`

```json
{
  "message": "Email queued successfully",
  "status": "ok"
}
```

### Error Responses

**Status:** `400 Bad Request` - Invalid request data

```json
{
  "error": "invalid request data: missing required field"
}
```

**Status:** `500 Internal Server Error` - Email sending failed

```json
{
  "error": "failed to send email: connection timeout"
}
```

## Development

### Running Locally

```bash
# Run with HTTPS (requires valid cert/key files)
make run

# Build binary
make build
```

### Docker Commands

```bash
# Build image
make docker-build

# Run with HTTPS
make docker-run-https DOMAIN=yourdomain.com

# View logs
make docker-logs

# Stop and remove container
make docker-stop
```
