# Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  Host Machine                                                    │
│                                                                  │
│  ~/.claude.json ──────────┐  (API keys, base URL, auth)         │
│  host-config/ ────────────┤  (CLAUDE.md, agents, skills)        │
│  config/workspace.yaml ───┤  (repos, GitHub servers)            │
│  .env ────────────────────┤  (tokens, Jira creds)               │
│                           │                                      │
│  ┌────────────────────────▼─────────────────────────────────┐   │
│  │  Docker Container (ubuntu:24.04)                          │   │
│  │                                                           │   │
│  │  ┌─────────────┐  ┌──────────┐  ┌──────────────────┐    │   │
│  │  │ Claude Code  │  │ gh CLI   │  │ jira-* scripts   │    │   │
│  │  │ (interactive │  │ (GitHub  │  │ (Jira REST API   │    │   │
│  │  │  or -p mode) │  │  ops)    │  │  read-only)      │    │   │
│  │  └─────────────┘  └──────────┘  └──────────────────┘    │   │
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
  ├── setup-github.sh      # Auth gh CLI per server in workspace.yaml
  ├── setup-jira.sh         # Validate Jira connection
  ├── clone-repos.sh        # Clone repos from workspace.yaml
  ├── setup-claude-config.sh # Copy host CLAUDE.md, agents, skills
  ├── create session dir    # /workspace/.claude-session/
  └── dispatch mode
      ├── develop.sh        # sleep infinity, user attaches
      └── pr-review.sh      # one-shot review, exit
```

## Volume Mounts

| Host Path | Container Path | Purpose |
|-----------|---------------|---------|
| `~/.claude.json` | `/home/claude/.claude.json:ro` | Anthropic API config |
| `./host-config/` | `/host-config:ro` | CLAUDE.md, agents, skills |
| `./config/` | `/etc/claude-dev/config:ro` | workspace.yaml, mode configs |
| `workspace` (volume) | `/workspace` | Cloned repos (persistent) |

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `MODE` | No | `develop` (default) or `pr-review` |
| `GH_TOKEN` | For GitHub.com | GitHub.com PAT |
| `GH_ENTERPRISE_TOKEN` | For GHE | Enterprise server PAT (name in workspace.yaml) |
| `JIRA_URL` | For Jira | Jira instance URL |
| `JIRA_USERNAME` | For Jira Cloud | Email for Cloud, username for DC |
| `JIRA_API_TOKEN` | For Jira | API token (Cloud) or PAT (DC) |
| `JIRA_AUTH_TYPE` | No | `cloud` (default) or `datacenter` |
| `PR_NUMBER` | PR review | PR number or `org/repo#number` |
| `DRY_RUN` | No | `true` (default) — save review to file |
| `SKIP_PERMISSIONS` | No | `true` to use `--dangerously-skip-permissions` in develop mode |
