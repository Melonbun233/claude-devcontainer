#!/usr/bin/env bash
set -euo pipefail

# ── Banner ───────────────────────────────────────────────────────────────────
SESSION_NAME="${SESSION_NAME:-default}"
echo "┌──────────────────────────────────────────────┐"
echo "│  claude-sandbox                              │"
echo "│  Session: $(printf '%-34s' "$SESSION_NAME")│"
echo "│  Time:    $(printf '%-34s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)")│"
echo "└──────────────────────────────────────────────┘"
echo ""

# Clear stale readiness sentinel from a previous run
rm -f /workspace/.claude-session/ready

# ── Setup scripts ────────────────────────────────────────────────────────────

echo ":: Installing custom CA certificates..."
/scripts/setup-certs.sh || echo "WARN: CA cert setup had issues (continuing)"

# Copy host Anthropic config and pre-accept /workspace trust.
# Host file is mounted read-only at /tmp/.claude.json.host; we copy and patch it.
echo ":: Setting up Anthropic config..."
CLAUDE_JSON="$HOME/.claude.json"
HOST_CLAUDE_JSON="/tmp/.claude.json.host"

if [ -f "$HOST_CLAUDE_JSON" ]; then
  jq '.projects["/workspace"] //= {} | .projects["/workspace"].hasTrustDialogAccepted = true | .hasCompletedOnboarding = true' \
    "$HOST_CLAUDE_JSON" > "$CLAUDE_JSON"
  echo "  Host config copied with /workspace trust pre-accepted."
else
  echo '{"hasCompletedOnboarding":true,"projects":{"/workspace":{"hasTrustDialogAccepted":true}}}' | jq . > "$CLAUDE_JSON"
  echo "  No host config found. Created minimal config with /workspace trust."
fi

# Copy host Claude settings.json (contains auth, base URL, model config).
# Rewrite localhost → host.docker.internal so the container can reach host proxy.
echo ":: Setting up Claude settings..."
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
HOST_SETTINGS="/tmp/.claude.settings.host"

if [ -f "$HOST_SETTINGS" ]; then
  jq '
    if .env.ANTHROPIC_BASE_URL then
      .env.ANTHROPIC_BASE_URL = (.env.ANTHROPIC_BASE_URL
        | gsub("localhost"; "host.docker.internal")
        | gsub("127\\.0\\.0\\.1"; "host.docker.internal"))
    else . end
  ' "$HOST_SETTINGS" > "$CLAUDE_SETTINGS"
  BASE_URL=$(jq -r '.env.ANTHROPIC_BASE_URL // "not set"' "$CLAUDE_SETTINGS")
  echo "  Host settings copied. API base URL: $BASE_URL"
else
  echo "  No host settings.json found."
fi

echo ":: Setting up Git..."
/scripts/setup-git.sh || echo "WARN: Git setup had issues (continuing)"

echo ":: Waiting for source directories..."
mkdir -p /workspace/.claude-session
touch /workspace/.claude-session/copy-ready

# Wait for host CLI to finish docker cp
COPY_TIMEOUT=300
for i in $(seq 1 "$COPY_TIMEOUT"); do
  if [ -f /workspace/.claude-session/copy-done ]; then
    break
  fi
  sleep 1
done

if [ -f /workspace/.claude-session/copy-done ]; then
  echo "  Source directories copied to /workspace/"
else
  echo "  WARN: Source directory copy did not complete within ${COPY_TIMEOUT}s"
fi

echo ":: Setting up repo identities..."
CONFIG_FILE=""
if [ -f "/etc/claude-sandbox/config/sandbox.yaml" ]; then
  CONFIG_FILE="/etc/claude-sandbox/config/sandbox.yaml"
elif [ -f "/etc/claude-sandbox/config/workspace.yaml" ]; then
  CONFIG_FILE="/etc/claude-sandbox/config/workspace.yaml"
fi

if [ -n "$CONFIG_FILE" ] && command -v yq &>/dev/null; then
  # Build server identity maps
  declare -A HOST_USER_NAMES HOST_USER_EMAILS
  SERVER_COUNT=$(yq '.github_servers | length' "$CONFIG_FILE" 2>/dev/null || echo 0)
  for i in $(seq 0 $((SERVER_COUNT - 1))); do
    host=$(yq ".github_servers[$i].host" "$CONFIG_FILE")
    uname=$(yq ".github_servers[$i].user_name // \"\"" "$CONFIG_FILE")
    email=$(yq ".github_servers[$i].user_email // \"\"" "$CONFIG_FILE")
    [ -n "$host" ] && HOST_USER_NAMES["$host"]="$uname"
    [ -n "$host" ] && HOST_USER_EMAILS["$host"]="$email"
  done

  for repo in /workspace/*/; do
    [ -d "$repo/.git" ] || continue
    repo_path=$(realpath "$repo")

    # Mark as safe directory
    git config --global --add safe.directory "$repo_path"

    # Match remote URL to a github_server for identity
    remote_url=$(git -C "$repo_path" remote get-url origin 2>/dev/null || true)
    if [ -n "$remote_url" ]; then
      host=$(echo "$remote_url" | sed -E \
        -e 's|^https?://([^/]+).*|\1|' \
        -e 's|^[^@]+@([^:]+):.*|\1|')
      user_name="${HOST_USER_NAMES[$host]:-}"
      user_email="${HOST_USER_EMAILS[$host]:-}"
      [ -n "$user_name" ] && git -C "$repo_path" config user.name "$user_name"
      [ -n "$user_email" ] && git -C "$repo_path" config user.email "$user_email"
    fi

    echo "  $repo_path configured"
  done
else
  # No config or no yq — still mark directories as safe
  for repo in /workspace/*/; do
    [ -d "$repo/.git" ] || continue
    git config --global --add safe.directory "$(realpath "$repo")"
  done
fi

echo ":: Configuring Claude Code..."
/scripts/setup-claude-config.sh || echo "WARN: Claude config setup had issues (continuing)"

# ── Session directory ────────────────────────────────────────────────────────
SESSION_DIR="/workspace/.claude-session"
mkdir -p "$SESSION_DIR"

# Determine session type
if [ -n "${ONE_SHOT_PROMPT:-}" ]; then
  SESSION_TYPE="one-shot"
else
  SESSION_TYPE="develop"
fi

cat > "$SESSION_DIR/status.json" <<EOF
{
  "session_name": "$SESSION_NAME",
  "type": "$SESSION_TYPE",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "container_id": "$(hostname)"
}
EOF

touch "$SESSION_DIR/output.log"

echo ""
echo ":: Setup complete."
echo ""

# Signal readiness to the host CLI
touch /workspace/.claude-session/ready

# ── Dispatch ──────────────────────────────────────────────────────────────
if [ -n "${ONE_SHOT_PROMPT:-}" ]; then
  echo ":: Running one-shot prompt..."
  # Set working directory for Claude context
  if [ -n "${DEFAULT_WORKDIR:-}" ] && [ -d "${DEFAULT_WORKDIR}" ]; then
    cd "$DEFAULT_WORKDIR"
  fi
  # One-shot always requires --dangerously-skip-permissions (non-interactive claude -p)
  OUTPUT=$(claude -p --dangerously-skip-permissions "$ONE_SHOT_PROMPT" 2>&1) || {
    echo "ERROR: Claude execution failed"
    echo "$OUTPUT"
    exit 1
  }
  echo "$OUTPUT" > "$SESSION_DIR/output.md"
  echo "$OUTPUT"
  echo ":: Output saved to $SESSION_DIR/output.md"
else
  echo ":: Develop mode — waiting for attach..."
  exec sleep infinity
fi
