#!/usr/bin/env bash
set -euo pipefail

# ── GitHub authentication setup ──────────────────────────────────────────────
# Reads github_servers from workspace.yaml, authenticates gh CLI per server.

CONFIG_FILE="/etc/claude-dev/config/workspace.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "  No workspace.yaml found, skipping GitHub setup."
  exit 0
fi

SERVER_COUNT=$(yq '.github_servers | length' "$CONFIG_FILE" 2>/dev/null || echo 0)

if [ "$SERVER_COUNT" -eq 0 ]; then
  echo "  No github_servers defined, skipping GitHub setup."
  exit 0
fi

for i in $(seq 0 $((SERVER_COUNT - 1))); do
  HOST=$(yq ".github_servers[$i].host" "$CONFIG_FILE")
  TOKEN_ENV=$(yq ".github_servers[$i].token_env" "$CONFIG_FILE")

  # Resolve the env var value
  TOKEN="${!TOKEN_ENV:-}"

  if [ -z "$TOKEN" ]; then
    echo "  WARN: \$$TOKEN_ENV is not set, skipping $HOST"
    continue
  fi

  echo "  Authenticating to $HOST..."
  echo "$TOKEN" | gh auth login --hostname "$HOST" --with-token 2>&1 || {
    echo "  WARN: Failed to authenticate to $HOST"
    continue
  }
done

# Configure git credential helper for all authenticated hosts
gh auth setup-git 2>/dev/null || true

echo "  GitHub auth status:"
gh auth status 2>&1 | sed 's/^/    /' || true
