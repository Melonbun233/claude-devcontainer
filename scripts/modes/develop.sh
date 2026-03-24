#!/usr/bin/env bash
set -euo pipefail

# ── Develop mode ─────────────────────────────────────────────────────────────
# Keeps the container alive so the user can attach interactively.

SKIP_PERMISSIONS="${SKIP_PERMISSIONS:-false}"
CONTAINER_NAME="${CONTAINER_NAME:-claude-dev}"
SESSION_NAME="${SESSION_NAME:-default}"

echo "╔══════════════════════════════════════════════════╗"
echo "║  DEVELOP MODE — $SESSION_NAME"
echo "╠══════════════════════════════════════════════════╣"
echo "║                                                  ║"
echo "║  Attach to this container:                       ║"
echo "║                                                  ║"
if [ "$SKIP_PERMISSIONS" = "true" ]; then
echo "║    docker exec -it $CONTAINER_NAME \\"
echo "║      claude --dangerously-skip-permissions       ║"
else
echo "║    docker exec -it $CONTAINER_NAME claude"
fi
echo "║                                                  ║"
echo "║  Or use the CLI wrapper:                         ║"
echo "║                                                  ║"
echo "║    ./claude-dev attach $SESSION_NAME"
echo "║                                                  ║"
echo "╚══════════════════════════════════════════════════╝"

# Keep the container alive
exec sleep infinity
