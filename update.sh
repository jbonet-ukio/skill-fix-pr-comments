#!/usr/bin/env bash
# Self-update for the fix-pr skill. The skill runs it at the start of every /fix-pr.
#
# Pulls the latest commit of the skill's git checkout (fast-forward only) and prints
# exactly one status line, plus the new commits after an update:
#   FIX_PR_UPDATED <old> -> <new>      SKILL.md may have changed: read it again
#   FIX_PR_UP_TO_DATE <sha>
#   FIX_PR_UPDATE_SKIPPED <reason>     not a git checkout (installed by copying files)
#   FIX_PR_UPDATE_FAILED <reason>      offline, local edits in the way, ...
# It always exits 0: a failed update must never block the skill.

set -u

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Personal default ignore rules: untracked, so updates never touch them.
if [ ! -f "$dir/ignore-rules.md" ] && [ -f "$dir/ignore-rules.example.md" ]; then
  cp "$dir/ignore-rules.example.md" "$dir/ignore-rules.md"
fi

if [ ! -d "$dir/.git" ]; then
  echo "FIX_PR_UPDATE_SKIPPED not a git checkout; reinstall with git clone to get updates"
  exit 0
fi

# Never wait for a password prompt or a dead network.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=10}"

before=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
if ! out=$(git -C "$dir" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=10 pull --ff-only --quiet 2>&1); then
  echo "FIX_PR_UPDATE_FAILED $(printf '%s' "$out" | tail -n 1)"
  exit 0
fi
after=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)

if [ "$before" = "$after" ]; then
  echo "FIX_PR_UP_TO_DATE $after"
else
  echo "FIX_PR_UPDATED $before -> $after"
  git -C "$dir" log --oneline "$before..$after"
fi
