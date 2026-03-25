# claude-sandbox

Containerized environment for running Claude Code with `--dangerously-skip-permissions` "safely", integrated with GitHub Enterprise, Jira, and pre-installed AI development skills.

## Prerequisites

- Docker and Docker Compose
- Claude Code authenticated on your host machine (`~/.claude.json`)
- GitHub PAT(s) for your GitHub server(s)
- (Optional) Jira API token

## Quick Start

```bash
# 1. Copy and fill in your environment variables
cp .env.example .env

# 2. Configure your workspace repos
cp config/workspace.yaml.example config/workspace.yaml
# Edit config/workspace.yaml with your repos and GitHub servers

# 3. Build the container
./claude-dev build

# 4. Launch a session (start + attach in one step)
./claude-dev launch my-feature
```

## Built-in Skills & Plugins

The container ships with two complementary skill sets pre-installed, available in all modes.

### [gstack](https://github.com/garrytan/gstack) — Development Workflow Skills

28 skills for day-to-day development. Key skills:

| Skill | Purpose |
|-------|---------|
| `/review` | Staff engineer code review with bug detection and auto-fixes |
| `/investigate` | Systematic root-cause debugging |
| `/qa` | Real browser testing with regression tests |
| `/ship` | Create PRs with test verification |
| `/plan-eng-review` | Architecture and data flow review |
| `/cso` | Security audit (OWASP + STRIDE) |
| `/benchmark` | Performance baselines and comparisons |

### [superpowers](https://github.com/obra/superpowers) — Structured Development Methodology

14 composable skills providing a complete software development workflow. Key skills:

| Skill | Purpose |
|-------|---------|
| `brainstorming` | Structured ideation before coding |
| `test-driven-development` | Write tests first, then implement |
| `systematic-debugging` | Methodical root-cause analysis |
| `writing-plans` | Structured planning documents |
| `executing-plans` | Step-by-step plan execution |
| `requesting-code-review` | Request and manage code reviews |
| `subagent-driven-development` | Parallel agent workflows |
| `verification-before-completion` | Ensure quality gates pass |

Superpowers skills are automatically injected into every session via a SessionStart hook.

## Modes

### Develop (default)

Interactive mode — you attach to the container and use Claude Code directly with full TTY formatting. All gstack and superpowers skills are available.

```bash
./claude-dev start my-feature
./claude-dev attach my-feature
# Optionally with --dangerously-skip-permissions:
./claude-dev attach my-feature --skip-permissions
```

> **Note:** The `--skip-permissions` flag passes `--dangerously-skip-permissions` to Claude Code, which allows Claude to execute tools (shell commands, file writes, etc.) without asking for confirmation. Only use this in a containerized environment where you are comfortable with Claude making unrestricted changes.

### PR Review

One-shot mode — reviews a PR using gstack's `/review` skill and outputs comments.

```bash
# Dry-run (default): outputs review to file for you to inspect
./claude-dev run pr-review-123 --mode=pr-review --pr=123

# Auto-post to GitHub:
./claude-dev run pr-review-456 --mode=pr-review --pr=org/repo#456 --no-dry-run

# Post a saved dry-run review:
./claude-dev pr-submit pr-review-123
```

### Multiple Sessions

Each session has its own name, container, and workspace volume. Run as many as you need:

```bash
./claude-dev start feature-auth
./claude-dev start bugfix-nav
./claude-dev list                      # see all sessions
./claude-dev attach feature-auth       # attach to a specific one
./claude-dev stop bugfix-nav           # stop (preserves state)
./claude-dev start bugfix-nav          # restart a stopped session
./claude-dev delete bugfix-nav         # permanently remove
```

## Configuration

### GitHub Servers

Define multiple GitHub servers in `config/workspace.yaml`:

```yaml
github_servers:
  - host: github.com
    token_env: GH_TOKEN
  - host: github.enterprise.sap.com
    token_env: GH_ENTERPRISE_TOKEN
```

Token env var names are flexible — use any name, just match it in `.env`:

```
GH_TOKEN=ghp_xxx
GH_ENTERPRISE_TOKEN=ghp_yyy
```

All variables from `.env` are automatically passed to the container.

### Repos

Define repos to clone into the workspace in `config/workspace.yaml`. These are general-purpose repos needed for your tasks — reference documentation, codebases, shared configs, etc. Each repo is cloned to `/workspace/<target>` on session start.

```yaml
repos:
  - url: https://github.com/org/my-service
    branch: main          # optional: only clone this branch (faster)
    target: my-service

  - url: https://github.com/org/docs
    target: docs           # no branch — clones all branches
```

The `branch` field is optional. When set, only that branch is cloned (`--single-branch`), saving time and bandwidth. When omitted, the full repo with all branches is cloned. The URL host must match one of the `github_servers` entries for authentication.

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

Place your CA cert in `./certs/` and reference it in `workspace.yaml`:

```yaml
github_servers:
  - host: github.enterprise.corp.com
    token_env: GH_ENTERPRISE_TOKEN
    ca_cert: corp-root-ca.pem
```

The cert file is installed into the container's system CA store at startup, making it trusted for git, gh CLI, curl, and Node.js.

### Jira (Read-Only)

Set in `.env`:

```
JIRA_URL=https://mycompany.atlassian.net
JIRA_USERNAME=you@company.com
JIRA_API_TOKEN=your-api-token
JIRA_AUTH_TYPE=cloud   # or "datacenter" for Jira DC/Server
```

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

The container ships with a built-in `CLAUDE.md` (GitHub, Jira, gstack, superpowers instructions) and `settings.json` (permissions allowlist). Your host config is layered on top:
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
| `./claude-dev build` | Build the container image |
| `./claude-dev launch <name>` | Start + attach in one step (prompts if session exists) |
| `./claude-dev start <name>` | Start a new session (or restart a stopped one) |
| `./claude-dev attach <name>` | Attach to a running session |
| `./claude-dev run <name> --mode=pr-review --pr=REF` | Run one-shot PR review |
| `./claude-dev pr-submit <name>` | Post saved review to GitHub |
| `./claude-dev status <name>` | Show session status |
| `./claude-dev logs <name>` | Tail session log |
| `./claude-dev stop <name>` | Stop session (preserves state for restart) |
| `./claude-dev delete <name>` | Permanently remove session and its data |
| `./claude-dev list` | List all sessions |
