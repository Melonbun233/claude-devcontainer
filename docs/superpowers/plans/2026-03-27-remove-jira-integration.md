# Remove Jira Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove all Jira-related code, configuration, and documentation from the claude-sandbox repo for a clean break.

**Architecture:** This is a pure removal — no new code. Delete 6 Jira-specific files, edit 9 shared files to strip Jira references, then verify zero Jira traces remain.

**Tech Stack:** Bash scripts, Dockerfile, Markdown docs

**Spec:** `docs/superpowers/specs/2026-03-27-remove-jira-integration-design.md`

---

### Task 1: Delete Jira-specific files

**Files:**
- Delete: `jira-cli/jira-common.sh`
- Delete: `jira-cli/jira-get-issue.sh`
- Delete: `jira-cli/jira-search.sh`
- Delete: `jira-cli/jira-get-subtasks.sh`
- Delete: `jira-cli/jira-get-sprint.sh`
- Delete: `scripts/setup-jira.sh`

- [ ] **Step 1: Delete all 6 files**

```bash
rm jira-cli/jira-common.sh jira-cli/jira-get-issue.sh jira-cli/jira-search.sh \
   jira-cli/jira-get-subtasks.sh jira-cli/jira-get-sprint.sh scripts/setup-jira.sh
rmdir jira-cli
```

- [ ] **Step 2: Verify deletion**

```bash
ls jira-cli/ 2>&1  # Should fail: "No such file or directory"
ls scripts/setup-jira.sh 2>&1  # Should fail: "No such file or directory"
```

- [ ] **Step 3: Commit**

```bash
git add -A jira-cli/ scripts/setup-jira.sh
git commit -m "chore: delete Jira CLI scripts and setup-jira.sh"
```

---

### Task 2: Remove Jira from Dockerfile and entrypoint

**Files:**
- Modify: `Dockerfile:71` (COPY jira-cli line)
- Modify: `Dockerfile:76-80` (symlink creation loop)
- Modify: `scripts/entrypoint.sh:59-60` (setup-jira.sh call)

- [ ] **Step 1: Edit Dockerfile — remove jira-cli COPY**

Remove this line from `Dockerfile:71`:
```
COPY --chown=claude:claude jira-cli/  /usr/local/lib/jira-cli/
```

- [ ] **Step 2: Edit Dockerfile — remove symlink loop**

Replace the RUN block at `Dockerfile:75-80`:
```dockerfile
RUN chmod +x /scripts/*.sh \
    && for f in /usr/local/lib/jira-cli/*.sh; do \
         name="$(basename "$f" .sh)"; \
         ln -sf "$f" "/usr/local/bin/$name"; \
         chmod +x "$f"; \
       done
```

With just:
```dockerfile
RUN chmod +x /scripts/*.sh
```

- [ ] **Step 3: Edit entrypoint.sh — remove Jira setup call**

Remove these two lines from `scripts/entrypoint.sh:59-60`:
```bash
echo ":: Setting up Jira..."
/scripts/setup-jira.sh || echo "WARN: Jira setup had issues (continuing)"
```

- [ ] **Step 4: Commit**

```bash
git add Dockerfile scripts/entrypoint.sh
git commit -m "chore: remove Jira from Dockerfile and entrypoint"
```

---

### Task 3: Remove Jira from config files

**Files:**
- Modify: `.env.example:16-24` (Jira env vars section)
- Modify: `claude-config/settings.json:6` (jira-* permission)
- Modify: `claude-config/CLAUDE.md:14-22` (Jira Integration section)
- Modify: `claude-config/CLAUDE.md:43` (duplicate Jira reference)

- [ ] **Step 1: Edit .env.example — remove Jira section**

Remove lines 16-24 (the entire Jira block including header comment):
```
# ── Jira (read-only queries) ─────────────────────────────────────────────────
# Jira instance URL (e.g., https://mycompany.atlassian.net)
JIRA_URL=
# Jira Cloud: your email; Jira DC: your username
JIRA_USERNAME=
# Jira Cloud: API token; Jira DC: personal access token
JIRA_API_TOKEN=
# cloud | datacenter (default: cloud)
JIRA_AUTH_TYPE=cloud
```

- [ ] **Step 2: Edit claude-config/settings.json — remove jira permission**

Remove this line from the `permissions.allow` array:
```json
      "Bash(jira-* *)",
```

- [ ] **Step 3: Edit claude-config/CLAUDE.md — remove Jira section**

Remove lines 14-22 (the "Jira Integration (Read-Only)" section):
```markdown
## Jira Integration (Read-Only)

Use these CLI tools to understand user stories and issues:
- `jira-get-issue PROJ-123` — fetch issue details (summary, status, description, subtasks)
- `jira-search "project = PROJ AND status = 'In Progress'"` — search with JQL
- `jira-get-subtasks PROJ-123` — list subtasks of a user story
- `jira-get-sprint 42` — list issues in the active sprint for a board

When a task references a Jira issue, always read it first to understand the full context.
```

- [ ] **Step 4: Edit claude-config/CLAUDE.md — remove duplicate Jira reference**

Remove line 43 (after the gstack skills list):
```
When a task references a Jira issue, always read it first to understand the full context.
```

- [ ] **Step 5: Commit**

```bash
git add .env.example claude-config/settings.json claude-config/CLAUDE.md
git commit -m "chore: remove Jira from config files and built-in instructions"
```

---

### Task 4: Remove Jira from documentation

**Files:**
- Modify: `CLAUDE.md:7` (project description)
- Modify: `CLAUDE.md:37` (startup flow step 5)
- Modify: `CLAUDE.md:62-68` (Jira CLI section)
- Modify: `CLAUDE.md:93-94` (key files table rows)
- Modify: `README.md:3` (project description)
- Modify: `README.md:10` (prerequisites)
- Modify: `README.md:175-184` (Jira config section)
- Modify: `README.md:203` (config cascade description)
- Modify: `docs/ARCHITECTURE.md:12` (.env description)
- Modify: `docs/ARCHITECTURE.md:17-21` (system diagram Jira box)
- Modify: `docs/ARCHITECTURE.md:38` (entrypoint flow)
- Modify: `docs/ARCHITECTURE.md:65-68` (env vars table)
- Modify: `docs/FUTURE.md:20-33` (two Jira sections)

- [ ] **Step 1: Edit CLAUDE.md — remove Jira from description**

Line 7, change:
```
Provides credential isolation, GitHub Enterprise multi-server auth, read-only Jira integration, and pre-installed skills (gstack + superpowers).
```
To:
```
Provides credential isolation, GitHub Enterprise multi-server auth, and pre-installed skills (gstack + superpowers).
```

- [ ] **Step 2: Edit CLAUDE.md — remove Jira from startup flow**

Remove step 5 at line 37:
```
5. `setup-jira.sh` — validate Jira connection (Cloud v3 or DC v2 API)
```

Renumber the remaining steps: step 6 becomes 5, step 7 becomes 6, etc.

- [ ] **Step 3: Edit CLAUDE.md — remove Jira CLI section**

Remove lines 62-68 (the entire "### Jira CLI" section):
```markdown
### Jira CLI

Four read-only scripts in `jira-cli/` all source `jira-common.sh` for shared auth:
- Cloud: `Basic base64(username:token)` → `/rest/api/3`
- Datacenter: `Bearer token` → `/rest/api/2`

`jira_curl()` handles auth headers, HTTP error codes, and JSON error extraction.
```

- [ ] **Step 4: Edit CLAUDE.md — remove Jira from key files table**

Remove these two rows from the key files table at lines 93-94:
```
| `jira-cli/jira-common.sh` | Shared Jira auth/HTTP library |
| `jira-cli/jira-*.sh` | Query scripts (get-issue, search, get-subtasks, get-sprint) |
```

- [ ] **Step 5: Edit README.md — remove Jira from description**

Line 3, change:
```
Ships with GitHub Enterprise multi-server auth, read-only Jira integration, credential isolation, and pre-installed AI development skills.
```
To:
```
Ships with GitHub Enterprise multi-server auth, credential isolation, and pre-installed AI development skills.
```

- [ ] **Step 6: Edit README.md — remove Jira from prerequisites**

Remove line 10:
```
- (Optional) Jira API token
```

- [ ] **Step 7: Edit README.md — remove Jira config section**

Remove lines 175-184 (the "### Jira (Read-Only)" section including the code block):
```markdown
### Jira (Read-Only)

Set in `.env`:

```
JIRA_URL=https://mycompany.atlassian.net
JIRA_USERNAME=you@company.com
JIRA_API_TOKEN=your-api-token
JIRA_AUTH_TYPE=cloud   # or "datacenter" for Jira DC/Server
```
```

- [ ] **Step 8: Edit README.md — remove Jira from config cascade description**

Line 203 (line number will shift after step 7), change:
```
The container ships with a built-in `CLAUDE.md` (GitHub, Jira, gstack, superpowers instructions) and `settings.json` (permissions allowlist).
```
To:
```
The container ships with a built-in `CLAUDE.md` (GitHub, gstack, superpowers instructions) and `settings.json` (permissions allowlist).
```

- [ ] **Step 9: Edit docs/ARCHITECTURE.md — remove Jira from system diagram**

In the ASCII diagram, change line 12 from:
```
│  .env ────────────────────┤  (tokens, Jira creds)               │
```
To:
```
│  .env ────────────────────┤  (tokens)                            │
```

Remove the Jira box from the diagram (lines 17-20). Replace:
```
│  │  ┌─────────────┐  ┌──────────┐  ┌──────────────────┐    │   │
│  │  │ Claude Code  │  │ gh CLI   │  │ jira-* scripts   │    │   │
│  │  │ (interactive │  │ (GitHub  │  │ (Jira REST API   │    │   │
│  │  │  or -p mode) │  │  ops)    │  │  read-only)      │    │   │
│  │  └─────────────┘  └──────────┘  └──────────────────┘    │   │
```
With:
```
│  │  ┌─────────────┐  ┌──────────┐                           │   │
│  │  │ Claude Code  │  │ gh CLI   │                           │   │
│  │  │ (interactive │  │ (GitHub  │                           │   │
│  │  │  or -p mode) │  │  ops)    │                           │   │
│  │  └─────────────┘  └──────────┘                           │   │
```

- [ ] **Step 10: Edit docs/ARCHITECTURE.md — remove Jira from entrypoint flow**

Remove line 38:
```
  ├── setup-jira.sh         # Validate Jira connection
```

- [ ] **Step 11: Edit docs/ARCHITECTURE.md — remove Jira env vars**

Remove these 4 rows from the environment variables table (lines 65-68):
```
| `JIRA_URL` | For Jira | Jira instance URL |
| `JIRA_USERNAME` | For Jira Cloud | Email for Cloud, username for DC |
| `JIRA_API_TOKEN` | For Jira | API token (Cloud) or PAT (DC) |
| `JIRA_AUTH_TYPE` | No | `cloud` (default) or `datacenter` |
```

- [ ] **Step 12: Edit docs/FUTURE.md — remove Jira sections**

Remove lines 20-33 (both "Jira Write Operations" and "Jira User Story Workflow" sections):
```markdown
## Jira Write Operations

Extend the Jira CLI with write capabilities:
- `jira-update-issue <KEY> <field> <value>` — update issue fields
- `jira-add-comment <KEY> "<text>"` — add comments
- `jira-transition <KEY> <status>` — transition issue status

## Jira User Story Workflow

Structure work based on Jira hierarchy:
- Read Epic → User Stories → Subtasks
- Auto-generate implementation plan from story
- Create subtasks for implementation phases
- Update status as work progresses
```

- [ ] **Step 13: Commit**

```bash
git add CLAUDE.md README.md docs/ARCHITECTURE.md docs/FUTURE.md
git commit -m "docs: remove all Jira references from documentation"
```

---

### Task 5: Verify clean removal

- [ ] **Step 1: Grep for any remaining Jira references**

```bash
grep -ri jira --include='*.md' --include='*.sh' --include='*.json' --include='*.yaml' --include='*.yml' --include='Dockerfile' .
```

Expected: zero matches (excluding `docs/superpowers/` spec/plan files).

- [ ] **Step 2: Build the Docker image**

```bash
docker compose build
```

Expected: build succeeds without errors about missing `jira-cli/` directory.

- [ ] **Step 3: Verify jira-cli directory is gone**

```bash
ls jira-cli/ 2>&1
```

Expected: "No such file or directory"

- [ ] **Step 4: Verify scripts/setup-jira.sh is gone**

```bash
ls scripts/setup-jira.sh 2>&1
```

Expected: "No such file or directory"
