# claude-sandbox

Isolated, containerized environment for Claude Code — built for DevOps, developers, and CI/CD pipelines. Ships with GitHub Enterprise multi-server auth, credential isolation, and extensible plugin support.

## Prerequisites

- Docker and Docker Compose
- Claude Code authenticated on your host machine (`~/.claude.json`)
- GitHub PAT(s) for your GitHub server(s)
- `yq` for config parsing (`brew install yq`)
- `socat` for SSH agent forwarding on macOS (`brew install socat`) — not needed on Linux

## Quick Start

```bash
# 1. Copy and fill in your environment variables
cp .env.example .env

# 2. Configure your GitHub servers and git options
cp config/sandbox.yaml.example config/sandbox.yaml
# Edit config/sandbox.yaml with your GitHub servers

# 3. Build the container
./claude-sandbox build

# 4. Launch a session (start + attach in one step)
./claude-sandbox launch my-feature
```

## Modes

### Develop (default)

Interactive mode — you attach to the container and use Claude Code directly with full TTY formatting.

```bash
./claude-sandbox start my-feature
./claude-sandbox attach my-feature
# Optionally enable autonomous mode:
./claude-sandbox attach my-feature --dangerously-skip-permissions
```

> **Note:** The `--dangerously-skip-permissions` flag allows Claude to execute tools (shell commands, file writes, etc.) without asking for confirmation each time. The containerized environment provides isolation so these operations are confined to the session's workspace volume and cannot affect your host machine.

### One-Shot

Run a prompt in a fresh container. Session auto-removes after completion unless `--keep` is specified.

```bash
# Run any prompt
./claude-sandbox run task1 --prompt="Run tests and fix failures" --repo=~/repos/api

# Code analysis
./claude-sandbox run audit --prompt="Find security issues" --repo=~/repos/service

# PR review (shorthand for common review workflow)
./claude-sandbox run pr-123 --pr=123
./claude-sandbox run pr-456 --pr=org/repo#456 --post    # auto-post review to GitHub

# Keep session for inspection after completion
./claude-sandbox run task1 --prompt="Refactor auth module" --keep
```

> **Note:** One-shot mode automatically uses `--dangerously-skip-permissions` because non-interactive `claude -p` requires it — there is no opt-out. Prefer read-only prompts (PR reviews, code analysis) unless you are comfortable with Claude making unrestricted changes in the container. Output saved to `output.md`.

### Multiple Sessions

Each session has its own name, container, and workspace volume. Run as many as you need:

```bash
./claude-sandbox start feature-auth
./claude-sandbox start bugfix-nav
./claude-sandbox list                      # see all sessions
./claude-sandbox attach feature-auth       # attach to a specific one
./claude-sandbox stop bugfix-nav           # stop (preserves state)
./claude-sandbox start bugfix-nav          # restart a stopped session
./claude-sandbox delete bugfix-nav         # permanently remove
```

## Configuration

### GitHub Servers

Define multiple GitHub servers in `config/sandbox.yaml`:

```yaml
github_servers:
  - host: github.com
    token_env: GH_TOKEN
    auth_method: https          # default
  - host: github.enterprise.corp.com
    token_env: GH_ENTERPRISE_TOKEN
    auth_method: ssh            # requires ssh_agent or mount_ssh
    user_name: Jane Doe
    user_email: jane@corp.com
```

Token env var names are flexible — use any name, just match it in `.env`:

```
GH_TOKEN=ghp_xxx
GH_ENTERPRISE_TOKEN=ghp_yyy
```

All variables from `.env` are automatically passed to the container.

### Source Directories

Source directories are copied into the container via `--repo` flag (no bind mounts — avoids macOS virtiofs overhead):

```bash
./claude-sandbox launch my-feature                          # copies current directory
./claude-sandbox launch my-feature --repo=~/repos/api       # specific directory
./claude-sandbox launch my-feature --repo=~/repos/api --repo=~/repos/config  # multiple
```

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

1. Enable in `config/sandbox.yaml`: set `ssh_agent: true`
2. Ensure your agent has keys loaded: `ssh-add -l`
3. Launch a session — the container should see the same keys via `ssh-add -l`

Host keys are auto-populated via `ssh-keyscan` at startup — no manual host key acceptance needed.

| Platform | Notes |
|----------|-------|
| **macOS** | Uses `socat` relay at `~/.claude/ssh-agent.sock` to survive sleep/wake socket rotation. Requires `socat` (`brew install socat`). Relay restarts on each `start`/`launch`. |
| **Linux** | Direct socket mount. Must be accessible by UID 1000 (container's `claude` user). |
| **Windows** | WSL2 only. Agent must run in the same WSL2 distro as Docker. |

<details>
<summary>SSH troubleshooting</summary>

| Problem | Solution |
|---------|----------|
| "Permission denied" with passphrase key | Use `ssh_agent: true` instead of `mount_ssh: true`. The agent handles passphrase decryption on the host. |
| SSH_AUTH_SOCK is not set | Start your SSH agent: `eval "$(ssh-agent -s)"` then `ssh-add`. macOS usually auto-starts one. |
| Agent stops working after macOS sleep/wake | Run `claude-sandbox stop <name>` then `claude-sandbox start <name>` — the relay restarts automatically. |
| "Bad configuration option: usekeychain" | Your macOS `~/.ssh/config` has macOS-only directives. Use `ssh_agent: true` instead of `mount_ssh: true` to avoid mounting the config. |
| "socat is required" | Install socat: `brew install socat`. Required on macOS only. |

</details>

### Custom File Copy

Copy arbitrary host files/directories into the container:

**CLI flag (ad-hoc, per-session):**

```bash
./claude-sandbox launch my-feature --copy=~/.aws
./claude-sandbox launch my-feature --copy=~/.kube/config:/home/claude/.kube/config:rw
```

**Config (declarative, every session):**

```yaml
# config/sandbox.yaml
custom_files:
  - source: ~/.aws
  - source: ~/.npmrc
    dest: /home/claude/.npmrc
    mode: rw
```

Format: `--copy=<source>[:<dest>][:<mode>]`. Dest defaults to same path, mode defaults to `ro`.

### SSL / TLS for GitHub Enterprise

Enterprise servers with self-signed or corporate CA certificates have two options:

**Option 1: Skip SSL verification**

```yaml
github_servers:
  - host: github.enterprise.corp.com
    token_env: GH_ENTERPRISE_TOKEN
    ssl_verify: false
```

**Option 2: Custom CA certificate**

Place your CA cert in `./certs/` and reference it in `sandbox.yaml`:

```yaml
github_servers:
  - host: github.enterprise.corp.com
    token_env: GH_ENTERPRISE_TOKEN
    ca_cert: corp-root-ca.pem
```

The cert file is installed into the container's system CA store at startup, making it trusted for git, gh CLI, curl, and Node.js.

### Host Configuration

Mount your custom CLAUDE.md, agents, skills, and settings by placing them in `host-config/`:

```
host-config/
├── CLAUDE.md              # Appended to built-in instructions
├── settings.json          # Merged with built-in defaults
├── agents/                # Global agents
├── skills/                # Global skills
└── repos/
    └── <repo-name>/       # Per-repo overrides
        ├── CLAUDE.md
        ├── agents/
        └── skills/
```

The container ships with a built-in `CLAUDE.md` (GitHub workflow instructions) and `settings.json` (permissions allowlist). Your host config is layered on top:
- **CLAUDE.md**: host content is **appended** to the built-in (both are preserved)
- **settings.json**: host values are **merged** with built-in defaults (host wins on conflicts)

### Anthropic Config

The container mounts your host `~/.claude.json` and `~/.claude/settings.json` read-only. API keys, base URL (e.g., LLM proxy), auth tokens, and model config are inherited automatically — no `.env` configuration needed.

To override the host config, uncomment and set these in `.env`:

```
ANTHROPIC_BASE_URL=http://my-proxy:8080/v1
ANTHROPIC_AUTH_TOKEN=your-token
ANTHROPIC_API_KEY=sk-ant-xxx
```

## CLI Reference

| Command | Description |
|---------|-------------|
| `./claude-sandbox build` | Build the container image |
| `./claude-sandbox install` | Install CLI globally as `claude-sandbox` |
| `./claude-sandbox launch <name>` | Start + attach in one step (prompts if session exists) |
| `./claude-sandbox start <name>` | Start a new session (or restart a stopped one) |
| `./claude-sandbox attach <name>` | Attach to a running session |
| `./claude-sandbox run <name> --prompt="<text>"` | Run one-shot prompt |
| `./claude-sandbox run <name> --pr=REF` | Run PR review |
| `./claude-sandbox status <name>` | Show session status |
| `./claude-sandbox logs <name>` | Tail session log |
| `./claude-sandbox stop <name>` | Stop session (preserves state for restart) |
| `./claude-sandbox delete <name>` | Permanently remove session and its data |
| `./claude-sandbox list` | List all sessions |
| `./claude-sandbox help <command>` | Per-command help |

**Common flags:** `--repo=<path>` (source directory), `--copy=<src>[:<dest>][:<mode>]` (custom file copy), `--rm` (auto-cleanup on exit), `--dangerously-skip-permissions` (skip tool confirmation)
