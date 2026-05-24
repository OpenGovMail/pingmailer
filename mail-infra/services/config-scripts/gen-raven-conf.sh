#!/bin/bash
# -----------------------------------------------------------------------------
# Raven Configuration Generator
# Generates the raven.yaml and copies required certificates.
# -----------------------------------------------------------------------------

set -euo pipefail # Exit on error, undefined vars, or failed pipe

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"       # /root/silver/services
GEN_DIR="${ROOT_DIR}/silver-config/raven" # Base path

CONFIG_FILE="${ROOT_DIR}/../conf/silver.yaml"
OUTPUT_FILE="${GEN_DIR}/conf/raven.yaml"

# --- Extract primary (first) domain from silver.yaml ---
# Look for the first domain entry under the domains list
MAIL_DOMAIN=$(grep -m 1 '^\s*-\s*domain:' "$CONFIG_FILE" | sed 's/.*domain:\s*//' | xargs)
MAIL_DOMAIN=${MAIL_DOMAIN:-example.local}

# --- Certificate paths ---
LETSENCRYPT_PATH="${ROOT_DIR}/silver-config/certbot/keys/etc/live/${MAIL_DOMAIN}"
RAVEN_CERT_PATH="${ROOT_DIR}/silver-config/raven/certs"

# --- Create necessary directories ---
mkdir -p "$(dirname "$OUTPUT_FILE")"
mkdir -p "${RAVEN_CERT_PATH}"

# --- Generate raven.yaml ---
cat >"$OUTPUT_FILE" <<EOF
domain: ${MAIL_DOMAIN}
auth_server_url: https://thunder-server:8090/auth/credentials/authenticate

sasl_scope: "tcp_only"

# OAUTHBEARER Token Validation (RFC 7628)
# Required when enabling AUTH=OAUTHBEARER for IMAP/SASL.
oauth_issuer_url: "https://${MAIL_DOMAIN}:8090"
oauth_jwks_url: "https://${MAIL_DOMAIN}:8090/oauth2/jwks"
oauth_audience:
  - "client_id_for_application"
oauth_clock_skew_seconds: 60
oauth_client_email_authorization_file: "/app/config/oauth_client_email_authorization.json"
EOF

echo "✅ Generated: $OUTPUT_FILE (domain: ${MAIL_DOMAIN})"

# --- Copy certificates ---
if [ -f "${LETSENCRYPT_PATH}/fullchain.pem" ] && [ -f "${LETSENCRYPT_PATH}/privkey.pem" ]; then
	cp "${LETSENCRYPT_PATH}/fullchain.pem" "${RAVEN_CERT_PATH}/fullchain.pem"
	cp "${LETSENCRYPT_PATH}/privkey.pem" "${RAVEN_CERT_PATH}/privkey.pem"
	echo "✅ Copied Raven certificates for domain: ${MAIL_DOMAIN}"
else
	echo "⚠️ Warning: Certificates not found in ${LETSENCRYPT_PATH}"
	echo "   Skipped copying Raven certificates."
fi

echo "✅ Raven configuration successfully generated."
