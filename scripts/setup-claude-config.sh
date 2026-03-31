#!/usr/bin/env bash
set -euo pipefail

# ── Install Claude Code config: built-in defaults + host overrides ────────────

HOST_CONFIG="/host-config"
CLAUDE_HOME="$HOME/.claude"
BUILTIN_CONFIG="/etc/claude-sandbox/claude-config"

# ── Step 1: Install built-in defaults ─────────────────────────────────────────

# Built-in CLAUDE.md (container environment instructions)
if [ -f "$BUILTIN_CONFIG/CLAUDE.md" ]; then
  cp "$BUILTIN_CONFIG/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md"
  echo "  Installed built-in CLAUDE.md"
fi

# Built-in settings.json (default permissions allowlist)
# Merge with existing settings (entrypoint may have already written host auth/proxy config)
if [ -f "$BUILTIN_CONFIG/settings.json" ]; then
  if [ -f "$CLAUDE_HOME/settings.json" ]; then
    jq -s '.[0] * .[1]' "$CLAUDE_HOME/settings.json" "$BUILTIN_CONFIG/settings.json" \
      > "$CLAUDE_HOME/settings.json.tmp" \
      && mv "$CLAUDE_HOME/settings.json.tmp" "$CLAUDE_HOME/settings.json"
    echo "  Merged built-in settings.json with host settings"
  else
    cp "$BUILTIN_CONFIG/settings.json" "$CLAUDE_HOME/settings.json"
    echo "  Installed built-in settings.json"
  fi
fi

# ── Step 2: Layer host config on top ──────────────────────────────────────────

if [ -d "$HOST_CONFIG" ]; then

  # Append host CLAUDE.md to built-in (preserves container instructions)
  if [ -f "$HOST_CONFIG/CLAUDE.md" ]; then
    printf '\n\n---\n\n' >> "$CLAUDE_HOME/CLAUDE.md"
    cat "$HOST_CONFIG/CLAUDE.md" >> "$CLAUDE_HOME/CLAUDE.md"
    echo "  Appended host CLAUDE.md"
  fi

  # Merge host settings.json (host values override built-in defaults)
  if [ -f "$HOST_CONFIG/settings.json" ]; then
    if [ -f "$CLAUDE_HOME/settings.json" ]; then
      jq -s '.[0] * .[1]' "$CLAUDE_HOME/settings.json" "$HOST_CONFIG/settings.json" \
        > "$CLAUDE_HOME/settings.json.tmp" \
        && mv "$CLAUDE_HOME/settings.json.tmp" "$CLAUDE_HOME/settings.json"
      echo "  Merged host settings.json with built-in defaults"
    else
      cp "$HOST_CONFIG/settings.json" "$CLAUDE_HOME/settings.json"
      echo "  Copied host settings.json"
    fi
  fi

  # Host agents (override built-in if same name)
  if [ -d "$HOST_CONFIG/agents" ]; then
    mkdir -p "$CLAUDE_HOME/agents"
    # Only copy if .md files exist; fail if cp itself fails
    if compgen -G "$HOST_CONFIG/agents/*.md" > /dev/null; then
      cp "$HOST_CONFIG/agents/"*.md "$CLAUDE_HOME/agents/" || {
        echo "  ERROR: Failed to copy host agents"
        exit 1
      }
      echo "  Copied host agents"
    fi
  fi

  # Host skills (override built-in if same name)
  if [ -d "$HOST_CONFIG/skills" ]; then
    if compgen -G "$HOST_CONFIG/skills/*" > /dev/null; then
      cp -r "$HOST_CONFIG/skills/"* "$CLAUDE_HOME/skills/" || {
        echo "  ERROR: Failed to copy host skills"
        exit 1
      }
      echo "  Copied host skills"
    fi
  fi

fi

# ── Step 3: Per-repo config ───────────────────────────────────────────────────

if [ -d "$HOST_CONFIG/repos" ]; then
  for REPO_DIR in "$HOST_CONFIG/repos"/*/; do
    REPO_NAME=$(basename "$REPO_DIR")
    WORKSPACE_REPO="/workspace/$REPO_NAME"

    if [ ! -d "$WORKSPACE_REPO" ]; then
      continue
    fi

    mkdir -p "$WORKSPACE_REPO/.claude"

    # Per-repo CLAUDE.md
    if [ -f "$REPO_DIR/CLAUDE.md" ]; then
      cp "$REPO_DIR/CLAUDE.md" "$WORKSPACE_REPO/.claude/CLAUDE.md"
      echo "  Copied CLAUDE.md for $REPO_NAME"
    fi

    # Per-repo agents
    if [ -d "$REPO_DIR/agents" ]; then
      mkdir -p "$WORKSPACE_REPO/.claude/agents"
      if compgen -G "$REPO_DIR/agents/*.md" > /dev/null; then
        cp "$REPO_DIR/agents/"*.md "$WORKSPACE_REPO/.claude/agents/" || {
          echo "  ERROR: Failed to copy agents for $REPO_NAME"
          exit 1
        }
      fi
    fi

    # Per-repo skills
    if [ -d "$REPO_DIR/skills" ]; then
      mkdir -p "$WORKSPACE_REPO/.claude/skills"
      if compgen -G "$REPO_DIR/skills/*" > /dev/null; then
        cp -r "$REPO_DIR/skills/"* "$WORKSPACE_REPO/.claude/skills/" || {
          echo "  ERROR: Failed to copy skills for $REPO_NAME"
          exit 1
        }
      fi
    fi

    # Per-repo plans
    if [ -d "$REPO_DIR/plans" ]; then
      mkdir -p "$WORKSPACE_REPO/.claude/plans"
      if compgen -G "$REPO_DIR/plans/*.md" > /dev/null; then
        cp "$REPO_DIR/plans/"*.md "$WORKSPACE_REPO/.claude/plans/" || {
          echo "  ERROR: Failed to copy plans for $REPO_NAME"
          exit 1
        }
      fi
    fi
  done
fi

echo "  Claude Code config ready."
