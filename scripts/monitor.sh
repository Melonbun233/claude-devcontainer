#!/usr/bin/env bash
set -euo pipefail

# ── Session monitor ──────────────────────────────────────────────────────────
# Reads session status and displays it. Called by `claude-sandbox status`.

SESSION_DIR="/workspace/.claude-session"
STATUS_FILE="$SESSION_DIR/status.json"

if [ ! -f "$STATUS_FILE" ]; then
  echo "No active session found."
  exit 0
fi

TYPE=$(jq -r '.type // "unknown"' "$STATUS_FILE")
SESSION=$(jq -r '.session_name // "unknown"' "$STATUS_FILE")
STARTED=$(jq -r '.started_at // "unknown"' "$STATUS_FILE")
CONTAINER=$(jq -r '.container_id // "unknown"' "$STATUS_FILE")

echo "┌──────────────────────────────────────────────┐"
echo "│  Session Status                              │"
echo "├──────────────────────────────────────────────┤"
echo "│  Session:   $(printf '%-33s' "$SESSION")│"
echo "│  Type:      $(printf '%-33s' "$TYPE")│"
echo "│  Started:   $(printf '%-33s' "$STARTED")│"
echo "│  Container: $(printf '%-33s' "$CONTAINER")│"

# PR review status
PR_STATUS=$(jq -r '.pr_review_status // empty' "$STATUS_FILE")
if [ -n "$PR_STATUS" ]; then
  echo "│  PR Review: $(printf '%-33s' "$PR_STATUS")│"
fi

echo "└──────────────────────────────────────────────┘"

# Show recent log lines
LOG_FILE="$SESSION_DIR/output.log"
if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
  echo ""
  echo "── Recent log (last 10 lines) ──"
  tail -10 "$LOG_FILE"
fi

# Show review file if present
REVIEW_FILE="$SESSION_DIR/output.md"
if [ -f "$REVIEW_FILE" ]; then
  echo ""
  echo "── Output available at: $REVIEW_FILE ──"
fi
