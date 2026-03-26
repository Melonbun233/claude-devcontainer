# Git Auth & Cloning Redesign

**Date:** 2026-03-25
**Status:** Approved
**Scope:** Git authentication and repo cloning only. Jira, config cascade, session lifecycle, Anthropic config unchanged.

## Problem

The current git auth setup has two concrete failures:

1. **`gh` auth ≠ `git` auth.** `setup-github.sh` authenticates the `gh` CLI and runs `gh auth setup-git` as a credential helper. Raw `git push/pull/fetch` inside the container doesn't reliably pick up credentials, especially for enterprise servers where `gh`'s credential helper behaves differently.

2. **HTTPS-only with token injection.** `clone-repos.sh` injects PATs directly into clone URLs (`https://x-access-token:TOKEN@host/...`). This breaks for private Git servers that only support SSH or require different auth mechanisms. The injected-URL pattern also means credentials are visible in `.git/config` remote URLs.

**Root cause:** The design assumes all servers use HTTPS with PATs and routes everything through `gh`. It provides no SSH path and no native git credential support.

## Requirements

- Per-server auth method choice (`ssh` or `https`) in workspace.yaml
- SSH support: opt-in mount of host `~/.ssh/` (read-only), with optional per-server `ssh_key:` override
- HTTPS fix: write PATs to `git-credential-store` so native git commands work; chain `gh` as secondary credential helper
- Git config: opt-in mount of host `~/.gitconfig` (read-only), per-server identity overrides win
- All configuration in workspace.yaml (new `git_config:` top-level section)
- Fully backward compatible — existing workspace.yaml files work without changes

## Approach: CLI-Driven Mounts (Approach B)

The host CLI (`claude-dev`) reads workspace.yaml and passes conditional volume mounts via `-v` flags. Container scripts handle credential setup. No compose file templating needed.

## Design

### 1. workspace.yaml Schema Changes

New top-level `git_config:` section, plus per-server `auth_method` and `ssh_key`:

```yaml
# ── Git Configuration ─────────────────────────────────────────
git_config:
  mount_ssh: true           # opt-in: mount host ~/.ssh/ read-only
  mount_gitconfig: true     # opt-in: mount host ~/.gitconfig read-only

# ── GitHub Servers ────────────────────────────────────────────
github_servers:
  - host: github.com
    auth_method: https       # ssh | https (default: https)
    token_env: GH_TOKEN      # required for auth_method: https
    # user_name: Jane Doe
    # user_email: jane@personal.com

  - host: github.enterprise.corp.com
    auth_method: ssh          # use SSH keys for this server
    ssh_key: ~/.ssh/id_ed25519_work   # optional: specific key for this server
    user_name: Jane Doe
    user_email: jane.doe@corp.com
    ssl_verify: false
```

**Rules:**
- `git_config:` section is optional. If absent, no SSH/gitconfig mounts.
- `auth_method` defaults to `https` (backward compatible).
- `token_env` required when `auth_method: https`.
- `ssh_key` optional — if omitted, SSH uses default key selection from `~/.ssh/config` or ssh-agent.
- `mount_ssh: true` is required for any server using `auth_method: ssh` (validated at startup).

### 2. CLI Changes (`claude-dev`)

Before calling `docker compose up`, the CLI parses `git_config:` from `config/workspace.yaml`:

- If `mount_ssh: true`: add `-v ${HOME}/.ssh:/home/claude/.ssh:ro`
- If `mount_gitconfig: true`: add `-v ${HOME}/.gitconfig:/home/claude/.gitconfig.host:ro` (staged as `.host`, copied by entrypoint so per-server overrides can be layered)
- Mounts passed via `--volume` flags on the `docker compose` command

**Validation:** If any server has `auth_method: ssh` but `mount_ssh` is not `true`, warn and abort before starting the container.

All existing CLI commands unchanged. Session naming, volume management, compose project naming unchanged.

### 3. Container Script: `setup-git.sh` (replaces `setup-github.sh`)

#### HTTPS servers (`auth_method: https`):
1. Write PAT to `~/.git-credentials`: `https://x-access-token:{TOKEN}@{HOST}`
2. Configure `git config --global credential.helper store`
3. Chain `gh` as secondary: `git config --global --add credential.helper '!gh auth git-credential'`
4. Authenticate `gh` CLI per server (for `gh pr`, `gh issue`, etc.)

#### SSH servers (`auth_method: ssh`):
1. If `ssh_key` specified: write `~/.ssh/config` entry (`Host`, `HostName`, `IdentityFile`, `IdentitiesOnly yes`)
2. If no `ssh_key`: rely on default key selection from mounted `~/.ssh/config` or ssh-agent
3. Add host to `~/.ssh/known_hosts` via `ssh-keyscan`
4. If the server also has a `token_env`: authenticate `gh` CLI for that host (so `gh pr` works even over SSH)

#### Host gitconfig:
- If `~/.gitconfig.host` exists (mounted): copy to `~/.gitconfig`, then layer per-server identity overrides per-repo
- If not mounted: no global gitconfig, per-server identity still works

#### SSL config:
Unchanged — `ssl_verify: false` sets `git http.<host>.sslVerify false`, `ca_cert` handled by `setup-certs.sh`.

### 4. Clone Script Changes (`clone-repos.sh`)

URL construction switches based on `auth_method`:

| `auth_method` | Clone URL |
|---------------|-----------|
| `https` | `https://github.com/org/repo.git` (no token in URL) |
| `ssh` | `git@github.com:org/repo.git` |

**Key changes from today:**
- No more token injection into URLs. HTTPS clones rely on `git-credential-store`. Git asks the credential helper, gets the PAT, authenticates.
- SSH URL conversion: repo URL in workspace.yaml is always `https://host/org/repo`. Clone script converts to `git@host:org/repo.git` when `auth_method: ssh`.
- Subsequent `git pull/push/fetch` works natively — credentials are configured globally.

**Unchanged:** per-repo branch scoping, per-repo git identity, error handling, `safe.directory` marking, already-cloned repos get `git pull --ff-only`.

### 5. Backward Compatibility

Fully backward compatible. No breaking changes.

- `git_config:` section optional. If absent, same behavior as today.
- `auth_method` defaults to `https`. Existing workspace.yaml files work unchanged.
- Only behavioral difference for existing HTTPS users: credential-store instead of token-injected URLs. Same result, better plumbing.

**Migration for SSH users:**
1. Add `git_config: mount_ssh: true`
2. Set `auth_method: ssh` on desired servers
3. Optionally add `ssh_key:` per server
4. Restart session (no rebuild needed)

## Files Changed

| File | Change |
|------|--------|
| `config/workspace.yaml.example` | Add `git_config:` section, `auth_method`/`ssh_key` examples |
| `claude-dev` | Parse `git_config`, add conditional `-v` mounts, validation |
| `scripts/setup-github.sh` → `scripts/setup-git.sh` | Rename, add SSH setup + git-credential-store |
| `scripts/clone-repos.sh` | URL construction based on `auth_method` |
| `scripts/entrypoint.sh` | Call `setup-git.sh` instead of `setup-github.sh` |
| `docker-compose.yaml` | No changes |
| `.env.example` | No changes |
