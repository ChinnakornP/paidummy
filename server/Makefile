COMPOSE := docker compose -f ../docker-compose.yml

.PHONY: up down run test test-int tidy lint cover

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

run:
	go run ./cmd/server

test:
	go test ./... -count=1

cover:
	go test ./internal/game/ -cover -count=1

test-int:
	go test -tags=integration ./test/integration/ -count=1

tidy:
	go mod tidy

lint:
	go vet ./...
