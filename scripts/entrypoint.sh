#!/usr/bin/env bash
set -euo pipefail

# ── Banner ───────────────────────────────────────────────────────────────────
MODE="${MODE:-develop}"
echo "┌──────────────────────────────────────────────┐"
echo "│  claude-devcontainer                         │"
echo "│  Mode: $(printf '%-38s' "$MODE")│"
echo "│  Time: $(printf '%-38s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)")│"
echo "└──────────────────────────────────────────────┘"
echo ""

# ── Validate mode ────────────────────────────────────────────────────────────
case "$MODE" in
  develop|pr-review)
    ;;
  *)
    echo "ERROR: Unknown mode '$MODE'. Supported: develop, pr-review"
    exit 1
    ;;
esac

# ── Setup scripts ────────────────────────────────────────────────────────────

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

echo ":: Setting up GitHub..."
/scripts/setup-github.sh || echo "WARN: GitHub setup had issues (continuing)"

echo ":: Setting up Jira..."
/scripts/setup-jira.sh || echo "WARN: Jira setup had issues (continuing)"

echo ":: Cloning repos..."
/scripts/clone-repos.sh || echo "WARN: Repo cloning had issues (continuing)"

echo ":: Configuring Claude Code..."
/scripts/setup-claude-config.sh || echo "WARN: Claude config setup had issues (continuing)"

# ── Session directory ────────────────────────────────────────────────────────
SESSION_DIR="/workspace/.claude-session"
mkdir -p "$SESSION_DIR"

cat > "$SESSION_DIR/status.json" <<EOF
{
  "mode": "$MODE",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "container_id": "$(hostname)"
}
EOF

touch "$SESSION_DIR/output.log"

echo ""
echo ":: Setup complete. Launching mode: $MODE"
echo ""

# ── Dispatch to mode script ──────────────────────────────────────────────────
exec /scripts/modes/${MODE}.sh
