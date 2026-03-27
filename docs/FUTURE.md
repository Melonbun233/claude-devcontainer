# Future Enhancements

## CI/CD Mode

Auto-triggered non-interactive mode for pipeline tasks:
- Lint fixing, test generation, documentation updates
- JSON output format with budget limits and timeouts
- Exit codes for pipeline integration
- Triggered by GitHub Actions, Jenkins, or other CI systems

## Refactoring Mode

Semi-autonomous mode with acceptance criteria:
- Takes a refactoring plan as input
- Executes step-by-step, commits between phases
- Acceptance criteria checked after each phase
- Interrupt/resume via sentinel files
- File-based session control (interrupt, guidance, status)

## Kubernetes Deployment

Run containers as K8s Jobs/CronJobs:
- Job spec for one-shot PR reviews
- CronJob for scheduled code quality checks
- Pod template with resource limits
- Web terminal (ttyd) for interactive access in cloud

## Host-Side SKILL Plugin

Claude Code skill on the host machine to spawn containers:
- `/container-start` skill to launch claude-sandbox
- Monitor running containers and their status
- Dashboard UI for managing multiple container sessions

## Web UI Dashboard

Browser-based interface for managing containers:
- Start/stop containers with mode selection
- View session status and logs
- Inspect and submit PR reviews
- Multi-container overview
