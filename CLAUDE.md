# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Containerized Claude Code environment (`ubuntu:24.04`) for running `--dangerously-skip-permissions` safely, with GitHub Enterprise multi-server auth, read-only Jira integration, and pre-installed skills (gstack + superpowers).

## Build & Run

```bash
./claude-dev build                          # docker compose build
./claude-dev launch <name>                  # start + attach in one step
./claude-dev start <name>                   # start named session (required)
./claude-dev attach <name>                  # attach interactively
./claude-dev stop <name>                    # stop (preserves state)
./claude-dev start <name>                   # restart stopped session
./claude-dev delete <name>                  # permanently remove container + volume
./claude-dev list                           # show all sessions
./claude-dev help <command>                 # per-command help
```

There is no test suite. Verify changes by building the image and starting a session.

## Architecture

### Container Startup Flow

`entrypoint.sh` orchestrates setup then dispatches to a mode script:

1. Copy + patch host `~/.claude.json` (pre-accept `/workspace` trust)
2. Copy + rewrite host `~/.claude/settings.json` (`localhost` → `host.docker.internal`)
3. `setup-github.sh` — authenticate `gh` CLI per server in `workspace.yaml`
4. `setup-jira.sh` — validate Jira connection (Cloud v3 or DC v2 API)
5. `clone-repos.sh` — clone repos with per-server token injection + per-repo git identity
6. `setup-claude-config.sh` — cascade host → built-in → per-repo config
7. Create `/workspace/.claude-session/` (status.json, output.log)
8. `exec /scripts/modes/${MODE}.sh`

### Named Sessions

Each session name derives three identifiers:
- Container: `claude-dev-<name>`
- Volume: `claude-dev-workspace-<name>`
- Compose project: `claude-dev-<name>` (via `--project-name`)

Sessions are isolated — multiple can run simultaneously. `stop` preserves the volume; `delete` removes everything.

### Multi-Server GitHub Auth

`workspace.yaml` defines a `github_servers[]` list. Each entry has `host`, `token_env` (env var name holding the PAT), and optional `user_name`/`user_email`. The clone script builds `HOST_TOKENS` / `HOST_USER_NAMES` / `HOST_USER_EMAILS` associative arrays, then routes tokens by matching repo URL hostname.

### Jira CLI

Four read-only scripts in `jira-cli/` all source `jira-common.sh` for shared auth:
- Cloud: `Basic base64(username:token)` → `/rest/api/3`
- Datacenter: `Bearer token` → `/rest/api/2`

`jira_curl()` handles auth headers, HTTP error codes, and JSON error extraction.

### Configuration Cascade

Built-in config (baked into image at `/etc/claude-dev/claude-config/`) is installed first, then host config (`/host-config`) is layered on top:
- **CLAUDE.md**: host content **appended** to built-in (both preserved)
- **settings.json**: host values **merged** via `jq -s '.[0] * .[1]'` (host wins)
- **agents/skills**: host files override built-in if same name

Per-repo config (`/host-config/repos/<name>/`) is copied to `/workspace/<name>/.claude/`.

### Modes

- **develop**: `sleep infinity`, user attaches with `docker exec -it`
- **pr-review**: checks out PR branch, runs `claude -p --dangerously-skip-permissions` with gstack `/review`, saves to `review.md` (dry-run default) or posts via `gh pr review`

## Key Files

| Path | Purpose |
|------|---------|
| `claude-dev` | Host CLI wrapper — session lifecycle, command dispatch |
| `docker-compose.yaml` | Parameterized service (container_name, volume via env vars) |
| `scripts/entrypoint.sh` | Container init orchestrator |
| `scripts/setup-*.sh` | GitHub auth, Jira validation, repo cloning, config cascade |
| `scripts/modes/*.sh` | Mode-specific handlers (develop, pr-review) |
| `jira-cli/jira-common.sh` | Shared Jira auth/HTTP library |
| `jira-cli/jira-*.sh` | Query scripts (get-issue, search, get-subtasks, get-sprint) |
| `config/workspace.yaml` | User's GitHub servers + repos (gitignored) |
| `.env` | User's credentials (gitignored) |

## Conventions

- All setup scripts degrade gracefully: warn and continue if credentials are missing (`|| echo "WARN: ..."`)
- Token indirection: `workspace.yaml` stores env var *names* (`token_env: GH_TOKEN`), resolved at runtime via `${!TOKEN_ENV}`
- Host proxy access: `host.docker.internal:host-gateway` in compose + `localhost` → `host.docker.internal` rewrite in entrypoint
- Container runs as non-root `claude` (UID 1000) with passwordless sudo
- Anthropic config inherited from host mounts; `.env` values are optional overrides
- Push to both remotes on commit: `git push origin main && git push github main`
