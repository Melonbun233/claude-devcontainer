#!/usr/bin/env bash
set -euo pipefail

# ── Clone repos from workspace.yaml ─────────────────────────────────────────

CONFIG_FILE="/etc/claude-dev/config/workspace.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "  No workspace.yaml found, skipping repo cloning."
  exit 0
fi

REPO_COUNT=$(yq '.repos | length' "$CONFIG_FILE" 2>/dev/null || echo 0)

if [ "$REPO_COUNT" -eq 0 ]; then
  echo "  No repos defined, skipping."
  exit 0
fi

# Build maps of host → token, identity, and SSL config from github_servers
declare -A HOST_TOKENS HOST_USER_NAMES HOST_USER_EMAILS HOST_SSL_VERIFY HOST_AUTH_METHODS HOST_SSH_PORTS
SERVER_COUNT=$(yq '.github_servers | length' "$CONFIG_FILE" 2>/dev/null || echo 0)
for i in $(seq 0 $((SERVER_COUNT - 1))); do
  HOST=$(yq ".github_servers[$i].host" "$CONFIG_FILE")
  TOKEN_ENV=$(yq ".github_servers[$i].token_env // \"\"" "$CONFIG_FILE")
  TOKEN="${!TOKEN_ENV:-}"
  if [ -n "$TOKEN" ]; then
    HOST_TOKENS["$HOST"]="$TOKEN"
  fi
  USER_NAME=$(yq ".github_servers[$i].user_name // \"\"" "$CONFIG_FILE")
  USER_EMAIL=$(yq ".github_servers[$i].user_email // \"\"" "$CONFIG_FILE")
  if [ -n "$USER_NAME" ]; then HOST_USER_NAMES["$HOST"]="$USER_NAME"; fi
  if [ -n "$USER_EMAIL" ]; then HOST_USER_EMAILS["$HOST"]="$USER_EMAIL"; fi
  SSL_VERIFY=$(yq ".github_servers[$i].ssl_verify" "$CONFIG_FILE")
  if [ "$SSL_VERIFY" != "false" ]; then SSL_VERIFY="true"; fi
  HOST_SSL_VERIFY["$HOST"]="$SSL_VERIFY"
  AUTH_METHOD=$(yq ".github_servers[$i].auth_method // \"https\"" "$CONFIG_FILE")
  HOST_AUTH_METHODS["$HOST"]="$AUTH_METHOD"
  SSH_PORT=$(yq ".github_servers[$i].ssh_port // \"22\"" "$CONFIG_FILE")
  HOST_SSH_PORTS["$HOST"]="$SSH_PORT"
done

CLONE_ERRORS=0

for i in $(seq 0 $((REPO_COUNT - 1))); do
  URL=$(yq ".repos[$i].url" "$CONFIG_FILE")
  BRANCH=$(yq ".repos[$i].branch // \"\"" "$CONFIG_FILE")
  TARGET=$(yq ".repos[$i].target" "$CONFIG_FILE")

  DEST="/workspace/$TARGET"

  # Extract hostname from URL to find the right token/identity
  REPO_HOST=$(echo "$URL" | sed -E 's|https?://([^/]+).*|\1|')

  # Check SSL config for this host
  SSL_VERIFY="${HOST_SSL_VERIFY[$REPO_HOST]:-true}"

  if [ -d "$DEST/.git" ]; then
    echo "  $TARGET: already cloned, pulling latest..."

    # Rewrite stale token-injected remote URLs
    CURRENT_URL=$(git -C "$DEST" remote get-url origin 2>/dev/null || echo "")
    if [[ "$CURRENT_URL" == *"x-access-token:"* ]]; then
      AUTH_METHOD="${HOST_AUTH_METHODS[$REPO_HOST]:-https}"
      if [ "$AUTH_METHOD" = "ssh" ]; then
        REPO_PATH=$(echo "$URL" | sed -E 's|https?://[^/]+/(.*)|\1|; s|\.git$||')
        SSH_PORT="${HOST_SSH_PORTS[$REPO_HOST]:-22}"
        if [ "$SSH_PORT" != "22" ]; then
          NEW_URL="ssh://git@${REPO_HOST}:${SSH_PORT}/${REPO_PATH}.git"
        else
          NEW_URL="git@${REPO_HOST}:${REPO_PATH}.git"
        fi
      else
        NEW_URL="$URL"
      fi
      git -C "$DEST" remote set-url origin "$NEW_URL"
      echo "    Remote URL rewritten (removed embedded credentials)"
    fi

    if [ "$SSL_VERIFY" = "false" ]; then
      GIT_SSL_NO_VERIFY=true git -C "$DEST" pull --ff-only 2>&1 | sed 's/^/    /' || true
    else
      git -C "$DEST" pull --ff-only 2>&1 | sed 's/^/    /' || true
    fi
  else
    AUTH_METHOD="${HOST_AUTH_METHODS[$REPO_HOST]:-https}"
    TOKEN="${HOST_TOKENS[$REPO_HOST]:-}"

    if [ "$AUTH_METHOD" = "ssh" ]; then
      # Convert https://host/org/repo → git@host:org/repo.git
      REPO_PATH=$(echo "$URL" | sed -E 's|https?://[^/]+/(.*)|\1|; s|\.git$||')
      SSH_PORT="${HOST_SSH_PORTS[$REPO_HOST]:-22}"
      if [ "$SSH_PORT" != "22" ]; then
        CLONE_URL="ssh://git@${REPO_HOST}:${SSH_PORT}/${REPO_PATH}.git"
      else
        CLONE_URL="git@${REPO_HOST}:${REPO_PATH}.git"
      fi
    else
      # HTTPS — no token in URL, credential store handles auth
      CLONE_URL="$URL"
    fi

    if [ -n "$BRANCH" ]; then
      echo "  Cloning $URL → $DEST (branch: $BRANCH)..."
    else
      echo "  Cloning $URL → $DEST (all branches)..."
    fi

    # Build clone arguments: use --single-branch when branch is specified
    CLONE_ARGS=()
    if [ -n "$BRANCH" ]; then
      CLONE_ARGS+=(--branch "$BRANCH" --single-branch)
    fi

    if [ "$SSL_VERIFY" = "false" ]; then
      if ! GIT_SSL_NO_VERIFY=true git clone "${CLONE_ARGS[@]}" "$CLONE_URL" "$DEST" 2>&1 | sed 's/^/    /'; then
        echo "  WARN: Failed to clone $URL (continuing with remaining repos)"
        CLONE_ERRORS=$((CLONE_ERRORS + 1))
        continue
      fi
    else
      if ! git clone "${CLONE_ARGS[@]}" "$CLONE_URL" "$DEST" 2>&1 | sed 's/^/    /'; then
        echo "  WARN: Failed to clone $URL (continuing with remaining repos)"
        CLONE_ERRORS=$((CLONE_ERRORS + 1))
        continue
      fi
    fi

    # Mark as safe directory
    git config --global --add safe.directory "$DEST"
  fi

  # Set per-repo git identity based on server config
  GIT_NAME="${HOST_USER_NAMES[$REPO_HOST]:-}"
  GIT_EMAIL="${HOST_USER_EMAILS[$REPO_HOST]:-}"
  if [ -n "$GIT_NAME" ]; then git -C "$DEST" config user.name "$GIT_NAME"; fi
  if [ -n "$GIT_EMAIL" ]; then git -C "$DEST" config user.email "$GIT_EMAIL"; fi
done

if [ "$CLONE_ERRORS" -gt 0 ]; then
  echo "  WARN: $CLONE_ERRORS repo(s) failed to clone. Check logs above."
fi
