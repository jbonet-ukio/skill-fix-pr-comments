#!/usr/bin/env bash
# Watches a PR until the Codex review bot reacts to the latest review request.
#
# Usage: watch-codex.sh [--once] <pr-number> <since-iso8601> [trigger-comment-id]
#
#   since               only Codex reviews/comments created after this instant count
#                       (use the time the review was requested, UTC, e.g. 2026-10-01T15:42:41Z)
#   trigger-comment-id  id of the "@codex review" issue comment. Without it, the
#                       reaction is read from the PR itself (auto-review on open).
#   --once              check a single time and print PENDING instead of sleeping
#                       (used by watch-stack.sh to poll several PRs together)
#
# Prints exactly one line and exits:
#   CODEX_APPROVED                    Codex reacted 👍 and left no new feedback
#   CODEX_FEEDBACK reviews=N inline=N comments=N
#   PR_NOT_OPEN state=MERGED|CLOSED
#   PENDING                           (--once only) nothing happened yet
# Run it from inside the repository checkout (gh resolves {owner}/{repo}).

set -u

once=0
if [ "${1:-}" = "--once" ]; then
  once=1
  shift
fi

pr="${1:?pr number required}"
since="${2:?since timestamp required}"
trigger="${3:-}"
bot="${CODEX_BOT_LOGIN:-chatgpt-codex-connector}"
interval="${CODEX_WATCH_INTERVAL:-45}"
by_bot="select(.user.login | startswith(\"$bot\"))"

if [ -n "$trigger" ]; then
  reactions_path="repos/{owner}/{repo}/issues/comments/$trigger/reactions"
else
  reactions_path="repos/{owner}/{repo}/issues/$pr/reactions"
fi

count_since() {
  gh api --paginate "$1" --jq ".[] | $by_bot | select(.$2 > \"$since\") | .id" 2>/dev/null | wc -l | tr -d ' '
}

# Prints the terminal line and returns 0, or prints nothing and returns 1 while pending.
check_once() {
  local state reviews inline comments thumbs
  state=$(gh pr view "$pr" --json state -q .state 2>/dev/null || echo UNKNOWN)
  if [ "$state" = "MERGED" ] || [ "$state" = "CLOSED" ]; then
    echo "PR_NOT_OPEN state=$state"
    return 0
  fi

  reviews=$(count_since "repos/{owner}/{repo}/pulls/$pr/reviews" submitted_at)
  inline=$(count_since "repos/{owner}/{repo}/pulls/$pr/comments" created_at)
  comments=$(count_since "repos/{owner}/{repo}/issues/$pr/comments" created_at)

  # Codex posts a COMMENTED review wrapper around its inline comments; a review with
  # no inline comments and no issue comment is not actionable feedback on its own.
  if [ "${inline:-0}" != "0" ] || [ "${comments:-0}" != "0" ]; then
    echo "CODEX_FEEDBACK reviews=$reviews inline=$inline comments=$comments"
    return 0
  fi

  thumbs=$(gh api "$reactions_path" --jq "[.[] | $by_bot | select(.content == \"+1\")] | length" 2>/dev/null || echo 0)
  if [ "${thumbs:-0}" != "0" ]; then
    echo "CODEX_APPROVED"
    return 0
  fi

  return 1
}

if [ "$once" = "1" ]; then
  check_once || echo "PENDING"
  exit 0
fi

while true; do
  if check_once; then
    exit 0
  fi
  sleep "$interval"
done
