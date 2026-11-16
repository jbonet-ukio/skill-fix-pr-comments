# Default ignore rules for /fix-pr
#
# One rule per "- " bullet. They apply to every /fix-pr run, combined with the
# rules passed on the command line (`/fix-pr 123 ignore: P3; naming nits`).
# Run `/fix-pr <pr> no-default-ignores` to skip this file for one run.
#
# Rule kinds:
#   Priority: P3 | P2,P3 | P2 and below   (matches the Codex badge; no badge = never ignored)
#   Claude:   claude nits | claude pre-existing | claude   (matches the Claude bot's 🔴/🟡/🟣 marker)
#   Topic:    plain language describing what the comment asks for, e.g.
#             feature flags | naming nits | changes under test/ | docs and comments
#   Append "and reply" to post a short reason in the thread instead of skipping silently.
#
# Examples (not active — move one below the line to enable it):
#   - P3
#   - feature flags
#   - feature flags and reply
#
# ---- active rules ----
