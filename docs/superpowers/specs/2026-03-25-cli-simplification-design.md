# CLI Simplification: Remove Mode Concept, Generic One-Shot `run`

**Date:** 2026-03-25
**Status:** Approved

## Problem

The `claude-dev` CLI has a bolted-on `pr-review` mode that adds complexity:
- `--mode` flag on `launch`/`start` with mode validation
- Dedicated `run` command hardcoded to pr-review
- `pr-submit` command for posting dry-run reviews
- `scripts/modes/` directory with per-mode shell scripts
- `config/modes/` directory with dead YAML configs (never consumed)
- Mode-specific env vars (`MODE`, `PR_NUMBER`, `PR_REPO`, `DRY_RUN`) in docker-compose

The pr-review capability is useful, but the mode abstraction is over-engineered for what amounts to "run a prompt and get output."

## Solution

Remove the mode concept entirely. Make `run` a generic one-shot command that takes any prompt. PR review becomes a `--pr` shorthand that expands to a review prompt.

## New CLI Surface

```
claude-dev build
claude-dev launch <name> [--skip-permissions] [--rm]
claude-dev start <name> [--skip-permissions]
claude-dev attach <name> [--skip-permissions]
claude-dev run <name> --prompt "<prompt>" [--post] [--keep]
claude-dev run <name> --pr=<ref> [--post] [--keep]
claude-dev status <name>
claude-dev logs <name>
claude-dev stop <name>
claude-dev delete <name>
claude-dev list
claude-dev help [command]
```

### Changed commands

**`launch`** — removed `--mode`, `--pr` flags. Added `--rm` flag.
- Always starts a develop session
- `--rm`: auto-remove container + volume when Claude REPL exits
- Uses `trap` on EXIT/INT/TERM for reliable cleanup when `--rm` is set

**`start`** — removed `--mode`, `--pr` flags.
- Always starts a develop session

**`run`** — rewritten as generic one-shot executor.
- `--prompt=<text>`: run any arbitrary prompt
- `--pr=<ref>`: shorthand that expands to a review prompt (see below)
- `--post`: for PR reviews, post the review to GitHub after completion
- `--keep`: preserve the session after completion (default: auto-remove)
- Container auto-removes by default (opposite of develop sessions)
- Always uses `--dangerously-skip-permissions` (non-interactive `claude -p` requires it)
- If a container with the same name already exists (from a prior `--keep`), it is removed first

### Removed commands

- **`pr-submit`** — replaced by `--post` flag on `run`, or attach and post manually

### Removed flags

- **`--mode`** — gone from all commands
- **`--no-dry-run`** — replaced by `--post`

## `--pr` Shorthand Expansion

When `--pr=123` is passed to `run`, the CLI expands it to:

```
Use the /review skill to review PR #123. Analyze all changes compared to the base branch. Output your review as markdown.
```

The `org/repo#123` format is also supported. The CLI parses it:

```bash
if [[ "$PR_REF" == *"#"* ]]; then
  PR_REPO="${PR_REF%%#*}"
  PR_NUM="${PR_REF##*#}"
else
  PR_REPO=""
  PR_NUM="$PR_REF"
fi
```

When a repo is specified, the prompt includes `--repo $PR_REPO` context so Claude knows which repo to target.

This expansion happens in the `claude-dev` script on the host. The container receives only `ONE_SHOT_PROMPT`.

## Entrypoint Changes

The entrypoint no longer validates modes or dispatches to mode scripts. New dispatch logic:

```bash
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

Note: `--dangerously-skip-permissions` is always used for one-shot because `claude -p` (non-interactive pipe mode) requires it. The `SKIP_PERMISSIONS` env var is no longer needed for one-shot dispatch.

## `run` Command Implementation

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
      echo "ERROR: --prompt or --pr is required."
      exit 1
    fi

    # Clean up any existing container with the same name (from a prior --keep)
    if container_exists; then
      docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
      docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
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

Key design decisions:
- Uses `docker cp` instead of `docker exec` to extract output after `--abort-on-container-exit` (the container is stopped at that point)
- Uses host-side `gh` CLI for posting reviews (avoids needing the container running)
- Cleans up any existing same-named container before starting
- `SKIP_PERMISSIONS` env var no longer exported — entrypoint always uses it for one-shot

## `launch --rm` Implementation

Change `exec docker exec -it ... claude` to a regular call so cleanup runs after. Use `trap` for reliable cleanup on signals:

```bash
# Set up cleanup trap if --rm
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

docker exec -it "$CONTAINER_NAME" claude $CLAUDE_ARGS

# If not --rm, no trap was set, so nothing happens on exit
```

## Files Removed

| File | Reason |
|------|--------|
| `scripts/modes/develop.sh` | Logic inlined into entrypoint |
| `scripts/modes/pr-review.sh` | Replaced by generic one-shot in entrypoint |
| `scripts/modes/` directory | Empty after above removals |
| `config/modes/develop.yaml` | Dead config, never consumed by any script |
| `config/modes/pr-review.yaml` | Dead config, never consumed by any script |
| `config/modes/` directory | Empty after above removals |

## Files Changed

| File | Changes |
|------|---------|
| `claude-dev` | Remove `--mode`, rewrite `run`, remove `pr-submit`, add `--rm`/`--keep`/`--post`/`--prompt` to option parser, update help text and `command_help()` |
| `scripts/entrypoint.sh` | Remove mode validation + dispatch, add `ONE_SHOT_PROMPT` check, remove `MODE` references |
| `docker-compose.yaml` | Remove `MODE`, `PR_NUMBER`, `PR_REPO`, `DRY_RUN` env vars. Add `ONE_SHOT_PROMPT`. Remove `SKIP_PERMISSIONS`. |
| `CLAUDE.md` | Update CLI reference, remove mode documentation |
| `docs/MODES.md` | Remove entirely (mode concept no longer exists) |
| `docs/ARCHITECTURE.md` | Update to reflect simplified entrypoint flow, remove mode references |

## Option Parser Updates

The option parser (currently lines 263-272 of `claude-dev`) needs these changes:

**Add:**
- `--prompt=*` → `PROMPT_ARG="${1#--prompt=}"`
- `--post` → `POST_REVIEW="true"`
- `--keep` → `KEEP_SESSION="true"`
- `--rm` → `AUTO_REMOVE="true"`

**Remove:**
- `--mode=*`
- `--no-dry-run`

**Defaults:**
- `POST_REVIEW="false"`
- `KEEP_SESSION="false"`
- `AUTO_REMOVE="false"`
- `PROMPT_ARG=""`
- `PR_REF=""` (unchanged)

## `status.json` Changes

The session `status.json` currently includes a `"mode"` field. Replace it with a `"type"` field:
- Develop sessions: `"type": "develop"`
- One-shot runs: `"type": "one-shot"` (plus `"prompt"` field with the truncated prompt text)

## Files Unchanged

- All setup scripts (`setup-github.sh`, `setup-jira.sh`, `clone-repos.sh`, etc.)
- `workspace.yaml` format
- `jira-cli/` scripts
- Dockerfile

## Testing

No test suite exists. Verify by:
1. `./claude-dev build`
2. `./claude-dev launch test1` — confirm develop mode works, attach works
3. `./claude-dev launch test2 --rm` — confirm auto-cleanup on Claude REPL exit
4. `./claude-dev run test3 --prompt "Respond with only: test successful"` — confirm one-shot works and auto-removes
5. `./claude-dev run test4 --prompt "Respond with only: test successful" --keep` — confirm session preserved, can attach
6. `./claude-dev run test5 --pr=123 --keep` — confirm PR review shorthand and session preserved (will fail if no repo, but validates parsing)
7. `./claude-dev status test4` — confirm status shows type "one-shot"
8. Verify `--mode` flag is rejected: `./claude-dev launch test6 --mode=develop` should fail
