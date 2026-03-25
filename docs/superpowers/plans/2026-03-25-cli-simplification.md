# CLI Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the mode concept from the CLI, make `run` a generic one-shot command, add `--rm` to `launch`, and clean up dead files.

**Architecture:** The entrypoint switches from mode-based dispatch (`scripts/modes/*.sh`) to a simple `ONE_SHOT_PROMPT` check — if set, run the prompt and exit; otherwise `sleep infinity` for develop. The `claude-dev` CLI drops `--mode`, `pr-submit`, rewrites `run` as a generic one-shot executor, and adds `--rm` to `launch`.

**Tech Stack:** Bash, Docker Compose, `gh` CLI

**Spec:** `docs/superpowers/specs/2026-03-25-cli-simplification-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `docker-compose.yaml` | Modify | Remove old env vars, add `ONE_SHOT_PROMPT`, update comment |
| `Dockerfile` | Modify | Remove `scripts/modes/*.sh` from `chmod` line |
| `scripts/entrypoint.sh` | Modify | Remove mode validation/dispatch, add one-shot logic |
| `scripts/monitor.sh` | Modify | Replace `mode` field with `type` |
| `claude-dev` | Modify | Major rewrite: option parser, help, `run`, `launch --rm`, remove `pr-submit` |
| `scripts/modes/develop.sh` | Delete | Logic moved into entrypoint |
| `scripts/modes/pr-review.sh` | Delete | Logic moved into entrypoint |
| `config/modes/develop.yaml` | Delete | Dead config, never consumed |
| `config/modes/pr-review.yaml` | Delete | Dead config, never consumed |
| `docs/MODES.md` | Delete | Mode concept removed |
| `docs/ARCHITECTURE.md` | Modify | Update entrypoint flow, env vars, remove mode refs |
| `CLAUDE.md` | Modify | Update CLI reference, startup flow, key files table |

---

### Task 1: Update `docker-compose.yaml` and `Dockerfile`

**Files:**
- Modify: `docker-compose.yaml`
- Modify: `Dockerfile`

- [ ] **Step 1: Remove old env vars, add `ONE_SHOT_PROMPT`**

Replace the `environment` block. Remove `MODE`, `PR_NUMBER`, `PR_REPO`, `DRY_RUN`, `SKIP_PERMISSIONS`. Add `ONE_SHOT_PROMPT`. Keep `SESSION_NAME` and `CONTAINER_NAME`.

```yaml
    environment:
      # CLI-driven vars (set by claude-dev wrapper, not .env)
      - SESSION_NAME=${SESSION_NAME:-default}
      - CONTAINER_NAME=${CONTAINER_NAME:-claude-dev}
      - ONE_SHOT_PROMPT
```

- [ ] **Step 2: Update stale volume comment**

Change the comment on line 29 of `docker-compose.yaml` from:
```yaml
      # Config files (workspace.yaml, mode configs)
```
to:
```yaml
      # Config files (workspace.yaml)
```

- [ ] **Step 3: Update Dockerfile `chmod` line**

The Dockerfile line 75 references `scripts/modes/*.sh` which will not exist after Task 4. Change:
```dockerfile
RUN chmod +x /scripts/*.sh /scripts/modes/*.sh \
```
to:
```dockerfile
RUN chmod +x /scripts/*.sh \
```

- [ ] **Step 4: Verify compose config parses**

Run: `docker compose config --quiet`
Expected: exits 0, no errors

- [ ] **Step 5: Commit**

```bash
git add docker-compose.yaml Dockerfile
git commit -m "chore: remove mode env vars from docker-compose, update Dockerfile chmod"
```

---

### Task 2: Simplify `scripts/entrypoint.sh`

**Files:**
- Modify: `scripts/entrypoint.sh`

- [ ] **Step 1: Remove `MODE` from the banner**

Replace lines 5-12 of `entrypoint.sh`. Remove the `MODE` variable and its display line from the banner:

```bash
SESSION_NAME="${SESSION_NAME:-default}"
echo "┌──────────────────────────────────────────────┐"
echo "│  claude-sandbox                              │"
echo "│  Session: $(printf '%-34s' "$SESSION_NAME")│"
echo "│  Time:    $(printf '%-34s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)")│"
echo "└──────────────────────────────────────────────┘"
echo ""
```

- [ ] **Step 2: Remove mode validation block**

Delete lines 18-26 (the `case "$MODE"` validation block).

- [ ] **Step 3: Update `status.json` to use `type` field**

Replace the `status.json` cat block (lines 84-91) with:

```bash
# Determine session type
if [ -n "${ONE_SHOT_PROMPT:-}" ]; then
  SESSION_TYPE="one-shot"
else
  SESSION_TYPE="develop"
fi

cat > "$SESSION_DIR/status.json" <<EOF
{
  "session_name": "$SESSION_NAME",
  "type": "$SESSION_TYPE",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "container_id": "$(hostname)"
}
EOF
```

- [ ] **Step 4: Replace mode dispatch with one-shot/develop logic**

Replace the block from `echo ":: Setup complete. Launching mode: $MODE"` through `exec /scripts/modes/${MODE}.sh` (end of file) with:

```bash
echo ""
echo ":: Setup complete."
echo ""

# Signal readiness to the host CLI
touch /workspace/.claude-session/ready

# ── Dispatch ──────────────────────────────────────────────────────────────
if [ -n "${ONE_SHOT_PROMPT:-}" ]; then
  echo ":: Running one-shot prompt..."
  # One-shot always requires --dangerously-skip-permissions (non-interactive claude -p)
  OUTPUT=$(claude -p --dangerously-skip-permissions "$ONE_SHOT_PROMPT" 2>&1) || {
    echo "ERROR: Claude execution failed"
    echo "$OUTPUT"
    exit 1
  }
  echo "$OUTPUT" > "$SESSION_DIR/output.md"
  echo "$OUTPUT"
  echo ":: Output saved to $SESSION_DIR/output.md"
else
  echo ":: Develop mode — waiting for attach..."
  exec sleep infinity
fi
```

Note: the `touch ready` line already exists at line 100 of the current file — make sure it's kept in the right position (before the dispatch block, after the setup steps).

- [ ] **Step 5: Verify the script has valid syntax**

Run: `bash -n scripts/entrypoint.sh`
Expected: exits 0, no output

- [ ] **Step 6: Commit**

```bash
git add scripts/entrypoint.sh
git commit -m "refactor: remove mode dispatch from entrypoint, add one-shot prompt support"
```

---

### Task 3: Update `scripts/monitor.sh`

**Files:**
- Modify: `scripts/monitor.sh`

- [ ] **Step 1: Replace `mode` with `type` in monitor.sh**

Change line 15 from:
```bash
MODE=$(jq -r '.mode // "unknown"' "$STATUS_FILE")
```
to:
```bash
TYPE=$(jq -r '.type // "unknown"' "$STATUS_FILE")
```

Change line 24 from:
```bash
echo "│  Mode:      $(printf '%-33s' "$MODE")│"
```
to:
```bash
echo "│  Type:      $(printf '%-33s' "$TYPE")│"
```

Also change `review.md` reference on line 45 to `output.md`:
```bash
REVIEW_FILE="$SESSION_DIR/output.md"
```

And on line 48:
```bash
echo "── Output available at: $REVIEW_FILE ──"
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/monitor.sh`
Expected: exits 0

- [ ] **Step 3: Commit**

```bash
git add scripts/monitor.sh
git commit -m "refactor: update monitor.sh to use type field instead of mode"
```

---

### Task 4: Delete dead files

**Files:**
- Delete: `scripts/modes/develop.sh`
- Delete: `scripts/modes/pr-review.sh`
- Delete: `config/modes/develop.yaml`
- Delete: `config/modes/pr-review.yaml`
- Delete: `docs/MODES.md`

- [ ] **Step 1: Remove all dead files**

```bash
rm scripts/modes/develop.sh scripts/modes/pr-review.sh
rmdir scripts/modes
rm config/modes/develop.yaml config/modes/pr-review.yaml
rmdir config/modes
rm docs/MODES.md
```

- [ ] **Step 2: Verify no remaining references**

Run: `grep -r 'modes/' scripts/ config/ docs/ claude-dev docker-compose.yaml --include='*.sh' --include='*.yaml' --include='*.md' 2>/dev/null || true`
Expected: no matches (other than the spec/plan files in `docs/superpowers/`)

- [ ] **Step 3: Commit**

```bash
git add -A scripts/modes/ config/modes/ docs/MODES.md
git commit -m "chore: remove dead mode scripts, configs, and docs"
```

---

### Task 5: Rewrite `claude-dev` CLI — option parser and help

This is the biggest change. We break it into two tasks: first the option parser + help text, then the command logic.

**Files:**
- Modify: `claude-dev`

- [ ] **Step 1: Update `usage()` function (lines 11-33)**

Replace the entire `usage()` function body with:

```bash
usage() {
  cat <<'EOF'
Usage: claude-dev <command> <session-name> [options]

A session name is required for all commands (except build, list, help).

Commands:
  build                                Build the container image
  launch <name> [options]              Start + attach in one step
  start <name> [--skip-permissions]    Start a new session
  attach <name> [--skip-permissions]   Attach to a running session
  run <name> --prompt=<text> [options] Run a one-shot prompt
  status <name>                        Show session status
  logs <name>                          Tail session output log
  stop <name>                          Stop session (can be restarted later)
  delete <name>                        Permanently remove session and its data
  list                                 List all sessions
  help [command]                       Show help for a command

Run 'claude-dev help <command>' for detailed help on a specific command.
EOF
}
```

- [ ] **Step 2: Update `command_help()` — `launch` case (lines 48-65)**

Replace with:

```bash
    launch)
      cat <<'EOF'
Usage: claude-dev launch <session-name> [options]

Start a session and immediately attach to Claude Code. If the session
is already running, you'll be prompted to re-attach or replace it.

Options:
  --skip-permissions    Enable --dangerously-skip-permissions
  --rm                  Auto-remove session when Claude exits

Examples:
  claude-dev launch my-feature
  claude-dev launch my-feature --skip-permissions
  claude-dev launch my-feature --rm
EOF
      ;;
```

- [ ] **Step 3: Update `command_help()` — `start` case (lines 66-86)**

Replace with:

```bash
    start)
      cat <<'EOF'
Usage: claude-dev start <session-name> [options]

Start a new session or restart a stopped one. Each session gets its own
container and persistent workspace volume.

Options:
  --skip-permissions    Enable --dangerously-skip-permissions

If the session was previously stopped, it is restarted with its existing
workspace data intact.

Examples:
  claude-dev start my-feature
  claude-dev start my-feature --skip-permissions
EOF
      ;;
```

- [ ] **Step 4: Update `command_help()` — `run` case (lines 103-118)**

Replace with:

```bash
    run)
      cat <<'EOF'
Usage: claude-dev run <session-name> --prompt=<text> [options]
       claude-dev run <session-name> --pr=<ref> [options]

Run a one-shot prompt in a fresh container. The session is auto-removed
after completion unless --keep is specified.

Options:
  --prompt=<text>       Prompt to send to Claude (required unless --pr)
  --pr=<ref>            PR review shorthand: number or org/repo#number
  --post                Post PR review to GitHub after completion
  --keep                Preserve session for later inspection (default: auto-remove)

Examples:
  claude-dev run task1 --prompt "Respond with only: test successful"
  claude-dev run review1 --pr=123
  claude-dev run review2 --pr=org/repo#456 --post
  claude-dev run review3 --pr=123 --keep
EOF
      ;;
```

- [ ] **Step 5: Remove `command_help()` — `pr-submit` case (lines 120-130)**

Delete the entire `pr-submit)` case block.

- [ ] **Step 6: Update `command_help()` — `status` case**

Replace description line:
```
Show session status including mode, start time, and container info.
```
with:
```
Show session status including type, start time, and container info.
```

- [ ] **Step 7: Update the option parser (lines 257-273)**

Replace the defaults and while loop:

```bash
# ── Parse remaining options ─────────────────────────────────────────────────
PR_REF=""
SKIP_PERMISSIONS="false"
PROMPT_ARG=""
POST_REVIEW="false"
KEEP_SESSION="false"
AUTO_REMOVE="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --pr=*)          PR_REF="${1#--pr=}" ;;
    --prompt=*)      PROMPT_ARG="${1#--prompt=}" ;;
    --post)          POST_REVIEW="true" ;;
    --keep)          KEEP_SESSION="true" ;;
    --rm)            AUTO_REMOVE="true" ;;
    --skip-permissions) SKIP_PERMISSIONS="true" ;;
    --help|-h)       usage; exit 0 ;;
    *)               echo "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done
```

- [ ] **Step 8: Verify syntax**

Run: `bash -n claude-dev`
Expected: exits 0

- [ ] **Step 9: Commit**

```bash
git add claude-dev
git commit -m "refactor: update CLI help text and option parser for simplified commands"
```

---

### Task 6: Rewrite `claude-dev` CLI — command logic

**Files:**
- Modify: `claude-dev`

- [ ] **Step 1: Simplify the `launch` command (lines 291-398)**

Replace the entire `launch)` case with:

```bash
  launch)
    CLAUDE_ARGS=""
    if [ "$SKIP_PERMISSIONS" = "true" ]; then
      CLAUDE_ARGS="--dangerously-skip-permissions"
    fi

    # Set up cleanup trap if --rm (covers all exit paths including Ctrl+C)
    if [ "$AUTO_REMOVE" = "true" ]; then
      cleanup_session() {
        echo ""
        echo ":: Cleaning up session '$SESSION_NAME'..."
        docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
        docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
        docker volume rm "$VOLUME_NAME" >/dev/null 2>&1 || true
        echo ":: Session cleaned up."
      }
      trap cleanup_session EXIT
    fi

    # If already running, prompt the user
    if container_running; then
      echo "Session '$SESSION_NAME' is already running."
      echo ""
      echo "  [r] Re-attach to existing session"
      echo "  [d] Delete and create a new session"
      echo "  [q] Quit"
      echo ""
      read -rp "Choice [r/d/q]: " choice
      case "$choice" in
        r|R)
          docker exec -it "$CONTAINER_NAME" claude $CLAUDE_ARGS
          exit 0
          ;;
        d|D)
          echo ":: Deleting session '$SESSION_NAME'..."
          # Temporarily disable trap for the intentional delete
          trap - EXIT
          docker stop "$CONTAINER_NAME" >/dev/null
          docker rm "$CONTAINER_NAME" >/dev/null
          if docker volume inspect "$VOLUME_NAME" &>/dev/null; then
            docker volume rm "$VOLUME_NAME" >/dev/null
          fi
          # Re-enable trap for the new session
          if [ "$AUTO_REMOVE" = "true" ]; then
            trap cleanup_session EXIT
          fi
          # fall through to create new session
          ;;
        *)
          # Disable trap — user chose to quit, not to clean up
          trap - EXIT
          exit 0
          ;;
      esac
    fi

    # Restart stopped container or create new one
    if container_exists; then
      echo ":: Restarting stopped session '$SESSION_NAME'..."
      docker start "$CONTAINER_NAME"
    else
      echo ":: Creating session '$SESSION_NAME'..."
      $COMPOSE up -d
    fi

    # Wait for container to be running
    echo ":: Waiting for container to start..."
    for i in $(seq 1 30); do
      if container_running; then
        break
      fi
      sleep 1
    done
    if ! container_running; then
      echo "ERROR: Container did not start within 30 seconds."
      echo "  Check logs: docker logs $CONTAINER_NAME"
      exit 1
    fi

    # Stream entrypoint output while waiting for setup to complete
    echo ""
    docker logs -f "$CONTAINER_NAME" 2>&1 &
    LOGS_PID=$!

    # Temporarily override trap to also clean up log streaming
    cleanup_logs() {
      kill "$LOGS_PID" 2>/dev/null || true
      wait "$LOGS_PID" 2>/dev/null || true
    }
    # Save the --rm cleanup for after logs are done
    PREV_TRAP="$AUTO_REMOVE"
    trap 'cleanup_logs; [ "$PREV_TRAP" = "true" ] && cleanup_session' EXIT

    # Poll for the readiness sentinel file
    READY_TIMEOUT=300
    for i in $(seq 1 "$READY_TIMEOUT"); do
      if docker exec "$CONTAINER_NAME" test -f /workspace/.claude-session/ready 2>/dev/null; then
        break
      fi
      if ! container_running; then
        cleanup_logs
        echo ""
        echo "ERROR: Container stopped unexpectedly during setup."
        echo "  Check logs: docker logs $CONTAINER_NAME"
        trap - EXIT
        exit 1
      fi
      sleep 1
    done

    # Stop log streaming, restore --rm-only trap
    cleanup_logs
    if [ "$AUTO_REMOVE" = "true" ]; then
      trap cleanup_session EXIT
    else
      trap - EXIT
    fi

    if ! docker exec "$CONTAINER_NAME" test -f /workspace/.claude-session/ready 2>/dev/null; then
      echo ""
      echo "ERROR: Setup did not complete within ${READY_TIMEOUT} seconds."
      echo "  Check logs: docker logs $CONTAINER_NAME"
      exit 1
    fi

    echo ""
    echo ":: Attaching to session '$SESSION_NAME'..."
    docker exec -it "$CONTAINER_NAME" claude $CLAUDE_ARGS
    ;;
```

Key changes from current:
- Removed `MODE` export, `PR_NUMBER`, `DRY_RUN`, `SKIP_PERMISSIONS` exports
- Removed `($MODE mode)` from echo
- Changed `exec docker exec` to `docker exec` so cleanup can run
- `--rm` cleanup trap set early (before any exit path) for signal safety
- Trap disabled on intentional quit (`q`) and during intentional delete (`d`)
- Log streaming cleanup composed with session cleanup trap

- [ ] **Step 2: Simplify the `start` command (lines 400-434)**

Replace the entire `start)` case with:

```bash
  start)
    # Check if session is already running
    if container_running; then
      echo "ERROR: Session '$SESSION_NAME' is already running."
      echo ""
      echo "  To attach:  ./claude-dev attach $SESSION_NAME"
      echo "  To stop:    ./claude-dev stop $SESSION_NAME"
      exit 1
    fi

    # Check if a stopped container exists — restart it
    if container_exists; then
      echo ":: Restarting stopped session '$SESSION_NAME'..."
      docker start "$CONTAINER_NAME"
    else
      $COMPOSE up -d
    fi

    echo ""
    echo "Session '$SESSION_NAME' started."
    echo "Attach with:  ./claude-dev attach $SESSION_NAME"
    ;;
```

- [ ] **Step 3: Rewrite the `run` command (lines 458-466)**

Replace the entire `run)` case with:

```bash
  run)
    # Parse --pr shorthand (supports org/repo#123 format)
    if [ -n "$PR_REF" ]; then
      if [[ "$PR_REF" == *"#"* ]]; then
        PR_REPO="${PR_REF%%#*}"
        PR_NUM="${PR_REF##*#}"
        PROMPT="Use the /review skill to review PR #$PR_NUM in repo $PR_REPO. Analyze all changes compared to the base branch. Output your review as markdown."
      else
        PR_NUM="$PR_REF"
        PROMPT="Use the /review skill to review PR #$PR_NUM. Analyze all changes compared to the base branch. Output your review as markdown."
      fi
    elif [ -n "$PROMPT_ARG" ]; then
      PROMPT="$PROMPT_ARG"
    else
      echo "ERROR: --prompt=<text> or --pr=<ref> is required for run."
      echo ""
      echo "  Examples:"
      echo "    ./claude-dev run $SESSION_NAME --prompt=\"Respond with: hello\""
      echo "    ./claude-dev run $SESSION_NAME --pr=123"
      exit 1
    fi

    # Clean up any existing container with the same name (from a prior --keep)
    if container_exists; then
      docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
      docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
      docker volume rm "$VOLUME_NAME" >/dev/null 2>&1 || true
    fi

    export ONE_SHOT_PROMPT="$PROMPT"

    # Run in foreground, blocks until container exits
    $COMPOSE up --abort-on-container-exit

    # Extract output using docker cp (container is stopped after --abort-on-container-exit)
    OUTPUT_FILE=$(mktemp)
    docker cp "$CONTAINER_NAME:/workspace/.claude-session/output.md" "$OUTPUT_FILE" 2>/dev/null || true

    # Post review if --post and --pr
    if [ "$POST_REVIEW" = "true" ] && [ -n "$PR_REF" ]; then
      if [ -s "$OUTPUT_FILE" ]; then
        echo ":: Posting review to GitHub..."
        REVIEW_BODY=$(cat "$OUTPUT_FILE")
        gh pr review "${PR_NUM}" ${PR_REPO:+--repo "$PR_REPO"} --comment --body "$REVIEW_BODY"
        echo "  Review posted to PR #${PR_NUM}"
      else
        echo "ERROR: No output to post. Check session logs."
      fi
    fi
    rm -f "$OUTPUT_FILE"

    # Default: auto-remove. --keep to preserve.
    if [ "$KEEP_SESSION" != "true" ]; then
      docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
      docker volume rm "$VOLUME_NAME" >/dev/null 2>&1 || true
      echo ":: Session cleaned up."
    else
      echo ":: Session preserved. Start and attach: ./claude-dev start $SESSION_NAME && ./claude-dev attach $SESSION_NAME"
    fi
    ;;
```

- [ ] **Step 4: Remove the `pr-submit` command (lines 468-480)**

Delete the entire `pr-submit)` case block.

- [ ] **Step 5: Verify syntax**

Run: `bash -n claude-dev`
Expected: exits 0

- [ ] **Step 6: Commit**

```bash
git add claude-dev
git commit -m "refactor: rewrite run as generic one-shot, add launch --rm, remove pr-submit"
```

---

### Task 7: Update `docs/ARCHITECTURE.md`

**Files:**
- Modify: `docs/ARCHITECTURE.md`

- [ ] **Step 1: Update entrypoint flow diagram (lines 34-43)**

Replace with:

```
entrypoint.sh
  ├── setup-certs.sh        # Install custom CA certificates
  ├── setup-github.sh       # Auth gh CLI per server in workspace.yaml
  ├── setup-jira.sh         # Validate Jira connection
  ├── clone-repos.sh        # Clone repos from workspace.yaml
  ├── setup-claude-config.sh # Install built-in config, layer host overrides
  ├── create session dir    # /workspace/.claude-session/
  └── dispatch
      ├── ONE_SHOT_PROMPT set → claude -p, save output, exit
      └── otherwise           → sleep infinity (develop, user attaches)
```

- [ ] **Step 2: Update volume mounts table (line 53)**

Change:
```
| `./config/` | `/etc/claude-dev/config:ro` | workspace.yaml, mode configs |
```
to:
```
| `./config/` | `/etc/claude-dev/config:ro` | workspace.yaml |
```

- [ ] **Step 3: Update CLI-driven env vars table (lines 79-87)**

Replace with:

```markdown
### CLI-driven (set automatically, not in `.env`)

| Variable | Set by | Description |
|----------|--------|-------------|
| `SESSION_NAME` | positional arg | Session name |
| `CONTAINER_NAME` | derived | `claude-dev-<session-name>` |
| `ONE_SHOT_PROMPT` | `--prompt=` or `--pr=` | Prompt for one-shot `run` command |
```

- [ ] **Step 4: Verify no stale mode references remain**

Run: `grep -n 'mode\|pr-review\|pr-submit\|DRY_RUN\|SKIP_PERMISSIONS\|PR_NUMBER' docs/ARCHITECTURE.md`
Expected: no matches

- [ ] **Step 5: Commit**

```bash
git add docs/ARCHITECTURE.md
git commit -m "docs: update ARCHITECTURE.md for CLI simplification"
```

---

### Task 8: Update `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update Build & Run section (lines 9-21)**

Replace with:

```markdown
## Build & Run

\`\`\`bash
./claude-dev build                          # docker compose build
./claude-dev launch <name>                  # start + attach in one step
./claude-dev launch <name> --rm             # start + attach, auto-cleanup on exit
./claude-dev start <name>                   # start named session (required)
./claude-dev attach <name>                  # attach interactively
./claude-dev run <name> --prompt="<text>"   # run one-shot prompt
./claude-dev run <name> --pr=123            # run PR review
./claude-dev stop <name>                    # stop (preserves state)
./claude-dev delete <name>                  # permanently remove container + volume
./claude-dev list                           # show all sessions
./claude-dev help <command>                 # per-command help
\`\`\`
```

- [ ] **Step 2: Update Container Startup Flow (lines 27-39)**

Replace step 9:
```
9. `exec /scripts/modes/${MODE}.sh`
```
with:
```
9. If `ONE_SHOT_PROMPT` set → run `claude -p`, save output, exit; otherwise → `sleep infinity`
```

- [ ] **Step 3: Update Modes section (lines 71-74)**

Replace the entire `### Modes` section with:

```markdown
### One-Shot vs Develop

- **develop** (default): `sleep infinity`, user attaches with `docker exec -it`
- **one-shot** (`run` command): runs `claude -p --dangerously-skip-permissions` with the provided prompt, saves output to `output.md`, exits
```

- [ ] **Step 4: Update Key Files table (lines 76-88)**

Remove the `scripts/modes/*.sh` row:
```
| `scripts/modes/*.sh` | Mode-specific handlers (develop, pr-review) |
```

- [ ] **Step 5: Verify no stale mode references remain**

Run: `grep -n 'pr-submit\|--mode\|pr-review mode\|DRY_RUN\|modes/' CLAUDE.md`
Expected: no matches

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for CLI simplification"
```

---

### Task 9: Smoke test

No automated test suite exists. Verify the changes work end-to-end.

- [ ] **Step 1: Build the image**

Run: `./claude-dev build`
Expected: builds successfully

- [ ] **Step 2: Verify `--mode` is rejected**

Run: `./claude-dev launch test-reject --mode=develop 2>&1`
Expected: "Unknown option: --mode=develop"

- [ ] **Step 3: Verify `run` requires `--prompt` or `--pr`**

Run: `./claude-dev run test-noprompt 2>&1`
Expected: "ERROR: --prompt=<text> or --pr=<ref> is required for run."

- [ ] **Step 4: Verify `pr-submit` is rejected**

Run: `./claude-dev pr-submit test 2>&1`
Expected: "Unknown command: pr-submit"

- [ ] **Step 5: Verify help text is updated**

Run: `./claude-dev help run`
Expected: shows `--prompt`, `--pr`, `--post`, `--keep` options

- [ ] **Step 6: Verify syntax of all shell scripts**

Run: `bash -n claude-dev && bash -n scripts/entrypoint.sh && bash -n scripts/monitor.sh && echo "All OK"`
Expected: "All OK"

- [ ] **Step 7: Verify no deleted files are referenced**

Run: `grep -rn 'scripts/modes\|config/modes\|MODES\.md\|pr-submit' claude-dev scripts/ docs/ CLAUDE.md docker-compose.yaml Dockerfile 2>/dev/null | grep -v 'superpowers/' || echo "Clean"`
Expected: "Clean"
