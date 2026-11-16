#!/usr/bin/env bash
# Watches one or more PRs until the Claude Code Review bot finishes the review
# requested with "@claude review".
#
# Usage: watch-claude.sh <pr>,<since-iso8601> [<pr>,<since-iso8601> ...]
#
#   since   only Claude reviews / check runs / comments after this instant count
#           (use the time the review was requested, UTC, e.g. 2026-10-01T15:42:41Z)
#
# Prints one line per PR as soon as that PR gets a terminal result, and exits when
# every PR has one:
#   123 CLAUDE_REVIEWED inline=N title=<title of the "Claude Code Review" check run>
#   123 PR_NOT_OPEN state=MERGED|CLOSED
# inline is the number of new inline findings; the title says how the run ended
# ("Code review found no issues", "Code review declined", ...). title=unknown means
# the review landed before the check run of the PR head was marked completed.
# Run it from inside the repository checkout (gh resolves {owner}/{repo}).

set -u

bot="${CLAUDE_BOT_LOGIN:-claude[bot]}"
interval="${CLAUDE_WATCH_INTERVAL:-45}"

if [ "$#" -eq 0 ]; then
  echo "usage: watch-claude.sh <pr>,<since> [...]" >&2
  exit 2
fi

count_since() {
  gh api --paginate "$1" --jq ".[] | select(.user.login == \"$bot\") | select(.$2 > \"$since\") | .id" 2>/dev/null | wc -l | tr -d ' '
}

# Prints the terminal line and returns 0, or prints nothing and returns 1 while pending.
check_once() {
  local view state sha title reviews inline
  view=$(gh pr view "$pr" --json state,headRefOid -q '.state + " " + .headRefOid' 2>/dev/null || echo "UNKNOWN")
  state="${view%% *}"
  sha="${view#* }"
  if [ "$state" = "MERGED" ] || [ "$state" = "CLOSED" ]; then
    echo "PR_NOT_OPEN state=$state"
    return 0
  fi
  [ "$state" = "OPEN" ] || return 1

  title=$(gh api "repos/{owner}/{repo}/commits/$sha/check-runs?per_page=100" --jq "
    [.check_runs[] | select(.app.slug == \"claude\") | select(.status == \"completed\") | select(.completed_at > \"$since\")]
    | sort_by(.completed_at) | last | .output.title // empty" 2>/dev/null)
  reviews=$(count_since "repos/{owner}/{repo}/pulls/$pr/reviews" submitted_at)
  if [ -z "$title" ] && [ "${reviews:-0}" = "0" ]; then
    return 1
  fi

  inline=$(count_since "repos/{owner}/{repo}/pulls/$pr/comments" created_at)
  echo "CLAUDE_REVIEWED inline=$inline title=${title:-unknown}"
}

pending=("$@")

while [ "${#pending[@]}" -gt 0 ]; do
  still=()
  for spec in "${pending[@]}"; do
    IFS=, read -r pr since <<<"$spec"
    if [ -z "${pr:-}" ] || [ -z "${since:-}" ]; then
      echo "bad spec: $spec (expected <pr>,<since>)" >&2
      exit 2
    fi
    if result=$(check_once); then
      echo "$pr $result"
    else
      still+=("$spec")
    fi
  done
  pending=("${still[@]+"${still[@]}"}")
  if [ "${#pending[@]}" -gt 0 ]; then
    sleep "$interval"
  fi
done
