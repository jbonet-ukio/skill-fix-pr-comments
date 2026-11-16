# fix-pr

A [Claude Code](https://claude.com/claude-code) skill that works through the review bots'
comments on a GitHub pull request until they have nothing left to say.

`/fix-pr` reads the comments left by the **Codex** and **Claude Code Review** bots, checks each
one against the code, fixes the ones that hold up (with a test), pushes, replies in the threads,
asks the bots to review again, and waits for the result. It repeats until Codex reacts 👍 and
Claude has no new findings.

## Install

```bash
git clone https://github.com/jbonet-ukio/skill-fix-pr-comments ~/.claude/skills/fix-pr
```

That is all. Start a new Claude Code session and `/fix-pr` is available.

Requirements:

- [`gh`](https://cli.github.com) logged in with an account that can push to your repo.
- The Codex and/or Claude Code Review app enabled on the repo.
- Optional, for stacked PRs: the [`gh stack`](https://github.com/github/gh-stack) extension.

## Updates

The skill updates itself. Every `/fix-pr` starts by pulling this repository
(`update.sh`, fast-forward only), so you always run the latest version. A failed update
(offline, local edits to the skill's files) never blocks the run; it is reported at the end.

To update by hand: `git -C ~/.claude/skills/fix-pr pull`.

## Usage

Run it from the checkout of the repository the PR belongs to.

| Command | What it does |
|---|---|
| `/fix-pr` | The PR of the current branch, both bots. |
| `/fix-pr 1234` | PR 1234 (a PR URL works too). |
| `/fix-pr --claude` | Only the Claude bot's comments. |
| `/fix-pr --codex` | Only the Codex bot's comments. |
| `/fix-pr 1234 stack` | Every open PR of the `gh stack` that PR 1234 belongs to. |
| `/fix-pr rounds: 2` | Stop after two fix rounds. |
| `/fix-pr ignore: P3; naming nits` | Skip comments that match these rules. |

Options can be combined: `/fix-pr 1234 --claude rounds: 1 ignore: claude nits`.

What a run is allowed to do, on that PR only: commit, push to its branch, reply in the bots'
threads, resolve the threads it fixed, and post `@codex review` / `@claude review`. It never
merges, squashes or deletes branches.

Each `@claude review` is a paid review for your organization. The skill requests one only after
it fixed a Claude finding.

## Ignore rules

Rules decide which comments the skill leaves alone:

- **Priority** (Codex): `P3`, `P2,P3`, `P2 and below`.
- **Claude severity**: `claude nits`, `claude pre-existing`, `claude`.
- **Topic**: plain language, e.g. `feature flags`, `naming nits`, `changes under test/`.

Pass them per run with `ignore:`, or make them your default in
`~/.claude/skills/fix-pr/ignore-rules.md`. That file is created on the first run, is yours, and
is never touched by updates. `/fix-pr no-default-ignores` skips it for one run.

## Uninstall

```bash
rm -rf ~/.claude/skills/fix-pr
```
