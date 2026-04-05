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

