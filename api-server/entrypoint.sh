#!/bin/sh
set -e

if [ -z "${CERT_FILE}" ] || [ -z "${KEY_FILE}" ]; then
    echo "ERROR: HTTPS is required. Set CERT_FILE and KEY_FILE." >&2
    exit 1
fi

# Use positional parameters to safely build the command. This avoids issues with
# word splitting if variables contain spaces or special characters.
set -- ./api-server -port "${PORT}" -cert "${CERT_FILE}" -key "${KEY_FILE}"
exec "$@"
