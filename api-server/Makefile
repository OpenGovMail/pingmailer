.PHONY: run build clean docker-build docker-run docker-stop docker-clean

run:
	go run . -port 8000

build:
	go build -o bin/opengovmail-api .

clean:
	rm -rf bin

# Docker commands
docker-build:
	docker build -t opengovmail-api .

docker-run:
	docker run -d \
		-p 8000:8000 \
		-e PORT=8000 \
		--name opengovmail-api \
		opengovmail-api

docker-stop:
	docker stop opengovmail-api || true
	docker rm opengovmail-api || true

docker-clean: docker-stop
	docker rmi opengovmail-api || true

docker-compose-up:
	docker-compose up -d

docker-compose-down:
	docker-compose down

docker-logs:
	docker logs -f opengovmail-api

gci:
	golangci-lint run
