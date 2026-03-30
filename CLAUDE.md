# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Isolated, containerized Claude Code environment (`ubuntu:24.04`) for DevOps, developers, and CI/CD pipelines. Provides credential isolation, GitHub Enterprise multi-server auth, and pre-installed skills (superpowers).

## Build & Run

```bash
./claude-sandbox build                                    # docker compose build
./claude-sandbox install                                  # install CLI globally
./claude-sandbox launch <name>                            # sandbox current directory
./claude-sandbox launch <name> --dir=/path/to/repo        # sandbox a specific directory
./claude-sandbox launch <name> --rm                       # start + attach, auto-cleanup on exit
./claude-sandbox start <name>                             # start named session (required)
./claude-sandbox start <name> --dir=/path/to/repo         # start with a specific directory
./claude-sandbox attach <name>                            # attach interactively
./claude-sandbox run <name> --prompt="<text>"             # run one-shot prompt
./claude-sandbox run <name> --prompt="<text>" --dir=/path # run one-shot on a specific directory
./claude-sandbox run <name> --pr=123                      # run PR review
./claude-sandbox stop <name>                              # stop (preserves state)
./claude-sandbox delete <name>                            # permanently remove container + volume
./claude-sandbox list                                     # show all sessions
./claude-sandbox help <command>                           # per-command help
```

There is no test suite. Verify changes by building the image and starting a session.

## Architecture

### Container Startup Flow

`entrypoint.sh` orchestrates setup then dispatches to a mode script:

1. `setup-certs.sh` — install custom CA certificates from `sandbox.yaml` `ca_cert` paths
2. Copy + patch host `~/.claude.json` (pre-accept `/workspace` trust)
3. Copy + rewrite host `~/.claude/settings.json` (`localhost` → `host.docker.internal`)
4. `setup-git.sh` — authenticate git per server (SSH keys + credential store + gh CLI)
5. Host CLI copies source directories via `docker cp` (entrypoint handshake: copy-ready → copy-done)
6. Per-repo git setup — `safe.directory`, per-repo identity from `github_servers[]`
7. `setup-claude-config.sh` — cascade host → built-in → per-repo config
8. Create `/workspace/.claude-session/` (status.json, output.log)
9. If `ONE_SHOT_PROMPT` set → run `claude -p`, save output, exit; otherwise → `sleep infinity`

### Named Sessions

Each session name derives three identifiers:
- Container: `claude-sandbox-<name>`
- Volume: `claude-sandbox-workspace-<name>`
- Compose project: `claude-sandbox-<name>` (via `--project-name`)

Sessions are isolated — multiple can run simultaneously. `stop` preserves the volume; `delete` removes everything.

### Multi-Server GitHub Auth

`sandbox.yaml` defines a `github_servers[]` list. Each entry has `host`, `token_env` (env var name holding the PAT), `auth_method: ssh|https`, optional `user_name`/`user_email`, and optional SSL config (`ssl_verify: false` or `ca_cert: path`).

- **HTTPS**: tokens written to git-credential-store; `gh` CLI configured as a secondary credential helper per server.
- **SSH (agent forwarding)**: opt-in via `git_config.ssh_agent: true`. Forwards the host SSH agent socket into the container — recommended for passphrase-protected keys and macOS Keychain. See `docs/SSH-AGENT.md`.
- **SSH (key files)**: opt-in via `git_config.mount_ssh: true`. Mounts host `~/.ssh` read-only; SSH config generated per server with `IdentityFile` routing. Keys must not require a passphrase.

`docker-compose.override.yaml` is generated at runtime by the CLI for conditional SSH/gitconfig/agent volume mounts and `DEFAULT_WORKDIR` (gitignored). Source directories are copied via `docker cp` after container start — no bind mounts. Per-server identity and SSL config are handled the same way regardless of auth method.

### Configuration Cascade

Built-in config (baked into image at `/etc/claude-sandbox/claude-config/`) is installed first, then host config (`/host-config`) is layered on top:
- **CLAUDE.md**: host content **appended** to built-in (both preserved)
- **settings.json**: host values **merged** via `jq -s '.[0] * .[1]'` (host wins)
- **agents/skills**: host files override built-in if same name

Per-repo config (`/host-config/repos/<name>/`) is copied to `/workspace/<name>/.claude/`.

### One-Shot vs Develop

- **develop** (default): `sleep infinity`, user attaches with `docker exec -it`
- **one-shot** (`run` command): automatically uses `--dangerously-skip-permissions` (required for non-interactive `claude -p`). Prefer read-only prompts (PR reviews, code analysis) unless comfortable with unrestricted changes. Output saved to `output.md`.

## Key Files

| Path | Purpose |
|------|---------|
| `claude-sandbox` | Host CLI wrapper — session lifecycle, command dispatch |
| `docker-compose.yaml` | Parameterized service; `env_file: .env` passes all credentials |
| `scripts/entrypoint.sh` | Container init orchestrator |
| `scripts/setup-git.sh` | Git auth: SSH config, credential store, gh CLI per server |
| `docker-compose.override.yaml` | Generated at runtime by CLI for conditional SSH/gitconfig mounts (gitignored) |
| `config/sandbox.yaml` | GitHub servers + git config (gitignored; no repos list) |
| `.env` | User's credentials (gitignored) |

## Conventions

- All setup scripts degrade gracefully: warn and continue if credentials are missing (`|| echo "WARN: ..."`)
- Source directories are copied via `docker cp` (no bind mounts) to avoid macOS virtiofs overhead
- Token indirection: `sandbox.yaml` stores env var *names* (`token_env: GH_TOKEN`), resolved at runtime via `${!TOKEN_ENV}`
- All `.env` variables auto-passed to container via `env_file` in docker-compose.yaml
- Host proxy access: `host.docker.internal:host-gateway` in compose + `localhost` → `host.docker.internal` rewrite in entrypoint
- Container runs as non-root `claude` (UID 1000) with passwordless sudo
- Anthropic config inherited from host mounts; `.env` values are optional overrides
- Use git worktrees for new features and code changes; open PRs to land on the default branch
- When starting a new feature without a specified name, suggest a descriptive branch name and let the user choose
