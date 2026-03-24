# claude-devcontainer

Containerized environment for running Claude Code with `--dangerously-skip-permissions` safely, integrated with GitHub Enterprise, Jira, and [gstack](https://github.com/garrytan/gstack) AI development skills.

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

# 4. Start in develop mode
./claude-dev start

# 5. Attach to Claude Code
./claude-dev attach
```

## Built-in Skills (gstack)

The container ships with [gstack](https://github.com/garrytan/gstack), a collection of AI development workflow skills. Key skills:

| Skill | Purpose |
|-------|---------|
| `/review` | Staff engineer code review with bug detection and auto-fixes |
| `/investigate` | Systematic root-cause debugging |
| `/qa` | Real browser testing with regression tests |
| `/ship` | Create PRs with test verification |
| `/plan-eng-review` | Architecture and data flow review |
| `/cso` | Security audit (OWASP + STRIDE) |
| `/benchmark` | Performance baselines and comparisons |

gstack skills are available in both Develop and PR Review modes.

## Modes

### Develop (default)

Interactive mode — you attach to the container and use Claude Code directly with full TTY formatting. All gstack skills are available.

```bash
./claude-dev start --mode=develop
./claude-dev attach
# Optionally with --dangerously-skip-permissions:
./claude-dev attach --skip-permissions
```

### PR Review

One-shot mode — reviews a PR using gstack's `/review` skill and outputs comments.

```bash
# Dry-run (default): outputs review to file for you to inspect
./claude-dev run --mode=pr-review --pr=123

# Auto-post to GitHub:
./claude-dev run --mode=pr-review --pr=org/repo#123 --no-dry-run

# Post a saved dry-run review:
./claude-dev pr-submit
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

Set the corresponding tokens in `.env`:

```
GH_TOKEN=ghp_xxx
GH_ENTERPRISE_TOKEN=ghp_yyy
```

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
├── CLAUDE.md              # Global instructions
├── settings.json          # Global settings
├── agents/                # Global agents
├── skills/                # Global skills
└── repos/
    └── <repo-name>/       # Per-repo overrides
        ├── CLAUDE.md
        ├── agents/
        └── skills/
```

### Anthropic Config

The container mounts your host `~/.claude.json` read-only. API keys, base URL (e.g., LLM proxy), and auth tokens are inherited automatically.

## CLI Reference

| Command | Description |
|---------|-------------|
| `./claude-dev build` | Build the container image |
| `./claude-dev start [--mode=MODE]` | Start the container |
| `./claude-dev attach` | Attach to Claude Code interactively |
| `./claude-dev run --mode=pr-review --pr=REF` | Run one-shot PR review |
| `./claude-dev pr-submit` | Post saved review to GitHub |
| `./claude-dev status` | Show session status |
| `./claude-dev logs` | Tail session log |
| `./claude-dev stop` | Stop the container |
| `./claude-dev clean` | Stop and remove volumes |
