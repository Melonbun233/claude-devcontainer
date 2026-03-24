#!/usr/bin/env bash
set -euo pipefail

# ── PR Review mode ───────────────────────────────────────────────────────────
# Reviews a pull request using gstack's /review skill.
# Outputs comments (dry-run) or posts to GitHub.

PR_NUMBER="${PR_NUMBER:-}"
PR_REPO="${PR_REPO:-}"
DRY_RUN="${DRY_RUN:-true}"
SESSION_DIR="/workspace/.claude-session"

if [ -z "$PR_NUMBER" ]; then
  echo "ERROR: PR_NUMBER is required for pr-review mode."
  echo "  Set PR_NUMBER=123 or PR_NUMBER=org/repo#123"
  exit 1
fi

# Parse org/repo#123 format
if [[ "$PR_NUMBER" == *"#"* ]]; then
  PR_REPO="${PR_NUMBER%%#*}"
  PR_NUMBER="${PR_NUMBER##*#}"
fi

# If PR_REPO is set, use --repo flag
REPO_FLAG=""
if [ -n "$PR_REPO" ]; then
  REPO_FLAG="--repo $PR_REPO"
fi

echo ":: Reviewing PR #$PR_NUMBER ${PR_REPO:+(repo: $PR_REPO)}"
echo ""

# Fetch PR metadata for display
echo ":: Fetching PR details..."
PR_INFO=$(gh pr view "$PR_NUMBER" $REPO_FLAG --json number,title,baseRefName,headRefName,additions,deletions 2>&1) || {
  echo "ERROR: Failed to fetch PR #$PR_NUMBER"
  echo "$PR_INFO"
  exit 1
}

PR_TITLE=$(echo "$PR_INFO" | jq -r '.title')
PR_BASE=$(echo "$PR_INFO" | jq -r '.baseRefName')
PR_HEAD=$(echo "$PR_INFO" | jq -r '.headRefName')
PR_ADDITIONS=$(echo "$PR_INFO" | jq -r '.additions')
PR_DELETIONS=$(echo "$PR_INFO" | jq -r '.deletions')

echo "  Title: $PR_TITLE"
echo "  $PR_BASE ← $PR_HEAD (+$PR_ADDITIONS/-$PR_DELETIONS)"
echo ""

# Checkout the PR branch so gstack /review can analyze the actual code
echo ":: Checking out PR branch..."
WORK_DIR="/workspace/pr-review-$$"
gh pr checkout "$PR_NUMBER" $REPO_FLAG -- "$WORK_DIR" 2>/dev/null || {
  # Fallback: clone and checkout if not already in the repo
  if [ -n "$PR_REPO" ]; then
    git clone --depth=50 "https://github.com/${PR_REPO}.git" "$WORK_DIR" 2>&1 | sed 's/^/    /'
    cd "$WORK_DIR"
    gh pr checkout "$PR_NUMBER" $REPO_FLAG 2>&1 | sed 's/^/    /'
  else
    echo "ERROR: Could not checkout PR. Ensure you are in the repo or set PR_REPO."
    exit 1
  fi
}

if [ -d "$WORK_DIR" ]; then
  cd "$WORK_DIR"
fi

# Run Claude with gstack /review skill
echo ":: Running gstack /review..."
REVIEW_OUTPUT=$(claude -p --dangerously-skip-permissions \
  "Use the /review skill to review this PR. The PR is #$PR_NUMBER. Analyze all changes on this branch compared to $PR_BASE. Output your review as markdown." \
  2>&1) || {
  echo "ERROR: Claude review failed"
  exit 1
}

# Save review to file
mkdir -p "$SESSION_DIR"
echo "$REVIEW_OUTPUT" > "$SESSION_DIR/review.md"
echo "  Review saved to $SESSION_DIR/review.md"

if [ "$DRY_RUN" = "true" ] || [ "$DRY_RUN" = "1" ]; then
  echo ""
  echo "╔══════════════════════════════════════════════════╗"
  echo "║  DRY RUN — Review not posted to GitHub          ║"
  echo "╠══════════════════════════════════════════════════╣"
  echo "║                                                  ║"
  echo "║  Review saved to:                                ║"
  echo "║    /workspace/.claude-session/review.md          ║"
  echo "║                                                  ║"
  echo "║  To inspect and edit:                            ║"
  echo "║    docker exec -it claude-dev \                  ║"
  echo "║      cat /workspace/.claude-session/review.md    ║"
  echo "║                                                  ║"
  echo "║  To post to GitHub:                              ║"
  echo "║    ./claude-dev pr-submit                        ║"
  echo "║                                                  ║"
  echo "╚══════════════════════════════════════════════════╝"
  echo ""
  echo "── Review Preview ──────────────────────────────────"
  echo ""
  echo "$REVIEW_OUTPUT"
else
  echo ":: Posting review to GitHub..."
  gh pr review "$PR_NUMBER" $REPO_FLAG --comment --body "$REVIEW_OUTPUT" 2>&1 || {
    echo "ERROR: Failed to post review. Review saved to $SESSION_DIR/review.md"
    exit 1
  }
  echo "  Review posted to PR #$PR_NUMBER"
fi

# Update session status
jq --arg review "completed" '.pr_review_status = $review' "$SESSION_DIR/status.json" \
  > "$SESSION_DIR/status.json.tmp" \
  && mv "$SESSION_DIR/status.json.tmp" "$SESSION_DIR/status.json"
