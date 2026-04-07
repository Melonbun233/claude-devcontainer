# Deprecate SSH Agent Forwarding, Standardize on HTTPS+PAT

**Date:** 2026-04-06
**Status:** Approved
**Supersedes:** 2026-03-26-ssh-agent-forwarding-design.md

## Problem

SSH agent forwarding on macOS is unreliable. macOS launchd rotates `SSH_AUTH_SOCK` paths after sleep/wake, which breaks the socat relay that bridges the host agent into the Docker container. When this happens, the container loses git push/pull/clone access and the only recovery is restarting the session.

The socat relay was a workaround for this platform behavior, but it adds fragile infrastructure: a background process that can die, a PID file, socket permission fixes inside the container, and macOS-specific code paths. All of this complexity exists to forward SSH keys that could be replaced by a static PAT in `.env`.

## Decision

Remove SSH agent forwarding entirely. Standardize on HTTPS+PAT as the primary auth method. Keep `mount_ssh` (static key file mount) as a secondary option for users with unencrypted SSH keys.

### Why Not Fix the Relay?

A self-healing relay (watchdog, health checks, auto-restart) was considered. It adds complexity to solve a platform instability that HTTPS avoids entirely. Since SSH agent forwarding was used for convenience (not policy), eliminating it is simpler and more reliable.

### Token Expiration

Classic GitHub PATs can be created with no expiration. They persist until manually revoked. Fine-grained PATs have enforced expiration (max 1 year on github.com; varies on GHE). For users of this sandbox, classic PATs with no expiration are recommended — they never require re-auth.

## What Changes

### Remove

- `git_config.ssh_agent` configuration option
- `ensure_ssh_relay()` function — socat relay lifecycle management
- `maybe_start_ssh_relay()` function — conditional relay startup on session restart
- SSH agent socket mount in `generate_compose_override()` — no more `SSH_AUTH_SOCK` injection
- socat relay PID tracking (`~/.claude/ssh-agent-relay.pid`, `~/.claude/ssh-agent.sock`)
- Container-side agent socket permission fix (`sudo chmod 666` on mounted socket)
- Container-side `ssh-add -l` agent verification block
- `socat` from Dockerfile apt-get and from prerequisites documentation

### Keep

- `git_config.mount_ssh` — mount host `~/.ssh/` read-only for key-file SSH auth
- SSH config generation for `mount_ssh` servers (per-server `IdentityFile`, `ssh_key`, `ssh_port`)
- `ssh-keyscan` for SSH host key verification
- `core.sshCommand` composition (used when `mount_ssh` is true)
- All HTTPS token auth (git-credential-store, `gh auth login`) — unchanged

### Modify

- `generate_compose_override()` validation: SSH servers require `mount_ssh: true` (no `ssh_agent` alternative)
- `sandbox.yaml.example`: remove `ssh_agent` references, update comments
- README.md and CLAUDE.md: remove socat/agent forwarding sections, simplify SSH docs to "mount key files"
- Error messages: detect `ssh_agent: true` in existing config and emit a clear migration error

## Migration Strategy

When the CLI detects `ssh_agent: true` in `sandbox.yaml`:

1. Emit a **hard error** (not warning) with migration instructions:
   - Passphrase-free SSH keys → switch to `mount_ssh: true`
   - Passphrase-protected keys or simplicity → switch to `auth_method: https` with a PAT
2. Do not silently ignore the old config — prevents confusing auth failures
3. No automatic migration — user edits `sandbox.yaml` once

### New Default Config

```yaml
git_config:
  mount_ssh: false          # mount host ~/.ssh/ read-only (for unencrypted SSH keys)
  mount_gitconfig: true     # mount host ~/.gitconfig
```

## Files Changed

| File | Change |
|------|--------|
| `claude-sandbox` | Remove `ensure_ssh_relay()`, `maybe_start_ssh_relay()`, SSH agent socket logic from `generate_compose_override()`, agent relay calls from start/launch/restart paths. Add `ssh_agent: true` deprecation error. |
| `scripts/setup-git.sh` | Remove agent socket chmod fix, `ssh-add -l` agent verification block. Keep `mount_ssh` key-file setup and `ssh-keyscan`. |
| `config/sandbox.yaml` | Remove `ssh_agent: true` line. |
| `config/sandbox.yaml.example` | Remove `ssh_agent` option and comments. |
| `Dockerfile` | Remove `socat` from apt-get install. Keep `openssh-client`. |
| `README.md` | Remove SSH agent forwarding/socat sections. Simplify SSH auth to "mount key files." Remove socat from prerequisites. |
| `CLAUDE.md` | Remove SSH agent/socat references from architecture docs. |
| `docs/superpowers/specs/2026-03-26-ssh-agent-forwarding-design.md` | Delete — superseded by this document. |

## Testing

No automated test suite exists. Verify by:

1. **Build image:** `./claude-sandbox build` — confirm socat no longer installed
2. **HTTPS auth:** Start a session with `auth_method: https` servers, confirm git clone/push and `gh` CLI work
3. **mount_ssh auth:** Start a session with `mount_ssh: true` and unencrypted SSH keys, confirm git clone/push works
4. **Migration error:** Add `ssh_agent: true` to sandbox.yaml, confirm the CLI emits a clear error and stops
5. **No SSH agent references:** Grep codebase for `ssh_agent`, `ssh-agent`, `socat`, `RELAY` — confirm no stale references
