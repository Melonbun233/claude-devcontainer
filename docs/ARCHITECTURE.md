# Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  Host Machine                                                    │
│                                                                  │
│  ~/.claude.json ──────────┐  (API keys, base URL, auth)         │
│  host-config/ ────────────┤  (CLAUDE.md, agents, skills)        │
│  config/workspace.yaml ───┤  (repos, GitHub servers)            │
│  .env ────────────────────┤  (tokens)                            │
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
│  │  /workspace/          ← cloned repos                      │   │
│  │  /workspace/.claude-session/  ← session state             │   │
│  │  ~/.claude/           ← Claude config, agents, skills     │   │
│  └───────────────────────────────────────────────────────────┘   │
│                           │                                      │
│  LLM Proxy ◄──────────────┘  (via host.docker.internal)         │
└─────────────────────────────────────────────────────────────────┘
```

## Entrypoint Flow

```
entrypoint.sh
  ├── setup-certs.sh        # Install custom CA certificates
  ├── setup-git.sh          # Configure git auth (SSH keys, credential store, gh CLI) per server
  ├── clone-repos.sh        # Clone repos from workspace.yaml
  ├── setup-claude-config.sh # Install built-in config, layer host overrides
  ├── create session dir    # /workspace/.claude-session/
  └── dispatch
      ├── ONE_SHOT_PROMPT set → claude -p, save output, exit
      └── otherwise           → sleep infinity (develop, user attaches)
```

## Volume Mounts

| Host Path | Container Path | Purpose |
|-----------|---------------|---------|
| `~/.claude.json` | `/home/claude/.claude.json:ro` | Anthropic API config |
| `~/.claude/settings.json` | `/tmp/.claude.settings.host:ro` | Auth tokens, base URL, model config |
| `./host-config/` | `/host-config:ro` | CLAUDE.md, agents, skills |
| `./config/` | `/etc/claude-sandbox/config:ro` | workspace.yaml |
| `workspace` (volume) | `/workspace` | Cloned repos (persistent) |

## Environment Variables

### Credentials (set in `.env`)

| Variable | Required | Description |
|----------|----------|-------------|
| `GH_TOKEN` | For GitHub.com | GitHub.com PAT |
| `GH_ENTERPRISE_TOKEN` | For GHE | Enterprise server PAT (name in workspace.yaml) |

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
