#!/usr/bin/env bash
set -euo pipefail

# ── Git authentication setup ────────────────────────────────────────────────
# Replaces setup-github.sh. Handles both HTTPS (git-credential-store) and
# SSH (key config + keyscan) per server, plus host gitconfig copying.

CONFIG_FILE="/etc/claude-dev/config/workspace.yaml"

# ── Host gitconfig (runs first) ──────────────────────────────────────────────
if [ -f "$HOME/.gitconfig.host" ]; then
  cp "$HOME/.gitconfig.host" "$HOME/.gitconfig"
  echo "  Host gitconfig copied."
else
  echo "  No host gitconfig mounted, skipping."
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "  No workspace.yaml found, skipping git setup."
  exit 0
fi

SERVER_COUNT=$(yq '.github_servers | length' "$CONFIG_FILE" 2>/dev/null || echo 0)

if [ "$SERVER_COUNT" -eq 0 ]; then
  echo "  No github_servers defined, skipping git setup."
  exit 0
fi

# ── Credential store setup (for HTTPS servers) ──────────────────────────────
# We'll set up the credential helper chain once, then write per-server tokens.
HAVE_HTTPS="false"

for i in $(seq 0 $((SERVER_COUNT - 1))); do
  AUTH_METHOD=$(yq ".github_servers[$i].auth_method // \"https\"" "$CONFIG_FILE")
  if [ "$AUTH_METHOD" = "https" ]; then
    HAVE_HTTPS="true"
    break
  fi
done

if [ "$HAVE_HTTPS" = "true" ]; then
  # Configure credential helper chain: store first, gh as fallback
  git config --global credential.helper store
  git config --global --add credential.helper '!gh auth git-credential'
  # Truncate credentials file (tokens are written fresh each start)
  > "$HOME/.git-credentials"
  chmod 600 "$HOME/.git-credentials"
fi

# ── Per-server setup ────────────────────────────────────────────────────────
GH_HOSTS_FILE="$HOME/.config/gh/hosts.yml"
mkdir -p "$(dirname "$GH_HOSTS_FILE")"

for i in $(seq 0 $((SERVER_COUNT - 1))); do
  HOST=$(yq ".github_servers[$i].host" "$CONFIG_FILE")
  AUTH_METHOD=$(yq ".github_servers[$i].auth_method // \"https\"" "$CONFIG_FILE")
  TOKEN_ENV=$(yq ".github_servers[$i].token_env // \"\"" "$CONFIG_FILE")
  SSL_VERIFY=$(yq ".github_servers[$i].ssl_verify" "$CONFIG_FILE")
  if [ "$SSL_VERIFY" != "false" ]; then SSL_VERIFY="true"; fi

  # SSL config (applies to HTTPS git ops and gh CLI API calls)
  if [ "$SSL_VERIFY" = "false" ]; then
    echo "  SSL verification disabled for $HOST"
    git config --global "http.https://$HOST/.sslVerify" false
  fi

  if [ "$AUTH_METHOD" = "https" ]; then
    # ── HTTPS server ──────────────────────────────────────────────────────
    if [ -z "$TOKEN_ENV" ]; then
      echo "  WARN: No token_env defined for HTTPS server $HOST, skipping"
      continue
    fi
    TOKEN="${!TOKEN_ENV:-}"
    if [ -z "$TOKEN" ]; then
      echo "  WARN: \$$TOKEN_ENV is not set, skipping $HOST"
      continue
    fi

    echo "  Configuring HTTPS credentials for $HOST..."

    # Write to git-credential-store
    echo "https://x-access-token:${TOKEN}@${HOST}" >> "$HOME/.git-credentials"

    # Authenticate gh CLI
    if [ "$SSL_VERIFY" = "false" ]; then
      yq -i ".[\"$HOST\"].oauth_token = \"$TOKEN\" | .[\"$HOST\"].git_protocol = \"https\"" "$GH_HOSTS_FILE" 2>/dev/null || {
        cat >> "$GH_HOSTS_FILE" <<EOF
$HOST:
    oauth_token: $TOKEN
    git_protocol: https
EOF
      }
      echo "  Token written directly to gh hosts.yml (SSL verify off)"
    else
      (unset GH_TOKEN GH_ENTERPRISE_TOKEN; echo "$TOKEN" | gh auth login --hostname "$HOST" --with-token 2>&1) || {
        echo "  WARN: Failed to authenticate gh CLI to $HOST"
      }
    fi

  elif [ "$AUTH_METHOD" = "ssh" ]; then
    # ── SSH server ────────────────────────────────────────────────────────
    SSH_KEY=$(yq ".github_servers[$i].ssh_key // \"\"" "$CONFIG_FILE")
    SSH_PORT=$(yq ".github_servers[$i].ssh_port // \"22\"" "$CONFIG_FILE")

    echo "  Configuring SSH for $HOST..."

    # Write SSH config entry if ssh_key is specified
    if [ -n "$SSH_KEY" ]; then
      mkdir -p "$HOME/.ssh"
      # Don't overwrite host-mounted config; append to a generated config
      SSH_CONFIG_FILE="$HOME/.ssh/config"
      # If .ssh is read-only (mounted), write to a separate generated file
      if [ -w "$HOME/.ssh" ]; then
        cat >> "$SSH_CONFIG_FILE" <<EOF

Host $HOST
    HostName $HOST
    Port $SSH_PORT
    IdentityFile /home/claude/.ssh/$SSH_KEY
    IdentitiesOnly yes
EOF
      else
        # .ssh is read-only mount — use GIT_SSH_COMMAND or write to a writable location
        mkdir -p "$HOME/.ssh-generated"
        cat >> "$HOME/.ssh-generated/config" <<EOF

Host $HOST
    HostName $HOST
    Port $SSH_PORT
    IdentityFile /home/claude/.ssh/$SSH_KEY
    IdentitiesOnly yes
EOF
        # Include the generated config
        git config --global core.sshCommand "ssh -F $HOME/.ssh-generated/config -F /home/claude/.ssh/config"
      fi
    fi

    # Add host to known_hosts via ssh-keyscan
    mkdir -p "$HOME/.ssh-generated"
    KNOWN_HOSTS="$HOME/.ssh-generated/known_hosts"
    if [ "$SSH_PORT" != "22" ]; then
      ssh-keyscan -H -p "$SSH_PORT" "$HOST" >> "$KNOWN_HOSTS" 2>/dev/null || {
        echo "  WARN: ssh-keyscan failed for $HOST:$SSH_PORT (clone may prompt for host verification)"
      }
    else
      ssh-keyscan -H "$HOST" >> "$KNOWN_HOSTS" 2>/dev/null || {
        echo "  WARN: ssh-keyscan failed for $HOST (clone may prompt for host verification)"
      }
    fi

    # Point SSH at the generated known_hosts (merge with any mounted known_hosts)
    if [ -f "/home/claude/.ssh/known_hosts" ]; then
      cat "/home/claude/.ssh/known_hosts" >> "$KNOWN_HOSTS" 2>/dev/null || true
    fi

    # Authenticate gh CLI if token is provided (optional for SSH servers)
    if [ -n "$TOKEN_ENV" ]; then
      TOKEN="${!TOKEN_ENV:-}"
      if [ -n "$TOKEN" ]; then
        if [ "$SSL_VERIFY" = "false" ]; then
          yq -i ".[\"$HOST\"].oauth_token = \"$TOKEN\" | .[\"$HOST\"].git_protocol = \"ssh\"" "$GH_HOSTS_FILE" 2>/dev/null || {
            cat >> "$GH_HOSTS_FILE" <<EOF
$HOST:
    oauth_token: $TOKEN
    git_protocol: ssh
EOF
          }
        else
          (unset GH_TOKEN GH_ENTERPRISE_TOKEN; echo "$TOKEN" | gh auth login --hostname "$HOST" --with-token 2>&1) || {
            echo "  WARN: Failed to authenticate gh CLI to $HOST"
          }
        fi
      fi
    fi
  fi
done

# Set GIT_SSH_COMMAND globally if we generated SSH config
if [ -f "$HOME/.ssh-generated/known_hosts" ]; then
  # Build the SSH command with all generated config
  SSH_CMD="ssh -o UserKnownHostsFile=$HOME/.ssh-generated/known_hosts"
  if [ -f "$HOME/.ssh-generated/config" ]; then
    SSH_CMD="$SSH_CMD -F $HOME/.ssh-generated/config"
    # Also include the mounted config if it exists
    if [ -f "/home/claude/.ssh/config" ]; then
      SSH_CMD="$SSH_CMD -F /home/claude/.ssh/config"
    fi
  fi
  git config --global core.sshCommand "$SSH_CMD"
fi

# Do NOT call `gh auth setup-git` here — it would overwrite the credential
# helper chain (store + gh) established above. The gh CLI is already
# authenticated per-server via hosts.yml / gh auth login.

echo "  Git auth complete."
