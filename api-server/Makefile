.PHONY: run build clean docker-build docker-run docker-stop docker-clean

run:
	go run . -port 8000

build:
	go build -o bin/pingmailer-api .

clean:
	rm -rf bin

# Docker commands
docker-build:
	docker build -t pingmailer-api .

docker-run:
	docker run -d \
		-p 8000:8000 \
		-e PORT=8000 \
		--name pingmailer-api \
		pingmailer-api

docker-stop:
	docker stop pingmailer-api || true
	docker rm pingmailer-api || true

docker-clean: docker-stop
	docker rmi pingmailer-api || true

docker-compose-up:
	docker-compose up -d

docker-compose-down:
	docker-compose down

docker-logs:
	docker logs -f pingmailer-api

gci:
	golangci-lint run
