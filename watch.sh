#!/usr/bin/env bash
# Watches pull requests until the review bots have answered the latest review request.
#
# Usage: watch.sh <spec> [<spec> ...]
#
#   One spec per pending review:
#     codex,<pr>,<since>[,<trigger-comment-id>]
#     claude,<pr>,<since>
#
#   since               only reviews/comments created after this instant count (UTC, e.g.
#                       2026-10-01T15:42:41Z). Use the time the review was requested.
#   trigger-comment-id  id of the "@codex review" comment. Without it, Codex's 👍 is read
#                       from the PR itself (auto-review of a freshly opened PR).
#
#   Example, one PR with both bots, and a second PR of a stack with Codex only:
#     watch.sh codex,123,2026-10-01T15:42:41Z,3456789 claude,123,2026-10-01T15:42:45Z \
#              codex,124,2026-10-01T15:42:50Z,3456790
#
# Prints one line per spec as soon as it has a result, and exits when every spec has one:
#   123 CODEX_APPROVED                               Codex reacted 👍 and left no new feedback
#   123 CODEX_FEEDBACK reviews=N inline=N comments=N
#   123 CLAUDE_REVIEWED inline=N title=<title of the "Claude Code Review" check run>
#   123 PR_NOT_OPEN state=MERGED|CLOSED              (once per spec of that PR)
# For Claude, inline is the number of new inline findings and the title says how the run
# ended ("Code review found no issues", "Code review declined", ...). title=unknown means
# the review landed before the check run of the PR head was marked completed.
# Run it from inside the repository checkout (gh resolves {owner}/{repo}).

set -u

codex_bot="${CODEX_BOT_LOGIN:-chatgpt-codex-connector}"
claude_bot="${CLAUDE_BOT_LOGIN:-claude[bot]}"
interval="${FIX_PR_WATCH_INTERVAL:-45}"

usage() {
  echo "usage: watch.sh codex,<pr>,<since>[,<trigger>] | claude,<pr>,<since> [...]" >&2
  exit 2
}

[ "$#" -gt 0 ] || usage
for spec in "$@"; do
  IFS=, read -r bot pr since trigger <<<"$spec"
  case "${bot:-}" in codex | claude) ;; *) echo "bad spec: $spec" >&2 && usage ;; esac
  [ -n "${pr:-}" ] && [ -n "${since:-}" ] || { echo "bad spec: $spec" >&2 && usage; }
done

# count_since <api-path> <timestamp-field> <jq filter selecting the bot's items>
# A failed request counts as 0 (still pending): gh prints the error body on stdout,
# which must not be mistaken for feedback.
count_since() {
  local out
  out=$(gh api --paginate "$1" --jq ".[] | $3 | select(.$2 > \"$since\") | .id" 2>/dev/null) || out=""
  printf '%s' "$out" | grep -c .
}

check_codex() {
  local by_bot reviews inline comments reactions_path thumbs
  by_bot="select(.user.login | startswith(\"$codex_bot\"))"
  reviews=$(count_since "repos/{owner}/{repo}/pulls/$pr/reviews" submitted_at "$by_bot")
  inline=$(count_since "repos/{owner}/{repo}/pulls/$pr/comments" created_at "$by_bot")
  comments=$(count_since "repos/{owner}/{repo}/issues/$pr/comments" created_at "$by_bot")

  # Codex posts a COMMENTED review wrapper around its inline comments; a review with
  # no inline comments and no issue comment is not actionable feedback on its own.
  if [ "${inline:-0}" != "0" ] || [ "${comments:-0}" != "0" ]; then
    echo "CODEX_FEEDBACK reviews=$reviews inline=$inline comments=$comments"
    return 0
  fi

  if [ -n "${trigger:-}" ]; then
    reactions_path="repos/{owner}/{repo}/issues/comments/$trigger/reactions"
  else
    reactions_path="repos/{owner}/{repo}/issues/$pr/reactions"
  fi
  thumbs=$(gh api "$reactions_path" --jq "[.[] | $by_bot | select(.content == \"+1\")] | length" 2>/dev/null) || thumbs=0
  if [ "${thumbs:-0}" != "0" ]; then
    echo "CODEX_APPROVED"
    return 0
  fi
  return 1
}

check_claude() {
  local by_bot title reviews inline
  by_bot="select(.user.login == \"$claude_bot\")"
  title=$(gh api "repos/{owner}/{repo}/commits/$sha/check-runs?per_page=100" --jq "
    [.check_runs[] | select(.app.slug == \"claude\") | select(.status == \"completed\") | select(.completed_at > \"$since\")]
    | sort_by(.completed_at) | last | .output.title // empty" 2>/dev/null) || title=""
  reviews=$(count_since "repos/{owner}/{repo}/pulls/$pr/reviews" submitted_at "$by_bot")
  if [ -z "$title" ] && [ "${reviews:-0}" = "0" ]; then
    return 1
  fi
  inline=$(count_since "repos/{owner}/{repo}/pulls/$pr/comments" created_at "$by_bot")
  echo "CLAUDE_REVIEWED inline=$inline title=${title:-unknown}"
}

# Prints the result line and returns 0, or prints nothing and returns 1 while pending.
check() {
  local view state sha
  view=$(gh pr view "$pr" --json state,headRefOid -q '.state + " " + .headRefOid' 2>/dev/null || echo "UNKNOWN")
  state="${view%% *}"
  sha="${view#* }"
  if [ "$state" = "MERGED" ] || [ "$state" = "CLOSED" ]; then
    echo "PR_NOT_OPEN state=$state"
    return 0
  fi
  [ "$state" = "OPEN" ] || return 1
  "check_$bot"
}

pending=("$@")

while [ "${#pending[@]}" -gt 0 ]; do
  still=()
  for spec in "${pending[@]}"; do
    IFS=, read -r bot pr since trigger <<<"$spec"
    if result=$(check); then
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
