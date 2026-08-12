#!/bin/bash

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Root directory contains docker-compose.yml
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../" && pwd)"

# Navigate to root directory and stop docker services
echo "Stopping PingMailer services and API Endpoint..."
(cd "${ROOT_DIR}" && docker compose down)