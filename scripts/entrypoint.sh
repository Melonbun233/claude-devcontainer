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

echo ":: Cloning repos..."
/scripts/clone-repos.sh || echo "WARN: Repo cloning had issues (continuing)"

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
