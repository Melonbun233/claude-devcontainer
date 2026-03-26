# SSH Agent Forwarding

Forward your host SSH agent into the container so passphrase-protected keys work without exposing key files.

## When to Use

| Method | Use when |
|--------|----------|
| **Agent forwarding** (`ssh_agent: true`) | Passphrase-protected keys, macOS Keychain, hardware tokens |
| **Key file mounting** (`mount_ssh: true`) | CI runners, headless servers, unencrypted keys |
| **Both** | Per-server `ssh_key:` uses key files; everything else uses agent |

## Setup

### 1. Enable in workspace.yaml

```yaml
git_config:
  ssh_agent: true
```

### 2. Start your SSH agent (if not already running)

**macOS** (auto-started by launchd — usually already running):
```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

Add to your `~/.ssh/config` for persistence across reboots:
```
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
```

**Linux:**
```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

Add to `~/.bashrc` or `~/.zshrc` to auto-start:
```bash
if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" > /dev/null
fi
```

**Windows (WSL2 only):**
```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```
Native Windows named pipes are not supported. Use WSL2 with Docker Desktop WSL2 backend.

### 3. Verify

```bash
# On host — should show your key(s)
ssh-add -l

# Start container
./claude-sandbox launch myproject

# Inside container — should show same key(s)
ssh-add -l
```

## Using Both Methods

You can enable both `ssh_agent: true` and `mount_ssh: true`. When a server specifies `ssh_key: id_ed25519_work`, that specific key file is used via `IdentityFile` + `IdentitiesOnly`. All other servers use the agent.

## Host Key Verification

The container automatically runs `ssh-keyscan` for each server in `github_servers` at startup, populating `~/.ssh-generated/known_hosts`. You do not need to accept host keys manually.

## Platform Notes

**macOS:** Docker Desktop for Mac runs containers inside a Linux VM. Socket forwarding works because Docker Desktop intercepts the host-side path and creates a proxy socket inside the VM. The proxied socket is mounted as `root:root 0660`; the container automatically fixes permissions (`chmod 666`) at startup so the non-root `claude` user can access it. If agent forwarding fails, test Docker socket forwarding:
```bash
docker run --rm -v ${SSH_AUTH_SOCK}:/run/test.sock alpine ls -la /run/test.sock
```

**Linux:** The host SSH agent socket must be accessible by UID 1000 (the container's `claude` user). If your host UID differs, adjust socket permissions.

**Windows (WSL2):** The SSH agent must run in the same WSL2 distro as Docker. Cross-distro socket access is not supported.

## Q&A / Troubleshooting

| Problem | Solution |
|---------|----------|
| **"Permission denied" with passphrase key** | Use `ssh_agent: true` instead of `mount_ssh: true`. The agent handles passphrase decryption on the host. |
| **"SSH_AUTH_SOCK is not set" on macOS** | macOS auto-starts an agent. Try `ssh-add -l`. If it fails: `eval "$(ssh-agent -s)"` then `ssh-add --apple-use-keychain`. |
| **"SSH_AUTH_SOCK is not set" on Linux** | Add `eval "$(ssh-agent -s)"` to `~/.bashrc`/`~/.zshrc`, then `ssh-add`. |
| **Agent works on host, not in container** | Run `docker run --rm -v ${SSH_AUTH_SOCK}:/run/test.sock alpine ls -la /run/test.sock` to test Docker socket forwarding. On macOS, ensure Docker Desktop resource sharing is enabled. |
| **"Permission denied" on socket (macOS)** | Docker Desktop mounts the proxied socket as `root:root 0660`. The container auto-fixes this at startup. If it still fails, check that the `claude` user has `sudo` access. |
| **"Agent connected but no keys loaded"** | Run `ssh-add` on the host to load your key. Hardware tokens may show no keys until first use. |
| **FIDO2/hardware key needing touch** | Not supported in container (`BatchMode=yes` prevents prompts). Pre-authorize with `ssh-add` (without `-c`) before starting. |
| **"Permission denied" in debug logs despite agent working** | Normal when both `mount_ssh` and `ssh_agent` are enabled. SSH tries key files first (may fail), then agent succeeds. |
| **Need `gh pr` on SSH-only server** | Add `token_env: GH_TOKEN` to the server config. `gh` CLI needs a PAT; git operations use SSH. |
| **Security: can container use my keys?** | Yes. Agent forwarding lets any container process sign with your host keys (same as `ssh -A`). The container already runs with `--dangerously-skip-permissions`. |
