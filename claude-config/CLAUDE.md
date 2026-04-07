# Claude Code — Container Environment Instructions

## GitHub Integration

Use `gh` CLI for all GitHub operations:
- `gh pr view <number>` — view PR details
- `gh pr diff <number>` — get PR diff
- `gh pr review <number> --comment --body "..."` — post review comment
- `gh pr create --title "..." --body "..."` — create PR
- `gh issue view <number>` — view issue
- `gh issue list` — list issues
- `gh api <endpoint>` — raw API calls

## Workflow

1. **Plan**: Frame the problem, brainstorm, and plan architecture
2. **Build**: Implement changes with focused, minimal edits
3. **Review**: Pre-landing code review
4. **Test**: Run tests manually or via structured QA
5. **Ship**: Create PR with test verification

Commit with descriptive messages following project conventions.

## Container Image Building

This sandbox uses Buildah (daemonless, rootless) instead of Docker for building container images.
A `docker` shim is installed that maps supported commands to Buildah equivalents:

| `docker` command | Actual command | Notes |
|------------------|---------------|-------|
| `docker build` | `buildah bud` | Full Dockerfile support |
| `docker push` | `buildah push` | Push to any OCI registry |
| `docker tag` | `buildah tag` | |
| `docker images` | `buildah images` | |
| `docker login` | `buildah login` | |
| `docker rmi` | `buildah rmi` | |

**Not available:** `docker run`, `docker compose`, `docker ps`, `docker exec`, and other runtime commands.
This sandbox is for building and pushing images only — not for running containers.

For multi-arch builds, use: `docker build --platform linux/amd64,linux/arm64 -t myimage .`

For registry auth, use `docker login <registry>` or copy credentials via `--copy=~/.docker/config.json:/run/containers/0/auth.json`.
