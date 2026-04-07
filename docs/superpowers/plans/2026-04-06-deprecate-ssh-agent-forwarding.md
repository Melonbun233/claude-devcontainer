# Deprecate SSH Agent Forwarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove SSH agent forwarding (socat relay) from claude-sandbox, standardize on HTTPS+PAT as the primary auth method, and keep `mount_ssh` (static key files) as a secondary option.

**Architecture:** The CLI's `ensure_ssh_relay()` / `maybe_start_ssh_relay()` functions, agent socket mount generation, and container-side agent verification are deleted. Validation in `generate_compose_override()` is simplified: SSH servers require `mount_ssh: true` (no `ssh_agent` alternative). A migration error is added for users with `ssh_agent: true` in their config.

**Tech Stack:** Bash (CLI + container scripts), Docker Compose, YAML config

---

### Task 1: Add migration error for `ssh_agent: true` in CLI

**Files:**
- Modify: `claude-sandbox:586-665` (inside `generate_compose_override()`)

This task adds a hard error when the CLI detects the deprecated `ssh_agent: true` config, so users get a clear migration message instead of silent breakage.

- [ ] **Step 1: Add deprecation check at the start of `generate_compose_override()`**

In `claude-sandbox`, after the config file is found and `yq` is validated (around line 611 where `SSH_AGENT` is read), add a deprecation error block. Replace the line that reads `SSH_AGENT` and everything that uses it.

Find the block at lines 609-611:
```bash
    MOUNT_SSH=$(yq '.git_config.mount_ssh // false' "$CONFIG_FILE" 2>/dev/null)
    MOUNT_GITCONFIG=$(yq '.git_config.mount_gitconfig // false' "$CONFIG_FILE" 2>/dev/null)
    SSH_AGENT=$(yq '.git_config.ssh_agent // false' "$CONFIG_FILE" 2>/dev/null)
```

Replace with:
```bash
    MOUNT_SSH=$(yq '.git_config.mount_ssh // false' "$CONFIG_FILE" 2>/dev/null)
    MOUNT_GITCONFIG=$(yq '.git_config.mount_gitconfig // false' "$CONFIG_FILE" 2>/dev/null)

    # Detect deprecated ssh_agent config
    local DEPRECATED_SSH_AGENT
    DEPRECATED_SSH_AGENT=$(yq '.git_config.ssh_agent // false' "$CONFIG_FILE" 2>/dev/null)
    if [ "$DEPRECATED_SSH_AGENT" = "true" ]; then
      echo "ERROR: git_config.ssh_agent has been removed."
      echo ""
      echo "  SSH agent forwarding was unreliable on macOS (socket rotation after"
      echo "  sleep/wake). Use one of these alternatives instead:"
      echo ""
      echo "  Option 1 — HTTPS + PAT (recommended):"
      echo "    Remove ssh_agent: true from config/sandbox.yaml"
      echo "    Set auth_method: https and token_env for each server"
      echo ""
      echo "  Option 2 — SSH key files (unencrypted keys only):"
      echo "    Replace ssh_agent: true with mount_ssh: true"
      echo "    Keys in ~/.ssh/ are mounted read-only into the container"
      echo ""
      echo "  See README.md for details."
      return 1
    fi
```

- [ ] **Step 2: Verify the error triggers**

Temporarily add `ssh_agent: true` to the worktree's sandbox.yaml (it won't be committed) and run:

```bash
cd /Users/I547584/workspace/claude-sandbox/.claude/worktrees/deprecate-ssh-agent
# Create a test config
mkdir -p config
cat > config/sandbox.yaml <<'EOF'
git_config:
  ssh_agent: true
  mount_ssh: false
  mount_gitconfig: true
github_servers:
  - host: github.com
    auth_method: https
    token_env: GH_TOKEN
EOF
```

Then run:
```bash
bash -c 'source claude-sandbox; generate_compose_override' 2>&1 || true
```

Expected: The error message about `ssh_agent` being removed is printed and the function exits with code 1.

Clean up the test config after verification.

- [ ] **Step 3: Commit**

```bash
git add claude-sandbox
GIT_COMMITTER_NAME="Melonbun233" GIT_COMMITTER_EMAIL="zeng_zh@foxmail.com" git commit --author="Melonbun233 <zeng_zh@foxmail.com>" -m "$(cat <<'EOF'
feat: add migration error for deprecated ssh_agent config

Users with ssh_agent: true in their sandbox.yaml now get a clear error
with migration instructions instead of silent breakage.
EOF
)"
```

---

### Task 2: Remove SSH agent relay functions from CLI

**Files:**
- Modify: `claude-sandbox:505-583` (remove `ensure_ssh_relay` and `maybe_start_ssh_relay`)
- Modify: `claude-sandbox:928-931` (launch restart path — remove `maybe_start_ssh_relay` call)
- Modify: `claude-sandbox:1023-1026` (start restart path — remove `maybe_start_ssh_relay` call)

- [ ] **Step 1: Delete `ensure_ssh_relay()` function**

Remove lines 505-565 entirely (from `# ── Ensure socat SSH agent relay` through the closing `}`):

```bash
# ── Ensure socat SSH agent relay is running (macOS only) ─────────────────────
# Sets AGENT_SOCK to the relay path on macOS, or SSH_AUTH_SOCK on Linux.
# On Linux this is a no-op (AGENT_SOCK = SSH_AUTH_SOCK).
ensure_ssh_relay() {
  ...entire function...
}
```

- [ ] **Step 2: Delete `maybe_start_ssh_relay()` function**

Remove lines 567-583 entirely (from `# ── Start SSH relay` through the closing `}`):

```bash
# ── Start SSH relay if ssh_agent is enabled in config ────────────────────────
# Call this before docker start on the restart path (where generate_compose_override is skipped).
maybe_start_ssh_relay() {
  ...entire function...
}
```

- [ ] **Step 3: Remove `maybe_start_ssh_relay` call from launch restart path**

In the `launch` case (around line 930), find:
```bash
      echo ":: Restarting stopped session '$SESSION_NAME'..."
      maybe_start_ssh_relay || exit 1
      docker start "$CONTAINER_NAME"
```

Replace with:
```bash
      echo ":: Restarting stopped session '$SESSION_NAME'..."
      docker start "$CONTAINER_NAME"
```

- [ ] **Step 4: Remove `maybe_start_ssh_relay` call from start restart path**

In the `start` case (around line 1025), find:
```bash
      echo ":: Restarting stopped session '$SESSION_NAME'..."
      maybe_start_ssh_relay || exit 1
      docker start "$CONTAINER_NAME"
```

Replace with:
```bash
      echo ":: Restarting stopped session '$SESSION_NAME'..."
      docker start "$CONTAINER_NAME"
```

- [ ] **Step 5: Commit**

```bash
git add claude-sandbox
GIT_COMMITTER_NAME="Melonbun233" GIT_COMMITTER_EMAIL="zeng_zh@foxmail.com" git commit --author="Melonbun233 <zeng_zh@foxmail.com>" -m "$(cat <<'EOF'
refactor: remove SSH agent relay functions from CLI

Delete ensure_ssh_relay() and maybe_start_ssh_relay(), and their call
sites in the launch/start restart paths. The socat relay was fragile on
macOS due to SSH_AUTH_SOCK rotation after sleep/wake.
EOF
)"
```

---

### Task 3: Remove SSH agent logic from `generate_compose_override()`

**Files:**
- Modify: `claude-sandbox` — the `generate_compose_override()` function

After Task 1 added the deprecation error and Task 2 removed the relay functions, this task cleans up the remaining `SSH_AGENT` variable usage throughout `generate_compose_override()`.

- [ ] **Step 1: Remove `SSH_AGENT` variable declaration**

Find (near the top of the function, around line 599):
```bash
  local MOUNT_SSH="false"
  local MOUNT_GITCONFIG="false"
  local SSH_AGENT="false"
```

Replace with:
```bash
  local MOUNT_SSH="false"
  local MOUNT_GITCONFIG="false"
```

- [ ] **Step 2: Update SSH server validation**

Find the validation block (around line 621):
```bash
    if [ "$AUTH_METHOD" = "ssh" ] && [ "$MOUNT_SSH" != "true" ] && [ "$SSH_AGENT" != "true" ]; then
      echo "ERROR: Server '$HOST' uses auth_method: ssh but neither git_config.mount_ssh nor git_config.ssh_agent is enabled."
      echo ""
      echo "  Add one of these to config/sandbox.yaml:"
      echo "    git_config:"
      echo "      ssh_agent: true      # recommended: forward host SSH agent"
      echo "      mount_ssh: true      # alternative: mount key files"
      return 1
    fi
```

Replace with:
```bash
    if [ "$AUTH_METHOD" = "ssh" ] && [ "$MOUNT_SSH" != "true" ]; then
      echo "ERROR: Server '$HOST' uses auth_method: ssh but git_config.mount_ssh is not enabled."
      echo ""
      echo "  Add this to config/sandbox.yaml:"
      echo "    git_config:"
      echo "      mount_ssh: true      # mount host ~/.ssh/ read-only"
      return 1
    fi
```

- [ ] **Step 3: Remove `ensure_ssh_relay` call from override generation**

Find (around line 660-663):
```bash
  # Start SSH agent relay (macOS) or set AGENT_SOCK directly (Linux)
  if [ "$SSH_AGENT" = "true" ]; then
    ensure_ssh_relay || return 1
  fi
```

Delete these 4 lines entirely.

- [ ] **Step 4: Remove SSH_AGENT from override need check**

Find (around line 669):
```bash
  if [ "$MOUNT_SSH" = "true" ] || [ "$MOUNT_GITCONFIG" = "true" ] || [ "$SSH_AGENT" = "true" ]; then
```

Replace with:
```bash
  if [ "$MOUNT_SSH" = "true" ] || [ "$MOUNT_GITCONFIG" = "true" ]; then
```

- [ ] **Step 5: Remove SSH agent volume and env from override file generation**

Find (around line 682):
```bash
      if [ "$MOUNT_SSH" = "true" ] || [ "$MOUNT_GITCONFIG" = "true" ] || [ "$SSH_AGENT" = "true" ]; then
        echo "    volumes:"
        if [ "$MOUNT_SSH" = "true" ]; then
          echo "      - ${HOME}/.ssh:/home/claude/.ssh:ro"
        fi
        if [ "$MOUNT_GITCONFIG" = "true" ]; then
          echo "      - ${HOME}/.gitconfig:/home/claude/.gitconfig.host:ro"
        fi
        if [ "$SSH_AGENT" = "true" ]; then
          echo "      - \"${AGENT_SOCK}:/run/ssh-agent.sock\""
          NEED_ENV="true"
        fi
      fi
      if [ "$NEED_ENV" = "true" ] || [ -n "${DEFAULT_WORKDIR:-}" ]; then
        echo "    environment:"
        if [ "$NEED_ENV" = "true" ]; then
          echo "      - SSH_AUTH_SOCK=/run/ssh-agent.sock"
        fi
```

Replace with:
```bash
      if [ "$MOUNT_SSH" = "true" ] || [ "$MOUNT_GITCONFIG" = "true" ]; then
        echo "    volumes:"
        if [ "$MOUNT_SSH" = "true" ]; then
          echo "      - ${HOME}/.ssh:/home/claude/.ssh:ro"
        fi
        if [ "$MOUNT_GITCONFIG" = "true" ]; then
          echo "      - ${HOME}/.gitconfig:/home/claude/.gitconfig.host:ro"
        fi
      fi
      if [ -n "${DEFAULT_WORKDIR:-}" ]; then
        echo "    environment:"
```

Also remove the now-unused `NEED_ENV` variable. Find:
```bash
    local NEED_ENV="false"
```
Delete this line.

And remove the closing bracket for the old `NEED_ENV` check. Find:
```bash
        if [ -n "${DEFAULT_WORKDIR:-}" ]; then
          echo "      - DEFAULT_WORKDIR=${DEFAULT_WORKDIR}"
        fi
      fi
```

This stays as-is (it's the DEFAULT_WORKDIR block) but make sure the surrounding braces close correctly.

- [ ] **Step 6: Verify the CLI parses without errors**

```bash
bash -n claude-sandbox
```

Expected: No output (syntax is valid).

- [ ] **Step 7: Commit**

```bash
git add claude-sandbox
GIT_COMMITTER_NAME="Melonbun233" GIT_COMMITTER_EMAIL="zeng_zh@foxmail.com" git commit --author="Melonbun233 <zeng_zh@foxmail.com>" -m "$(cat <<'EOF'
refactor: remove SSH agent logic from generate_compose_override

Remove SSH_AGENT variable, agent socket volume mount, SSH_AUTH_SOCK env
injection, and NEED_ENV tracking. SSH servers now require mount_ssh only.
EOF
)"
```

---

### Task 4: Remove SSH agent verification from setup-git.sh

**Files:**
- Modify: `scripts/setup-git.sh:224-250`

- [ ] **Step 1: Delete the SSH agent verification block**

Remove lines 224-250 entirely (from `# ── SSH agent verification` to the closing `fi`):

```bash
# ── SSH agent verification ──────────────────────────────────────────────────
if [ -n "${SSH_AUTH_SOCK:-}" ]; then
  echo "  Verifying SSH agent..."

  # Fix socket permissions — Docker Desktop (macOS) mounts the proxied socket
  # as root:root with 0660, which the non-root claude user cannot access.
  if [ -S "$SSH_AUTH_SOCK" ] && [ ! -r "$SSH_AUTH_SOCK" ]; then
    sudo chmod 666 "$SSH_AUTH_SOCK" 2>/dev/null || true
  fi

  set +e
  ssh-add -l > /dev/null 2>&1
  AGENT_EXIT=$?
  set -e

  if [ "$AGENT_EXIT" -eq 0 ]; then
    KEY_COUNT=$(ssh-add -l 2>/dev/null | wc -l | tr -d ' ')
    echo "  SSH agent forwarded successfully ($KEY_COUNT keys available)"
  elif [ "$AGENT_EXIT" -eq 1 ]; then
    echo "  WARN: SSH agent connected but no keys loaded."
    echo "  If clone fails, run 'ssh-add' on the host to load your keys."
  else
    echo "  ERROR: SSH_AUTH_SOCK is set but agent is not responding."
    echo "  Check that your host SSH agent is running: ssh-add -l"
    exit 1
  fi
fi
```

- [ ] **Step 2: Verify setup-git.sh parses without errors**

```bash
bash -n scripts/setup-git.sh
```

Expected: No output (syntax is valid).

- [ ] **Step 3: Commit**

```bash
git add scripts/setup-git.sh
GIT_COMMITTER_NAME="Melonbun233" GIT_COMMITTER_EMAIL="zeng_zh@foxmail.com" git commit --author="Melonbun233 <zeng_zh@foxmail.com>" -m "$(cat <<'EOF'
refactor: remove SSH agent verification from setup-git.sh

Delete the SSH_AUTH_SOCK verification block (socket permission fix,
ssh-add -l check, key count reporting). No longer needed since SSH agent
forwarding has been removed.
EOF
)"
```

---

### Task 5: Remove SSH agent reference from entrypoint.sh

**Files:**
- Modify: `scripts/entrypoint.sh:131-170` (server documentation generation)

The entrypoint generates a "Configured Git Servers" table in CLAUDE.md. It references `SSH_AUTH_SOCK` to show "agent forwarding" in the notes column. Update this.

- [ ] **Step 1: Remove SSH_AUTH_SOCK check from server documentation**

Find (around lines 134-135):
```bash
    SSH_AGENT_ON="false"
    [ -n "${SSH_AUTH_SOCK:-}" ] && SSH_AGENT_ON="true"
```

Delete these 2 lines.

- [ ] **Step 2: Update notes generation for SSH servers**

Find (around lines 148-156):
```bash
        if [ "$auth" = "ssh" ]; then
          clone="git@${host}:org/repo.git"
          if [ -n "$ssh_key" ]; then
            notes="key: $ssh_key"
          elif [ "$SSH_AGENT_ON" = "true" ]; then
            notes="agent forwarding"
          else
            notes=""
          fi
```

Replace with:
```bash
        if [ "$auth" = "ssh" ]; then
          clone="git@${host}:org/repo.git"
          if [ -n "$ssh_key" ]; then
            notes="key: $ssh_key"
          else
            notes="key-file mount"
          fi
```

- [ ] **Step 3: Verify entrypoint.sh parses without errors**

```bash
bash -n scripts/entrypoint.sh
```

Expected: No output (syntax is valid).

- [ ] **Step 4: Commit**

```bash
git add scripts/entrypoint.sh
GIT_COMMITTER_NAME="Melonbun233" GIT_COMMITTER_EMAIL="zeng_zh@foxmail.com" git commit --author="Melonbun233 <zeng_zh@foxmail.com>" -m "$(cat <<'EOF'
refactor: remove SSH agent reference from entrypoint server docs

Update the git server documentation table to no longer check
SSH_AUTH_SOCK or display 'agent forwarding' in notes.
EOF
)"
```

---

### Task 6: Update config files

**Files:**
- Modify: `config/sandbox.yaml.example`

The example config template needs `ssh_agent` removed and comments updated.

- [ ] **Step 1: Update sandbox.yaml.example**

Find the git_config comment block at the top (lines 1-6):
```yaml
# ── Git Configuration (optional) ─────────────────────────────────────────────
# Control how the container accesses git. All options are opt-in.
# git_config:
#   ssh_agent: true           # forward host SSH agent socket (for passphrase-protected keys)
#   mount_ssh: true           # mount host ~/.ssh/ read-only (for unencrypted key files)
#   mount_gitconfig: true     # mount host ~/.gitconfig read-only into container
```

Replace with:
```yaml
# ── Git Configuration (optional) ─────────────────────────────────────────────
# Control how the container accesses git. Both options are opt-in.
# git_config:
#   mount_ssh: true           # mount host ~/.ssh/ read-only (for unencrypted SSH key files)
#   mount_gitconfig: true     # mount host ~/.gitconfig read-only into container
```

- [ ] **Step 2: Update the SSH example comment**

Find the SSH example comments (around lines 24-35):
```yaml
  # SSH example for enterprise server:
  # When using auth_method: ssh, enable either ssh_agent: true (recommended)
  # or mount_ssh: true in git_config above.
  # - host: github.enterprise.corp.com
  #   auth_method: ssh
  #   ssh_key: id_ed25519_work   # optional: filename in ~/.ssh/ (requires mount_ssh)
```

Replace with:
```yaml
  # SSH example for enterprise server:
  # When using auth_method: ssh, enable mount_ssh: true in git_config above.
  # - host: github.enterprise.corp.com
  #   auth_method: ssh
  #   ssh_key: id_ed25519_work   # optional: filename in ~/.ssh/ (requires mount_ssh)
```

- [ ] **Step 3: Commit**

```bash
git add config/sandbox.yaml.example
GIT_COMMITTER_NAME="Melonbun233" GIT_COMMITTER_EMAIL="zeng_zh@foxmail.com" git commit --author="Melonbun233 <zeng_zh@foxmail.com>" -m "$(cat <<'EOF'
docs: remove ssh_agent from sandbox.yaml.example

Update the example config to reflect that SSH agent forwarding has been
removed. SSH auth now requires mount_ssh: true only.
EOF
)"
```

---

### Task 7: Remove socat from Dockerfile

**Files:**
- Modify: `Dockerfile:6-17`

The Dockerfile does not currently install `socat` (it was a host-side dependency only, installed via `brew install socat`). Verify this and note it in a commit if no change is needed.

- [ ] **Step 1: Verify socat is not in Dockerfile**

Search the Dockerfile for `socat`:
```bash
grep -n socat Dockerfile
```

Expected: No matches. `socat` was a host-side macOS dependency, not installed in the container image.

- [ ] **Step 2: No change needed — skip this task**

If grep confirms no socat in Dockerfile, no commit is needed. Move to next task.

---

### Task 8: Update documentation (README.md)

**Files:**
- Modify: `README.md`

Remove SSH agent forwarding sections, socat from prerequisites, and simplify git config docs.

- [ ] **Step 1: Remove socat from prerequisites**

Find (around line 11):
```markdown
- `socat` for SSH agent forwarding on macOS (`brew install socat`) — not needed on Linux
```

Delete this line entirely.

- [ ] **Step 2: Replace the Git Configuration section**

Find the entire Git Configuration section (around lines 138-177, from `### Git Configuration` to the end of the SSH troubleshooting `</details>` block):

```markdown
### Git Configuration

Control how the container accesses git via the `git_config` section in `config/sandbox.yaml`:

```yaml
git_config:
  ssh_agent: true           # forward host SSH agent socket (recommended for SSH)
  mount_ssh: true           # mount host ~/.ssh/ read-only (for unencrypted key files)
  mount_gitconfig: true     # mount host ~/.gitconfig read-only
```

| Method | Use when |
|--------|----------|
| **Agent forwarding** (`ssh_agent: true`) | Passphrase-protected keys, macOS Keychain, hardware tokens |
| **Key file mounting** (`mount_ssh: true`) | CI runners, headless servers, unencrypted keys |

**SSH agent setup:**
...entire agent setup section...

| Platform | Notes |
...platform notes table...

<details>
<summary>SSH troubleshooting</summary>
...entire troubleshooting table...
</details>
```

Replace with:

```markdown
### Git Configuration

Control how the container accesses git via the `git_config` section in `config/sandbox.yaml`:

```yaml
git_config:
  mount_ssh: true           # mount host ~/.ssh/ read-only (for unencrypted key files)
  mount_gitconfig: true     # mount host ~/.gitconfig read-only
```

| Method | Use when |
|--------|----------|
| **HTTPS + PAT** (`auth_method: https`) | Recommended for all servers. Set `token_env` to the name of the env var holding the PAT. |
| **SSH key files** (`mount_ssh: true`) | CI runners, headless servers with unencrypted SSH keys in `~/.ssh/`. |

**SSH key file setup:**

1. Enable in `config/sandbox.yaml`: set `mount_ssh: true`
2. Ensure your SSH keys do not require a passphrase (agent forwarding is not supported)
3. Optionally specify `ssh_key: <filename>` per server to route to a specific key

Host keys are auto-populated via `ssh-keyscan` at startup — no manual host key acceptance needed.

<details>
<summary>SSH troubleshooting</summary>

| Problem | Solution |
|---------|----------|
| "Permission denied" with passphrase key | Use `auth_method: https` with a PAT instead. `mount_ssh` only works with unencrypted keys. |
| "Bad configuration option: usekeychain" | macOS-specific SSH config options are automatically stripped inside the container. If issues persist, use `auth_method: https`. |

</details>
```

- [ ] **Step 3: Commit**

```bash
git add README.md
GIT_COMMITTER_NAME="Melonbun233" GIT_COMMITTER_EMAIL="zeng_zh@foxmail.com" git commit --author="Melonbun233 <zeng_zh@foxmail.com>" -m "$(cat <<'EOF'
docs: remove SSH agent forwarding from README

Remove socat from prerequisites, replace SSH agent setup section with
simplified SSH key file + HTTPS+PAT documentation.
EOF
)"
```

---

### Task 9: Update documentation (CLAUDE.md)

**Files:**
- Modify: `CLAUDE.md`

Remove SSH agent/socat references from the architecture documentation.

- [ ] **Step 1: Update Multi-Server GitHub Auth section**

Find the Multi-Server GitHub Auth section (around lines 59-65):
```markdown
### Multi-Server GitHub Auth

`sandbox.yaml` defines a `github_servers[]` list. Each entry has `host`, `token_env` (env var name holding the PAT), `auth_method: ssh|https`, optional `user_name`/`user_email`, and optional SSL config (`ssl_verify: false` or `ca_cert: path`).

- **HTTPS**: tokens written to git-credential-store; `gh` CLI configured as a secondary credential helper per server.
- **SSH (agent forwarding)**: opt-in via `git_config.ssh_agent: true`. Forwards the host SSH agent socket into the container — recommended for passphrase-protected keys and macOS Keychain. On macOS, the CLI starts a `socat` relay at `~/.claude/ssh-agent.sock` to survive SSH_AUTH_SOCK path rotation after sleep/wake; requires `socat` (`brew install socat`).
- **SSH (key files)**: opt-in via `git_config.mount_ssh: true`. Mounts host `~/.ssh` read-only; SSH config generated per server with `IdentityFile` routing. Keys must not require a passphrase.

`docker-compose.override.yaml` is generated at runtime by the CLI for conditional SSH/gitconfig/agent volume mounts and `DEFAULT_WORKDIR` (gitignored). Source directories are copied via `docker cp` after container start — no bind mounts. Per-server identity and SSL config are handled the same way regardless of auth method.
```

Replace with:
```markdown
### Multi-Server GitHub Auth

`sandbox.yaml` defines a `github_servers[]` list. Each entry has `host`, `token_env` (env var name holding the PAT), `auth_method: ssh|https`, optional `user_name`/`user_email`, and optional SSL config (`ssl_verify: false` or `ca_cert: path`).

- **HTTPS** (recommended): tokens written to git-credential-store; `gh` CLI configured as a secondary credential helper per server.
- **SSH (key files)**: opt-in via `git_config.mount_ssh: true`. Mounts host `~/.ssh` read-only; SSH config generated per server with `IdentityFile` routing. Keys must not require a passphrase.

`docker-compose.override.yaml` is generated at runtime by the CLI for conditional SSH/gitconfig volume mounts and `DEFAULT_WORKDIR` (gitignored). Source directories are copied via `docker cp` after container start — no bind mounts. Per-server identity and SSL config are handled the same way regardless of auth method.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
GIT_COMMITTER_NAME="Melonbun233" GIT_COMMITTER_EMAIL="zeng_zh@foxmail.com" git commit --author="Melonbun233 <zeng_zh@foxmail.com>" -m "$(cat <<'EOF'
docs: remove SSH agent forwarding from CLAUDE.md

Remove agent forwarding and socat relay references from the Multi-Server
GitHub Auth architecture section.
EOF
)"
```

---

### Task 10: Delete superseded design doc

**Files:**
- Delete: `docs/superpowers/specs/2026-03-26-ssh-agent-forwarding-design.md`

- [ ] **Step 1: Delete the old design spec**

```bash
git rm docs/superpowers/specs/2026-03-26-ssh-agent-forwarding-design.md
```

- [ ] **Step 2: Commit**

```bash
GIT_COMMITTER_NAME="Melonbun233" GIT_COMMITTER_EMAIL="zeng_zh@foxmail.com" git commit --author="Melonbun233 <zeng_zh@foxmail.com>" -m "$(cat <<'EOF'
chore: delete superseded SSH agent forwarding design doc

This spec is superseded by 2026-04-06-deprecate-ssh-agent-forwarding-design.md.
EOF
)"
```

---

### Task 11: Final verification — grep for stale references

**Files:** All files in the repository

This is a sweep to ensure no stale references to SSH agent forwarding remain.

- [ ] **Step 1: Grep for stale references**

```bash
grep -rn 'ssh_agent\|ssh-agent\|socat\|RELAY_SOCK\|RELAY_PID\|AGENT_SOCK\|SSH_AUTH_SOCK' \
  --include='*.sh' --include='*.yaml' --include='*.md' \
  --exclude-dir='.git' --exclude-dir='docs/superpowers/specs' \
  .
```

Expected: No matches. If any matches are found in files we modified, they need to be cleaned up. Matches in the spec directory are expected (our new design doc references these terms in context).

- [ ] **Step 2: Verify the CLI script parses cleanly**

```bash
bash -n claude-sandbox
bash -n scripts/setup-git.sh
bash -n scripts/entrypoint.sh
```

Expected: No output for all three (all scripts have valid syntax).

- [ ] **Step 3: Build the Docker image**

```bash
./claude-sandbox build
```

Expected: Build succeeds. The image no longer includes socat (it never did — socat was host-only).

- [ ] **Step 4: Commit any cleanup fixes (if needed)**

If Step 1 found stale references that needed fixing:

```bash
git add -A
GIT_COMMITTER_NAME="Melonbun233" GIT_COMMITTER_EMAIL="zeng_zh@foxmail.com" git commit --author="Melonbun233 <zeng_zh@foxmail.com>" -m "$(cat <<'EOF'
chore: clean up remaining SSH agent forwarding references
EOF
)"
```

If no fixes were needed, skip this step.
