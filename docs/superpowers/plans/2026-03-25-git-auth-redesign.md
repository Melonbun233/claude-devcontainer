# Git Auth & Cloning Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the HTTPS-only token-injection git auth with per-server SSH/HTTPS choice, native git-credential-store, and opt-in host SSH key/gitconfig mounting.

**Architecture:** The host CLI (`claude-dev`) reads `git_config:` from workspace.yaml and generates a `docker-compose.override.yaml` with conditional volume mounts. Inside the container, a new `setup-git.sh` script (replacing `setup-github.sh`) configures git-credential-store for HTTPS servers and SSH config for SSH servers. `clone-repos.sh` builds clone URLs based on per-server `auth_method`.

**Tech Stack:** Bash, Docker Compose, yq, git, openssh-client, gh CLI

**Spec:** `docs/superpowers/specs/2026-03-25-git-auth-redesign-design.md`

---

### Task 1: Update workspace.yaml.example with new schema

**Files:**
- Modify: `config/workspace.yaml.example`

- [ ] **Step 1: Add `git_config:` section and per-server auth fields**

Add the new `git_config:` top-level section before `github_servers:`, and add `auth_method`, `ssh_key`, `ssh_port` fields to the server examples:

```yaml
# ── Git Configuration (optional) ─────────────────────────────────────────────
# Control how the container accesses git. Both options are opt-in.
# git_config:
#   mount_ssh: true           # mount host ~/.ssh/ read-only into container
#   mount_gitconfig: true     # mount host ~/.gitconfig read-only into container

# ── GitHub Servers ────────────────────────────────────────────────────────────
# Each entry defines a hostname and how to authenticate.
#
# auth_method: https (default) — uses PAT via git-credential-store
# auth_method: ssh — uses SSH keys (requires git_config.mount_ssh: true)
#
# SSL options (for GitHub Enterprise with corporate/self-signed certs):
#   ssl_verify: false     — skip TLS certificate verification
#   ca_cert: corp-ca.pem  — use a custom CA cert from ./certs/ directory
github_servers:
  - host: github.com
    auth_method: https         # ssh | https (default: https)
    token_env: GH_TOKEN        # required for auth_method: https
    # user_name: Jane Doe
    # user_email: jane@personal.com

  # SSH example for enterprise server:
  # - host: github.enterprise.corp.com
  #   auth_method: ssh
  #   ssh_key: id_ed25519_work   # optional: filename in ~/.ssh/
  #   ssh_port: 22               # optional: non-standard SSH port
  #   token_env: GH_ENTERPRISE_TOKEN  # optional for SSH: enables gh CLI
  #   user_name: Jane Doe
  #   user_email: jane.doe@corp.com
  #   ssl_verify: false
```

- [ ] **Step 2: Update the repos section comments**

Update the repos section header comment to mention that repo URLs are always written as HTTPS — the clone script converts to SSH automatically when the server uses `auth_method: ssh`:

```yaml
# ── Repos to Clone ──────────────────────────────────────────────────────────
# Each repo is cloned to /workspace/<target> on container start.
# The URL host must match one of the github_servers above for auth.
# Always use HTTPS URLs here — SSH conversion is automatic when
# the matching server has auth_method: ssh.
```

- [ ] **Step 3: Commit**

```bash
git add config/workspace.yaml.example
git commit -m "config: add git_config section and per-server auth_method to workspace.yaml.example"
```

---

### Task 2: Add `docker-compose.override.yaml` to `.gitignore`

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add the override file entry**

Add under the `# Docker` section:

```
docker-compose.override.yaml
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore docker-compose.override.yaml (generated at runtime)"
```

---

### Task 3: Add override file generation and validation to `claude-dev`

**Files:**
- Modify: `claude-dev`

This is the largest task. The CLI must parse `git_config:` from workspace.yaml, validate SSH requirements, and generate `docker-compose.override.yaml` before starting containers.

- [ ] **Step 1: Add a `generate_compose_override` function**

Add this function after the `container_running()` helper (after line 274), before the `# ── Commands` section:

```bash
# ── Generate docker-compose.override.yaml from workspace.yaml git_config ────
generate_compose_override() {
  local CONFIG_FILE="$SCRIPT_DIR/config/workspace.yaml"
  local OVERRIDE_FILE="$SCRIPT_DIR/docker-compose.override.yaml"

  # If no workspace.yaml, remove any stale override and return
  if [ ! -f "$CONFIG_FILE" ]; then
    rm -f "$OVERRIDE_FILE"
    return 0
  fi

  local MOUNT_SSH
  local MOUNT_GITCONFIG
  MOUNT_SSH=$(yq '.git_config.mount_ssh // false' "$CONFIG_FILE" 2>/dev/null)
  MOUNT_GITCONFIG=$(yq '.git_config.mount_gitconfig // false' "$CONFIG_FILE" 2>/dev/null)

  # Validate: any server with auth_method: ssh requires mount_ssh: true
  local SERVER_COUNT
  SERVER_COUNT=$(yq '.github_servers | length' "$CONFIG_FILE" 2>/dev/null || echo 0)
  for i in $(seq 0 $((SERVER_COUNT - 1))); do
    local AUTH_METHOD HOST
    AUTH_METHOD=$(yq ".github_servers[$i].auth_method // \"https\"" "$CONFIG_FILE")
    HOST=$(yq ".github_servers[$i].host" "$CONFIG_FILE")

    if [ "$AUTH_METHOD" = "ssh" ] && [ "$MOUNT_SSH" != "true" ]; then
      echo "ERROR: Server '$HOST' uses auth_method: ssh but git_config.mount_ssh is not true."
      echo ""
      echo "  Add this to config/workspace.yaml:"
      echo "    git_config:"
      echo "      mount_ssh: true"
      return 1
    fi

    # Validate ssh_key file exists on host
    if [ "$AUTH_METHOD" = "ssh" ]; then
      local SSH_KEY
      SSH_KEY=$(yq ".github_servers[$i].ssh_key // \"\"" "$CONFIG_FILE")
      if [ -n "$SSH_KEY" ] && [ ! -f "$HOME/.ssh/$SSH_KEY" ]; then
        echo "ERROR: SSH key '$HOME/.ssh/$SSH_KEY' not found (server '$HOST')."
        return 1
      fi
    fi
  done

  # Validate host paths exist
  if [ "$MOUNT_SSH" = "true" ] && [ ! -d "$HOME/.ssh" ]; then
    echo "ERROR: git_config.mount_ssh is true but $HOME/.ssh/ does not exist."
    return 1
  fi

  if [ "$MOUNT_GITCONFIG" = "true" ] && [ ! -f "$HOME/.gitconfig" ]; then
    echo "WARN: git_config.mount_gitconfig is true but $HOME/.gitconfig does not exist. Skipping gitconfig mount."
    MOUNT_GITCONFIG="false"
  fi

  # Generate override file only if mounts are needed
  if [ "$MOUNT_SSH" = "true" ] || [ "$MOUNT_GITCONFIG" = "true" ]; then
    {
      echo "# Generated by claude-dev — do not edit"
      echo "services:"
      echo "  claude-dev:"
      echo "    volumes:"
      if [ "$MOUNT_SSH" = "true" ]; then
        echo "      - ${HOME}/.ssh:/home/claude/.ssh:ro"
      fi
      if [ "$MOUNT_GITCONFIG" = "true" ]; then
        echo "      - ${HOME}/.gitconfig:/home/claude/.gitconfig.host:ro"
      fi
    } > "$OVERRIDE_FILE"
  else
    # No mounts needed — remove stale override
    rm -f "$OVERRIDE_FILE"
  fi
}
```

- [ ] **Step 2: Call `generate_compose_override` before every `$COMPOSE up`**

There are three places where `$COMPOSE up` is called. Add the call before each one.

In the `launch` command, before `$COMPOSE up -d` (line 345):

```bash
    else
      echo ":: Creating session '$SESSION_NAME'..."
      generate_compose_override || exit 1
      $COMPOSE up -d
    fi
```

In the `start` command, before `$COMPOSE up -d` (line 428):

```bash
    else
      generate_compose_override || exit 1
      $COMPOSE up -d
    fi
```

In the `run` command, before `$COMPOSE up --abort-on-container-exit` (line 490):

```bash
    generate_compose_override || exit 1

    # Run in foreground, blocks until container exits
    $COMPOSE up --abort-on-container-exit
```

- [ ] **Step 3: Verify the function works with no workspace.yaml**

```bash
# Remove override if it exists, run with no config
rm -f docker-compose.override.yaml
mv config/workspace.yaml config/workspace.yaml.bak 2>/dev/null || true
# The function should complete silently
bash -c 'source claude-dev; generate_compose_override && echo OK'
# Verify no override file was created
ls -la docker-compose.override.yaml 2>&1  # should say "No such file"
mv config/workspace.yaml.bak config/workspace.yaml 2>/dev/null || true
```

Expected: "OK" printed, no override file created.

Note: the above is a rough verification approach. Since `claude-dev` uses `set -euo pipefail` and is structured as a command dispatcher, you may need to extract the function for isolated testing or test via a real `./claude-dev launch` with a test session.

- [ ] **Step 4: Commit**

```bash
git add claude-dev
git commit -m "feat: generate docker-compose.override.yaml for conditional SSH/gitconfig mounts"
```

---

### Task 4: Create `setup-git.sh` (replace `setup-github.sh`)

**Files:**
- Create: `scripts/setup-git.sh`
- Delete: `scripts/setup-github.sh`

- [ ] **Step 1: Create `scripts/setup-git.sh` with full implementation**

```bash
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
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/setup-git.sh
```

- [ ] **Step 3: Delete `scripts/setup-github.sh`**

```bash
rm scripts/setup-github.sh
```

- [ ] **Step 4: Commit (together with Task 5 entrypoint change)**

Tasks 4 and 5 must be committed together — the entrypoint references `setup-git.sh`, so deleting `setup-github.sh` without updating the entrypoint would break the build.

```bash
git add scripts/setup-git.sh scripts/entrypoint.sh
git rm scripts/setup-github.sh
git commit -m "feat: replace setup-github.sh with setup-git.sh (SSH + HTTPS credential store)"
```

---

### Task 5: Update `entrypoint.sh` to call `setup-git.sh`

**Files:**
- Modify: `scripts/entrypoint.sh`

**Note:** This task is committed together with Task 4. Complete the entrypoint edit before committing.

- [ ] **Step 1: Replace the setup-github.sh call**

Change line 57 from:

```bash
echo ":: Setting up GitHub..."
/scripts/setup-github.sh || echo "WARN: GitHub setup had issues (continuing)"
```

to:

```bash
echo ":: Setting up Git..."
/scripts/setup-git.sh || echo "WARN: Git setup had issues (continuing)"
```

- [ ] **Step 2: Already committed in Task 4 Step 4**

No separate commit needed — this was staged and committed with Task 4.

---

### Task 6: Update `clone-repos.sh` for per-server auth_method

**Files:**
- Modify: `scripts/clone-repos.sh`

- [ ] **Step 1: Add `HOST_AUTH_METHODS` to the server maps**

After the existing `HOST_SSL_VERIFY` map declaration (around line 21), add `HOST_AUTH_METHODS`:

```bash
declare -A HOST_TOKENS HOST_USER_NAMES HOST_USER_EMAILS HOST_SSL_VERIFY HOST_AUTH_METHODS HOST_SSH_PORTS
```

Inside the server loop, after the `HOST_SSL_VERIFY` assignment, add:

```bash
  AUTH_METHOD=$(yq ".github_servers[$i].auth_method // \"https\"" "$CONFIG_FILE")
  HOST_AUTH_METHODS["$HOST"]="$AUTH_METHOD"
  SSH_PORT=$(yq ".github_servers[$i].ssh_port // \"22\"" "$CONFIG_FILE")
  HOST_SSH_PORTS["$HOST"]="$SSH_PORT"
```

- [ ] **Step 2: Replace token-injected URL construction with auth_method-based logic**

Replace the clone URL construction block (around lines 62-69) with:

```bash
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
```

- [ ] **Step 3: Add remote URL rewrite for existing cloned repos**

In the "already cloned" branch (around line 54-60), add URL rewriting before the pull. Replace:

```bash
  if [ -d "$DEST/.git" ]; then
    echo "  $TARGET: already cloned, pulling latest..."
    if [ "$SSL_VERIFY" = "false" ]; then
      GIT_SSL_NO_VERIFY=true git -C "$DEST" pull --ff-only 2>&1 | sed 's/^/    /' || true
    else
      git -C "$DEST" pull --ff-only 2>&1 | sed 's/^/    /' || true
    fi
```

with:

```bash
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
```

- [ ] **Step 4: Commit**

```bash
git add scripts/clone-repos.sh
git commit -m "feat: auth_method-based clone URLs, rewrite stale token-injected remotes"
```

---

### Task 7: Update `.env.example` with SSH comment

**Files:**
- Modify: `.env.example`

- [ ] **Step 1: Add comment about SSH servers**

Update the GitHub section comment:

```bash
# ── GitHub ────────────────────────────────────────────────────────────────────
# Tokens for each GitHub server. Variable names must match token_env in
# workspace.yaml — use any name you want (e.g., GH_MY_SERVER_TOKEN).
# Tokens are required for servers with auth_method: https.
# For servers with auth_method: ssh, tokens are optional (enables gh CLI only).
GH_TOKEN=
# GH_ENTERPRISE_TOKEN=
```

- [ ] **Step 2: Commit**

```bash
git add .env.example
git commit -m "docs: clarify token requirements for SSH vs HTTPS servers in .env.example"
```

---

### Task 8: Update documentation

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update ARCHITECTURE.md**

Update the entrypoint flow section to reference `setup-git.sh` instead of `setup-github.sh`. Update the "Multi-Server GitHub Auth" section to describe the new dual-auth approach (SSH + HTTPS credential store).

Key changes:
- Step 5 in the entrypoint flow: `setup-git.sh` — configure git auth (SSH keys, credential store, gh CLI) per server
- Replace the "Multi-Server GitHub Auth" section content to describe `auth_method: ssh|https`, credential store, SSH config generation, and `docker-compose.override.yaml` for conditional mounts

- [ ] **Step 2: Update CLAUDE.md**

In the "Key Files" table, update the `setup-github.sh` entry to `setup-git.sh` with updated description. Add a mention of `docker-compose.override.yaml` (generated, gitignored).

In the "Container Startup Flow" section, update step 5 to reference `setup-git.sh`.

- [ ] **Step 3: Commit**

```bash
git add docs/ARCHITECTURE.md CLAUDE.md
git commit -m "docs: update ARCHITECTURE.md and CLAUDE.md for git auth redesign"
```

---

### Task 9: Manual verification

No files changed — this is a testing task.

- [ ] **Step 1: Build the image**

```bash
./claude-dev build
```

Expected: Build completes successfully.

- [ ] **Step 2: Test backward compatibility (no git_config section)**

Use a workspace.yaml with no `git_config:` section and an HTTPS server with a valid token:

```bash
./claude-dev launch test-https --rm
```

Inside the container, verify:
- `cat ~/.git-credentials` shows the token entry
- `git config --global credential.helper` shows `store` and `!gh auth git-credential`
- `git remote get-url origin` in a cloned repo shows clean HTTPS URL (no embedded token)
- `git pull` works

- [ ] **Step 3: Test SSH auth (if SSH keys available)**

Update workspace.yaml to add `git_config: mount_ssh: true` and set a server to `auth_method: ssh`:

```bash
./claude-dev launch test-ssh --rm
```

Inside the container, verify:
- `ls -la ~/.ssh/` shows mounted keys (read-only)
- `git remote get-url origin` shows `git@host:org/repo.git`
- `git pull` works via SSH

- [ ] **Step 4: Test validation errors**

Set a server to `auth_method: ssh` without `mount_ssh: true`:

```bash
./claude-dev launch test-fail --rm
```

Expected: CLI aborts with clear error message before starting the container.

- [ ] **Step 5: Test session restart migration**

Start a session with old config (token-injected URLs exist in .git/config), then restart with new config. Verify remote URLs are rewritten.
