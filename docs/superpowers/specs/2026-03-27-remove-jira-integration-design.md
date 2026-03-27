# Remove Jira Integration

## Motivation

The custom Jira CLI integration lacks security guardrails (credentials passed as plain env vars, no token scoping, no audit trail) and adds maintenance burden. Jira integration is better served by MCP servers which provide standardized auth, permission boundaries, and community support. Removing it keeps the repo minimal and functional.

## Scope

Complete removal of all Jira-related code, configuration, and documentation. Clean break with no references remaining.

## File Deletions (6 files)

| File | Content |
|------|---------|
| `jira-cli/jira-common.sh` | Shared auth library (Cloud/DC detection, curl wrapper) |
| `jira-cli/jira-get-issue.sh` | Fetch issue details |
| `jira-cli/jira-search.sh` | JQL search |
| `jira-cli/jira-get-subtasks.sh` | List subtasks |
| `jira-cli/jira-get-sprint.sh` | List sprint issues |
| `scripts/setup-jira.sh` | Connection validation during container startup |

The `jira-cli/` directory is removed entirely.

## File Edits

### Dockerfile

Remove:
- `COPY --chown=claude:claude jira-cli/ /usr/local/lib/jira-cli/` line
- The symlink creation block that links `jira-*.sh` into `/usr/local/bin/`

### scripts/entrypoint.sh

Remove the `setup-jira.sh` call (line ~59-60) from the startup sequence.

### .env.example

Remove the entire Jira section (lines 16-24):
```
# ── Jira (read-only queries) ──────────────────────────────────────────────
JIRA_URL=
JIRA_USERNAME=
JIRA_API_TOKEN=
JIRA_AUTH_TYPE=cloud
```

### claude-config/settings.json

Remove `"Bash(jira-* *)"` from the `permissions.allow` array.

### claude-config/CLAUDE.md

Remove the "Jira Integration (Read-Only)" section (lines 14-22) and the duplicate Jira reference on line 43.

### CLAUDE.md (root)

Remove:
- "read-only Jira integration" from project description
- Step 5 (`setup-jira.sh`) from Container Startup Flow
- The "Jira CLI" architecture section
- `jira-cli/` entries from the Key Files table
- `jira_curl()` reference

### README.md

Remove:
- "read-only Jira integration" from project description
- "(Optional) Jira API token" from prerequisites
- Jira configuration section with env var examples
- "Jira, " from the config cascade description ("The container ships with a built-in CLAUDE.md (GitHub, Jira, gstack, superpowers instructions)...")

### docs/ARCHITECTURE.md

Remove:
- `jira-* scripts` from system diagram
- `setup-jira.sh` from entrypoint flow
- Jira env vars (`JIRA_URL`, `JIRA_USERNAME`, `JIRA_API_TOKEN`, `JIRA_AUTH_TYPE`) from environment variables table

### docs/FUTURE.md

Remove:
- "Jira Write Operations" section (lines 20-25)
- "Jira User Story Workflow" section (lines 27-33)

## What stays unchanged

- `docker-compose.yaml` — `env_file: .env` is generic
- `config/workspace.yaml` — has no Jira config
- All Git, GitHub, SSH, and clone-related code

## Verification

- `docker compose build` succeeds without Jira artifacts
- `grep -ri jira` across the repo returns zero matches
- Container starts without errors (setup-jira.sh no longer called)

## Out of scope

- Adding MCP server documentation or configuration (separate effort if desired)
- Modifying any Git/GitHub/SSH auth flows
