# Multi-stage build for optimal image size
# Stage 1: Build the Go application
FROM golang:alpine AS builder

# Install build dependencies
RUN apk add --no-cache git ca-certificates tzdata

# Set GOTOOLCHAIN to auto to allow newer go versions
ENV GOTOOLCHAIN=auto

# Set working directory
WORKDIR /build

# Copy go mod files and download dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy the entire source code
COPY . .

# Build the application
# CGO_ENABLED=0 for static binary, GOOS=linux for Linux systems
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -ldflags="-w -s" -o api-server .

# Stage 2: Create the final minimal image
FROM alpine:latest

# Install ca-certificates for HTTPS requests
RUN apk --no-cache add ca-certificates tzdata

# Create a non-root user
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

# Set working directory
WORKDIR /app

# Copy the binary from builder
COPY --from=builder /build/api-server .

# Copy templates directory (needed for email templates)
COPY --from=builder /build/internal/emailer/templates ./internal/emailer/templates

# Create directory for certificates (will be mounted as volume)
RUN mkdir -p /certs

# Change ownership of the app directory
RUN chown -R appuser:appuser /app

# Note: Running as root to access certificate files mounted from host
# The certificate files are typically owned by root with restricted permissions
# Since we mount them read-only (:ro), this is acceptable
# For production, consider using Docker secrets or adjusting host file permissions

# Expose HTTPS port
EXPOSE 8443

# Set environment variables (can be overridden)
ENV PORT=8443
ENV CERT_FILE=""
ENV KEY_FILE=""

# Copy and set up entrypoint script
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

# Use entrypoint script for proper signal handling
ENTRYPOINT ["./entrypoint.sh"]
