# Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  Host Machine                                                    │
│                                                                  │
│  ~/.claude.json ──────────┐  (API keys, base URL, auth)         │
│  host-config/ ────────────┤  (CLAUDE.md, agents, skills)        │
│  config/sandbox.yaml ─────┤  (GitHub servers, git config)       │
│  .env ────────────────────┤  (tokens)                            │
│                           │                                      │
│  SSH agent ───────────────┤  (via socat relay on macOS)          │
│  --repo=<path> ───────────┤  (copied via docker cp)             │
│  --copy=<src> ────────────┤  (custom files via docker cp)       │
│                           │                                      │
│  ┌────────────────────────▼─────────────────────────────────┐   │
│  │  Docker Container (ubuntu:24.04)                          │   │
│  │                                                           │   │
│  │  ┌─────────────┐  ┌──────────┐                           │   │
│  │  │ Claude Code  │  │ gh CLI   │                           │   │
│  │  │ (interactive │  │ (GitHub  │                           │   │
│  │  │  or -p mode) │  │  ops)    │                           │   │
│  │  └─────────────┘  └──────────┘                           │   │
│  │                                                           │   │
│  │  /workspace/          ← source dirs (docker cp)           │   │
│  │  /workspace/.claude-session/  ← session state             │   │
│  │  ~/.claude/           ← Claude config, agents, skills     │   │
│  │  /run/ssh-agent.sock  ← forwarded SSH agent               │   │
│  └───────────────────────────────────────────────────────────┘   │
│                           │                                      │
│  LLM Proxy ◄──────────────┘  (via host.docker.internal)         │
└─────────────────────────────────────────────────────────────────┘
```

## Entrypoint Flow

```
entrypoint.sh
  ├── setup-certs.sh          # Install custom CA certificates
  ├── Copy + patch host ~/.claude.json (pre-accept /workspace trust)
  ├── Copy + rewrite host ~/.claude/settings.json (localhost → host.docker.internal)
  ├── setup-git.sh            # Configure git auth per server:
  │     ├── HTTPS: credential store + gh CLI
  │     ├── SSH: key config or agent forwarding
  │     ├── ssh-keyscan for known_hosts
  │     └── Symlink known_hosts to ~/.ssh/ for direct ssh access
  ├── [wait for host docker cp]  # CLI copies source dirs + custom files
  ├── Per-repo git setup      # safe.directory, per-repo identity
  ├── setup-claude-config.sh  # Cascade: built-in → host → per-repo config
  ├── Generate server auth docs  # Append configured servers table to ~/.claude/CLAUDE.md
  ├── Create session dir      # /workspace/.claude-session/
  └── Dispatch
      ├── ONE_SHOT_PROMPT set → claude -p, save output, exit
      └── otherwise           → sleep infinity (develop, user attaches)
```

## Volume Mounts

| Host Path | Container Path | Purpose |
|-----------|---------------|---------|
| `~/.claude.json` | `/tmp/.claude.json.host:ro` | Anthropic API config |
| `~/.claude/settings.json` | `/tmp/.claude.settings.host:ro` | Auth tokens, base URL, model config |
| `./host-config/` | `/host-config:ro` | CLAUDE.md, agents, skills |
| `./config/` | `/etc/claude-sandbox/config:ro` | sandbox.yaml |
| `workspace` (volume) | `/workspace` | Source dirs, session state (persistent) |

### Conditional Mounts (via docker-compose.override.yaml)

| Mount | Condition |
|-------|-----------|
| `~/.ssh:/home/claude/.ssh:ro` | `git_config.mount_ssh: true` |
| `~/.gitconfig:/home/claude/.gitconfig.host:ro` | `git_config.mount_gitconfig: true` |
| `~/.claude/ssh-agent.sock:/run/ssh-agent.sock` (macOS) | `git_config.ssh_agent: true` |
| `$SSH_AUTH_SOCK:/run/ssh-agent.sock` (Linux) | `git_config.ssh_agent: true` |

## SSH Agent Forwarding

On macOS, `SSH_AUTH_SOCK` paths rotate after sleep/wake (launchd regenerates them). Docker mounts are baked at container creation, so the old path becomes stale.

The CLI starts a `socat` relay at `~/.claude/ssh-agent.sock` that forwards to the real `$SSH_AUTH_SOCK`. The container mounts the stable relay path. On `start`/`launch`, the relay is restarted to pick up any new socket path — no container recreation needed.

On Linux, `$SSH_AUTH_SOCK` is mounted directly (no relay needed).

See [`SSH-AGENT.md`](SSH-AGENT.md) for detailed setup and troubleshooting.

## Environment Variables

### Credentials (set in `.env`)

| Variable | Required | Description |
|----------|----------|-------------|
| `GH_TOKEN` | For GitHub.com | GitHub.com PAT |
| `GH_ENTERPRISE_TOKEN` | For GHE | Enterprise server PAT (name matches `token_env` in sandbox.yaml) |

### Anthropic / LLM Proxy (optional overrides in `.env`)

By default, config is inherited from the host's `~/.claude.json` and `~/.claude/settings.json`. Set these only to override:

| Variable | Description |
|----------|-------------|
| `ANTHROPIC_BASE_URL` | LLM proxy endpoint |
| `ANTHROPIC_AUTH_TOKEN` | Bearer token for proxy |
| `ANTHROPIC_API_KEY` | Direct API key |

### CLI-driven (set automatically, not in `.env`)

| Variable | Set by | Description |
|----------|--------|-------------|
| `SESSION_NAME` | positional arg | Session name |
| `CONTAINER_NAME` | derived | `claude-sandbox-<session-name>` |
| `ONE_SHOT_PROMPT` | `--prompt=` or `--pr=` | Prompt for one-shot `run` command |
| `DEFAULT_WORKDIR` | `--repo=` | Working directory inside container |
