# PingMailer
**_Simple Email Service for Transactional Emails_**

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)
![Last Commit](https://img.shields.io/github/last-commit/Silver-Mail-Platform/pingmailer)

**PingMailer** is a lightweight service for sending transactional emails. It provides a simple REST API for email delivery using SMTP, powered by [Silver](https://github.com/LSFLK/silver) mail infrastructure.

<p align="center">
  •   <a href="#features">Features</a> •
  <a href="#getting-started">Getting Started</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#license">License</a> •
</p>

## Features

- **Simple REST API** – Send emails via HTTPS requests
- **Template Support** – Pre-built email templates for common use cases
- **SMTP Integration** – Works with any SMTP server or Silver instance
- **Lightweight** – Minimal resource footprint
- **Dockerized** – Easy deployment with Docker Compose

## Getting Started

### Prerequisites
- Docker and Docker Compose installed
- SMTP server credentials (or a running Silver instance)

### Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/Silver-Mail-Platform/pingmailer.git
   cd pingmailer
   ```

2. **Set up the mail infrastructure**
   ```bash
   bash mail-infra/scripts/setup/setup.sh
   ```

3. **Start the Silver mail server**
   ```bash
   bash mail-infra/scripts/service/start-silver.sh
   ```

4. **Configure the API server**
   ```bash
   cd api-server
   cp .env.example .env
   ```
   
   Edit the `.env` file to set your `DOMAIN` for SSL certificate configuration.

5. **Start the API server**
   ```bash
   docker compose -f docker-compose.https.yml up -d
   ```

6. **Send a test email**
   ```bash
   curl -k -X POST https://localhost:8443/notify \
       -H "Authorization: Bearer <access-token>" \
     -H "Content-Type: application/json" \
     -d '{
       "smtp_host": "your_smtp_host",
       "smtp_port": 587,
       "smtp_username": "your_smtp_username",
       "smtp_sender": "sender@example.com",
          "recipients": [
             {
                "email": "user@example.com",
                "name": "User"
             }
          ]
     }'
    ```

    The API forwards the bearer access token to SMTP using XOAUTH2.

## Architecture

PingMailer consists of two main components:

- **`api-server/`** - Go-based REST API server for sending templated emails
- **`mail-infra/`** - Silver SMTP components for outgoing mail delivery

The API server accepts HTTPS requests and forwards emails through the configured SMTP server. Email templates are stored in `api-server/internal/emailer/templates/`.

## License

Distributed under the Apache 2.0 License. See [LICENSE](LICENSE) for more information.
