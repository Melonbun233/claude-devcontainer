.PHONY: build start attach stop logs clean status

IMAGE_NAME := claude-sandbox
COMPOSE := docker compose

# Build the container image
build:
	$(COMPOSE) build

# Start the container (default: develop mode)
# Usage: make start  or  MODE=pr-review make start
start:
	$(COMPOSE) up -d

# Attach to the running container with Claude Code
attach:
	docker exec -it $(IMAGE_NAME) claude

# Show session status
status:
	docker exec $(IMAGE_NAME) /scripts/monitor.sh

# Tail session logs
logs:
	docker exec $(IMAGE_NAME) tail -f /workspace/.claude-session/output.log

# Stop the container
stop:
	$(COMPOSE) down

# Stop and remove volumes
clean:
	$(COMPOSE) down -v
