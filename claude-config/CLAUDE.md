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

## Superpowers Plugin

The [superpowers](https://github.com/obra/superpowers) plugin is installed globally, providing structured development workflows:
- **Brainstorming** — structured ideation before coding
- **Test-Driven Development** — write tests first, then implement
- **Systematic Debugging** — methodical root-cause analysis
- **Writing Plans** — structured planning documents
- **Executing Plans** — step-by-step plan execution
- **Code Review** — requesting and receiving reviews
- **Subagent-Driven Development** — parallel agent workflows
- **Verification Before Completion** — ensure quality gates pass

Superpowers skills are invoked automatically during development tasks or via the Skill tool.
