# Default values, can be overridden
DOMAIN ?= yourdomain.com
CERT_DIR ?= $(PWD)/../mail-infra/services/silver-config/certbot/keys/etc

.PHONY: run build clean docker-build docker-run-https docker-stop docker-clean

run:
	go run . -port 8443 -cert $(CERT_DIR)/live/$(DOMAIN)/fullchain.pem -key $(CERT_DIR)/live/$(DOMAIN)/privkey.pem

build:
	go build -o bin/pingmailer-api .

clean:
	rm -rf bin

# Docker commands
docker-build:
	docker build -t pingmailer-api .

docker-run-https:
	docker run -d \
		-p 8443:8443 \
		-e PORT=8443 \
		-e CERT_FILE=/certs/live/$(DOMAIN)/fullchain.pem \
		-e KEY_FILE=/certs/live/$(DOMAIN)/privkey.pem \
		-v $(CERT_DIR):/certs:ro \
		--network mail-network \
		--name pingmailer-api \
		pingmailer-api

docker-stop:
	docker stop pingmailer-api || true
	docker rm pingmailer-api || true

docker-clean: docker-stop
	docker rmi pingmailer-api || true

docker-compose-up:
	docker-compose up -d

docker-compose-https:
	docker-compose -f docker-compose.https.yml up -d

docker-compose-down:
	docker-compose down

docker-logs:
	docker logs -f pingmailer-api
gci:
	golangci-lint run
