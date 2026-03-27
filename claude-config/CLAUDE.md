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

Use the gstack skills for structured development workflows:

1. **Plan**: `/office-hours` to frame the problem, `/plan-eng-review` to lock architecture
2. **Build**: Implement changes with focused, minimal edits
3. **Review**: `/review` for pre-landing code review with auto-fixes
4. **Test**: `/qa` for real browser testing, or run tests manually
5. **Ship**: `/ship` to create PR with test verification

### Key gstack skills available:
- `/review` — Staff engineer code review with bug detection and auto-fixes
- `/investigate` — Systematic root-cause debugging
- `/qa` — Real browser testing with regression tests
- `/ship` — Create PRs with test verification
- `/plan-eng-review` — Architecture and data flow review
- `/cso` — Security audit (OWASP + STRIDE)
- `/benchmark` — Performance baselines and comparisons

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
