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

**`start`** — removed `--mode`, `--pr` flags.
- Always starts a develop session

**`run`** — rewritten as generic one-shot executor.
- `--prompt=<text>`: run any arbitrary prompt
- `--pr=<ref>`: shorthand that expands to a review prompt (see below)
- `--post`: for PR reviews, post the review to GitHub after completion
- `--keep`: preserve the session after completion (default: auto-remove)
- Container auto-removes by default (opposite of develop sessions)

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

The `org/repo#123` format is also supported — the CLI parses the ref and includes repo context in the prompt.

This expansion happens in the `claude-dev` script on the host. The container receives only `ONE_SHOT_PROMPT`.

## Entrypoint Changes

The entrypoint no longer validates modes or dispatches to mode scripts. New dispatch logic:

```bash
if [ -n "${ONE_SHOT_PROMPT:-}" ]; then
  echo ":: Running one-shot prompt..."
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

## `run` Command Implementation

```bash
run)
    if [ -n "$PR_REF" ]; then
      PROMPT="Use the /review skill to review PR #$PR_REF. ..."
    elif [ -n "$PROMPT_ARG" ]; then
      PROMPT="$PROMPT_ARG"
    else
      echo "ERROR: --prompt or --pr is required."
      exit 1
    fi

    export ONE_SHOT_PROMPT="$PROMPT" SKIP_PERMISSIONS="true"

    $COMPOSE up --abort-on-container-exit

    # Post review if --post and --pr
    if [ "$POST_REVIEW" = "true" ] && [ -n "$PR_REF" ]; then
      docker exec "$CONTAINER_NAME" gh pr review "$PR_REF" \
        --comment --body "$(docker exec "$CONTAINER_NAME" cat /workspace/.claude-session/output.md)"
    fi

    # Default: auto-remove. --keep to preserve.
    if [ "$KEEP_SESSION" != "true" ]; then
      docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
      docker volume rm "$VOLUME_NAME" >/dev/null 2>&1 || true
    fi
    ;;
```

## `launch --rm` Implementation

Change `exec docker exec -it ... claude` to a regular call so cleanup runs after:

```bash
docker exec -it "$CONTAINER_NAME" claude $CLAUDE_ARGS

if [ "$AUTO_REMOVE" = "true" ]; then
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker volume rm "$VOLUME_NAME" >/dev/null 2>&1 || true
fi
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
| `claude-dev` | Remove `--mode`, rewrite `run`, remove `pr-submit`, add `--rm`/`--keep`/`--post`/`--prompt`, update help |
| `scripts/entrypoint.sh` | Remove mode validation + dispatch, add `ONE_SHOT_PROMPT` check |
| `docker-compose.yaml` | Remove `MODE`, `PR_NUMBER`, `PR_REPO`, `DRY_RUN` env vars. Add `ONE_SHOT_PROMPT`. |
| `CLAUDE.md` | Update docs to reflect new CLI surface |

## Files Unchanged

- All setup scripts (`setup-github.sh`, `setup-jira.sh`, `clone-repos.sh`, etc.)
- `workspace.yaml` format
- `jira-cli/` scripts
- Dockerfile

## Testing

No test suite exists. Verify by:
1. `./claude-dev build`
2. `./claude-dev launch test1` — confirm develop mode works
3. `./claude-dev launch test2 --rm` — confirm auto-cleanup on exit
4. `./claude-dev run test3 --prompt "echo hello"` — confirm one-shot works and auto-removes
5. `./claude-dev run test4 --pr=123 --keep` — confirm PR review shorthand and session preserved
