#!/usr/bin/env bash
# Watches every PR of a stack until Codex has reacted to each one.
#
# Usage: watch-stack.sh <pr>,<since-iso8601>[,<trigger-comment-id>] [...]
#
#   One spec per PR being watched, e.g.
#     watch-stack.sh 123,2026-10-01T15:42:41Z,3456789 124,2026-10-01T15:42:50Z,3456790
#   Omit the trigger id for a freshly opened PR (the 👍 then lands on the PR itself).
#
# Prints one line per PR as soon as that PR gets a terminal result, prefixed with
# the PR number, and exits when every PR has one:
#   123 CODEX_APPROVED
#   124 CODEX_FEEDBACK reviews=1 inline=2 comments=0
#   125 PR_NOT_OPEN state=MERGED
# Run it from inside the repository checkout (gh resolves {owner}/{repo}).

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
interval="${CODEX_WATCH_INTERVAL:-45}"

if [ "$#" -eq 0 ]; then
  echo "usage: watch-stack.sh <pr>,<since>[,<trigger>] [...]" >&2
  exit 2
fi

pending=("$@")

while [ "${#pending[@]}" -gt 0 ]; do
  still=()
  for spec in "${pending[@]}"; do
    IFS=, read -r pr since trigger <<<"$spec"
    if [ -z "${pr:-}" ] || [ -z "${since:-}" ]; then
      echo "bad spec: $spec (expected <pr>,<since>[,<trigger>])" >&2
      exit 2
    fi
    result=$("$here/watch-codex.sh" --once "$pr" "$since" "${trigger:-}")
    if [ "$result" = "PENDING" ]; then
      still+=("$spec")
    else
      echo "$pr $result"
    fi
  done
  pending=("${still[@]+"${still[@]}"}")
  if [ "${#pending[@]}" -gt 0 ]; then
    sleep "$interval"
  fi
done
