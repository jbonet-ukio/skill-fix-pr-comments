---
name: fix-pr
description: Address the Codex review bot's feedback — and the Claude Code Review bot's comments, when there are any — on a GitHub pull request, or on every PR of a `gh stack`, and loop until Codex reacts 👍 — verify each comment, fix the ones that hold up (with a test), push, reply in the threads, re-request `@codex review` (plus `@claude review` when a Claude finding was fixed), and watch the PR(s). Supports `--claude` / `--codex` to handle only one bot, ignore rules (e.g. skip P3, skip requests for new feature flags), a `stack` mode for stacked PRs, and an optional round cap. Use when the user runs /fix-pr or asks to fix the Codex / Claude review and keep watching the PR until Codex approves.
argument-hint: "[pr-number-or-url] [--claude | --codex] [stack] [rounds: N] [ignore: <rules>]"
---

# Fix the PR until Codex approves

Arguments: `$ARGUMENTS`

- The first token, if it is a number or a PR URL, is the target PR. Otherwise use the PR of the
  current branch.
- `--claude` or `--codex` limits the run to that bot's comments. Without either, both bots are
  handled. See "Bot selection" below.
- `stack` (or `--stack`) switches to **stack mode**: work every open PR of the `gh stack` the
  target PR belongs to, not just the target. See "Stack mode" below.
- `rounds: N` (or `max-rounds: N`) caps the number of fix rounds. **Without it there is no cap**:
  keep looping until Codex 👍s, only ignored comments remain, or one of the explicit stop
  conditions in step 3 / step 7 fires.
- Everything after `ignore:` (or `skip:`) is a `;`-separated list of **ignore rules** for this run.
  `no-default-ignores` disables the defaults file for this run.

## 0. Update the skill

Before anything else, run `~/.claude/skills/fix-pr/update.sh` once. It pulls the latest version
of this skill and prints one line:

- `FIX_PR_UPDATED <old> -> <new>` (followed by the new commits) → the instructions you are
  reading are the old version. Read `~/.claude/skills/fix-pr/SKILL.md` again and follow that
  one; don't run `update.sh` a second time.
- `FIX_PR_UP_TO_DATE …` → carry on.
- `FIX_PR_UPDATE_SKIPPED …` or `FIX_PR_UPDATE_FAILED …` → carry on with the installed version
  and repeat the line in the final report.

Invoking this skill authorizes, **for this PR only** (every PR of the stack in stack mode):
commits, pushes to its branch, replies in Codex's and Claude's review threads, and
`@codex review` / `@claude review` comments.
If the PR gets merged mid-loop, it also authorizes moving the pending fix to **one** follow-up PR
(step 5). In stack mode it additionally authorizes the cascade rebase of the stack's own upper
branches and their `--force-with-lease` push (`gh stack rebase --no-trunk` + `gh stack push`),
because a commit on a lower layer rewrites every layer above it. It never authorizes merging,
rebasing onto trunk, squashing or otherwise rewriting commits, deleting branches, or touching PRs
outside the target (or the stack) — ask for those.

The Codex bot's login is `chatgpt-codex-connector[bot]` (REST) / `chatgpt-codex-connector`
(GraphQL); match it with `startswith("chatgpt-codex-connector")`. All `gh api` paths below use
gh's `{owner}/{repo}` placeholders, so run them from inside the repository checkout.

How Codex signals:
- It reviews automatically when a PR is opened, and again only when someone comments `@codex review`.
  Pushing new commits alone does **not** trigger a review.
- 👀 on the PR / trigger comment = review in progress (not terminal).
- 👍 on the PR (auto-review) or on the `@codex review` comment = no suggestions → done.
- Suggestions arrive as a `COMMENTED` review wrapping inline comments. Each one starts with a
  priority badge (`badge/P1-…`, `badge/P2-…`, `badge/P3-…`; P1 is the most severe).

### The Claude Code Review bot

Some repos also have the managed Claude Code Review app. Its login is `claude[bot]` (REST) /
`claude` (GraphQL, exact match) and its check run is named `Claude Code Review`. It is optional:
when the PR has no Claude review, everything below about Claude is skipped and the run is
Codex-only.

How Claude signals:
- When it reviews depends on the repo setting. The usual one is **once, when the PR is opened**:
  later pushes are not reviewed. A new review needs a top-level PR comment that starts with
  `@claude review` (one review, no subscription). Replying in one of its threads does not start
  a review.
- Its review is a `COMMENTED` review: a summary body plus inline findings. Each finding starts
  with a severity marker: 🔴 important (fix before merging), 🟡 nit (optional), 🟣 pre-existing
  (a bug the PR did not introduce).
- It never 👍s and the check run never fails (conclusion `neutral`). The result is the check
  run's title: `Code review found no issues`, `Code review found N …`, or `Code review declined`
  (the organization's review budget is used up — the review did not run).
- Its next review reads our replies and resolves its own earlier threads when it judges them
  fixed.
- Every review is billed to the organization, so request one only when step 6 says so.

### Bot selection

By default the run handles both bots. `--codex` or `--claude` in the arguments limits it to one.
Echo the selection once at the start, and skip every part of the steps below that belongs to a
bot that is not selected: its threads are not collected, replied to or resolved, its trigger
comment is not posted, and its watcher is not started.

- `--codex`: Codex only. Claude's comments stay untouched, even when the PR has some.
- `--claude`: Claude only. Never post `@codex review`. If the PR has no Claude review and none
  is running, say so and stop. The loop ends when a round fixes no Claude finding (nothing to
  re-request → step 8) or when the re-review comes back with no new findings
  (`CLAUDE_REVIEWED inline=0`). Step 7 starts the Monitor with `watch-claude.sh` alone.

## Ignore rules

Rules come from two places, combined:

1. **Defaults**: `~/.claude/skills/fix-pr/ignore-rules.md` — one rule per `- ` bullet; lines
   starting with `#` and the commented examples are not rules. Skipped with `no-default-ignores`.
   The file is personal: `update.sh` creates it from `ignore-rules.example.md` when it is
   missing, and updates never overwrite it.
2. **This run**: the `ignore:` part of the arguments.

Echo the effective rule list to the user once at the start.

Each rule is one of:

- **Priority** — `P3`, `P2,P3`, `P2 and below`: ignore comments whose badge matches. Mechanical:
  comments with no badge are never ignored by a priority rule, so these never match a Claude
  comment.
- **Claude severity** — `claude nits`, `claude pre-existing`, `claude` (all of them): ignore
  Claude comments whose severity marker matches.
- **Topic** — any plain-language description, e.g. `feature flags`, `naming nits`,
  `changes under test/`: ignore comments whose *main request* is that thing (judge the ask,
  not keyword mentions; a correctness bug that merely touches a flagged code path is not a
  "feature flag" request).

An ignored comment gets no code change and **no reply** (unless the rule says `…and reply`, in
which case reply once with a short, neutral reason). Keep a list of every ignored comment and the
rule that matched it for the report. If an ignored comment describes a likely real defect (crash,
data loss, security, wrong money amounts), still ignore it but call it out at the top of the
report.

## Stack mode

Stacks are managed with the `gh stack` extension (github/gh-stack). Layers are listed bottom →
top, each layer's branch is based on the one below it, and each layer has its own PR that Codex
reviews independently.

**Discover the stack** (from the repository checkout):

```bash
gh stack view --json
```

`branches[]` is ordered bottom → top with `name`, `head`, `pr.number`, `pr.state`, `isMerged`.
If the target PR is not in the locally tracked stack, `gh stack checkout <pr>` pulls the stack
down from GitHub first. If `gh stack view` reports no stack, tell the user and fall back to
single-PR mode on the target.

**Work set** = the layers whose `pr.state` is `OPEN`. Echo the work set (PR number, branch, layer
position) once at the start. Merged layers are skipped; their content already lives in the layers
above.

**A round in stack mode** runs steps 2–3 once per open layer, bottom → top, then steps 4, 6
and 7 once for the whole stack:

1. For each open layer, bottom → top:
   - `git checkout <layer-branch>` (main checkout, no worktrees; the tree must be clean).
   - Collect that PR's Codex and Claude feedback (step 2) and triage/fix it (step 3). Commit on **that
     layer's branch** — a fix belongs to the layer that introduced the code it changes, so if a
     comment on layer 3 is really about code added in layer 1, commit it on layer 1 and reply in
     the layer-3 thread pointing at the commit.
   - Run validation (step 3's last paragraph) on this layer before moving up: each layer must
     compile and pass on its own because CI runs on every PR.
   - If the layer got a commit, cascade it upward right away so the layers above carry it
     before you work on them: `gh stack rebase --no-trunk --upstack`. A conflict here is not
     yours to resolve silently: `gh stack rebase --abort`, stop and ask.
2. Push the whole stack once: `gh stack push` (force-with-lease per branch). Then confirm, for
   every open layer, that `gh pr view <pr> --json headRefOid` matches the local branch tip.
   Re-check every PR's `state` right before pushing (step 4's rule); any layer that got merged
   meanwhile → "Merged layer" below.
3. Reply, resolve and re-request (step 6) on **every PR that got a fix or a decline** in this
   round. Keep each trigger comment's id and timestamp per PR. PRs that had nothing to address
   are not re-requested. `@claude review` goes only on the PRs where a Claude finding was fixed.
4. Watch all triggered PRs together (step 7, stack variant). The next round starts when every
   watched PR has printed a result — from Codex, and from Claude where it was triggered;
   feedback on any layer means another round over the whole work set (layers with no new
   feedback simply have nothing to fix that round).

**Merged layer mid-loop**: re-read `gh stack view --json`. If a layer with pending fixes got
merged, land those fixes on the **lowest still-open layer** (its branch already contains the
merged code), reply in the merged PR's thread `Fixed in #<upper-pr> (<sha>): …` and resolve it.
Only when **every** layer is merged does step 5's single follow-up PR apply. A layer closed
without merge → stop and ask.

**Done** when every open PR of the work set is 👍 (or only ignored comments remain on it) and no
requested Claude review is still pending or left findings to address.

## 1. Resolve the PR and its state

```bash
gh pr view <pr> --json number,url,state,title,headRefName,headRefOid,baseRefName
```

- `state` must be `OPEN`; otherwise go to step 5 (stack mode: see "Merged layer").
- Make sure the active `gh` account can push to the repo (`gh auth status`).
- Work on the PR branch in the main checkout (no worktrees). If the working tree is dirty with
  unrelated changes, stop and ask. Pull the branch so local HEAD == `headRefOid`.
- Stack mode: discover the stack and the work set now (see "Stack mode").

## 2. Collect the Codex and Claude feedback to address

Unresolved Codex and Claude review threads. Keep `bot`, `thread_id` (needed to resolve the thread
in step 6) and `comment_id` (needed to reply). `priority` is the Codex badge (`P1`…`P3`) or the
Claude severity (`important`, `nit`, `pre-existing`):

```bash
gh api graphql -F owner='{owner}' -F repo='{repo}' -F pr=<pr> -f query='
query($owner:String!,$repo:String!,$pr:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$pr){
  reviewThreads(first:100){nodes{id isResolved isOutdated comments(first:30){nodes{databaseId author{login} path line createdAt body}}}}}}}' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved | not)
        | .comments.nodes[0] as $c
        | (if ($c.author.login | startswith("chatgpt-codex-connector")) then "codex"
           elif $c.author.login == "claude" then "claude" else empty end) as $bot
        | {bot: $bot, thread_id: .id, comment_id: $c.databaseId, created_at: $c.createdAt, path: $c.path, line: $c.line,
           priority: (if $bot == "codex" then (($c.body | capture("badge/(?<p>P[0-9])-") | .p) // "none")
                      else (($c.body | capture("^(?<s>🔴|🟡|🟣)") | {"🔴": "important", "🟡": "nit", "🟣": "pre-existing"}[.s]) // "none") end),
           replies: [.comments.nodes[1:][] | .author.login], body: $c.body}'
```

Read Claude's review summary too. It says what Claude checked, and whether it left findings out
("found and not posted", "outside the scope of this re-review"):

```bash
gh api --paginate repos/{owner}/{repo}/pulls/<pr>/reviews \
  --jq '.[] | select(.user.login == "claude[bot]") | {submitted_at, commit: .commit_id[0:10], body}'
```

If Claude's first review is still running (its check run on the PR head is not `completed`), wait
for it with `watch-claude.sh` (step 7, `since` = PR creation time) before triaging, so its
findings land in this round. Never request a first Claude review on a PR that has none.

First round: take all of them. Later rounds: only threads with `created_at` after the last
trigger of **that bot on that PR** (`since`; stack mode keeps one per PR and bot). Also check
Codex's top-level PR comments in later rounds:

```bash
gh api --paginate repos/{owner}/{repo}/issues/<pr>/comments \
  --jq '.[] | select(.user.login | startswith("chatgpt-codex-connector")) | select(.created_at > "<since>") | {id, body}'
```

Skip threads that already have our reply explaining a fix or a decline, unless the bot answered
again.
If there is no Codex review yet and none is pending, post `@codex review` (step 6) and watch.
If Codex already 👍'd the latest request and nothing is unresolved, report done (stack mode: that
PR is done; continue with the other layers).

## 3. Triage and fix

First apply the ignore rules and set the matches aside. If **every** remaining comment is
ignored, don't change code or re-request a review — go to step 8 (Codex won't 👍 a review whose
comments are still there, and asking again just repeats them). Stack mode: that PR is done for
this run; continue with the other layers.

For each remaining comment, verify the claim against the code before acting — read the code and
trace the data flow; the bot is often right but not always.

- **Holds up** → fix it. Smallest change that addresses the root cause, following the project's
  CLAUDE.md / AGENTS.md conventions. Add or adjust a test that reproduces the problem, and confirm
  it **fails without the fix and passes with it** (temporarily copy the fixed file to the
  scratchpad, restore the old line, run the test, copy it back — never `git stash`).
- **Doesn't hold up** → no code change; reply in the thread with the concrete reason (cite
  `file:line`).
- **Needs a product decision** → ask the user before changing behavior.
- Codex or Claude repeats a point you already declined with reasons → stop and ask the user.

Claude comments go through the same triage, with these differences:

- 🟡 nits are still verified and fixed when they hold up (Claude's "no need to push a fix" note
  is about merging, not about this run). A fix that changes no behavior (a comment, a name)
  needs no new test.
- 🟣 pre-existing findings are not this PR's change: no code change and no reply; list them in
  the report for the user to decide.
- When Codex and Claude flag the same thing, fix it once and reply in both threads.

After the **last** edit, run the project's pre-push validation (e.g. `make checks` where it
exists, otherwise the checks listed in CLAUDE.md / AGENTS.md) and the affected tests. Don't push
red. Stack mode: do this per layer that got a commit, on that layer's branch.

## 4. Commit and push

- One commit per round and per PR; message follows the PR's convention (e.g. the ticket prefix of
  the PR title: `ABC-1234: Ignore discarded transactions in the totals`; stacks keep their
  `[n/N]` marker: `ABC-1234 [2/3]: …`).
- **Right before pushing**, re-check `gh pr view <pr> --json state -q .state` is `OPEN`
  (teammates merge approved PRs fast). If not → step 5.
- `git push`, then confirm `git ls-remote origin refs/heads/<branch>` and
  `gh pr view <pr> --json headRefOid` both equal local HEAD (GitHub may lag a few seconds).
  Stack mode: `gh stack push` instead of `git push`, then do the same confirmation for every
  open layer.
- A `[new branch]` line when pushing to a branch that already had a PR is a red flag: the PR was
  merged and its branch deleted → step 5.

## 5. The PR was merged (or closed) mid-loop

Stack mode: see "Merged layer mid-loop" first; this step applies when the whole stack is merged.

- **Closed without merge** → stop and ask.
- **Merged, nothing pending** → report and stop.
- **Merged with pending fix commits**:
  1. Never keep pushing to the old branch. If a push already re-created it, tell the user and
     offer to delete it (don't delete without a yes).
  2. `git fetch origin <base>`, create a new branch from `origin/<base>` named after the fix,
     `git cherry-pick` only the commits not in the base, re-run validation.
  3. Push and open a follow-up PR using the repo's PR template (`.github/pull_request_template.md`
     if present), referencing the merged PR and the Codex comment it addresses. Then reply in the
     original thread on the merged PR (`Fixed in #<new-pr> (<sha>): …`) and resolve it (step 6).
  4. Continue the loop on the new PR (same ignore rules). Codex auto-reviews new PRs, so watch it
     **without** a trigger comment (step 7) using the PR creation time as `since`.

## 6. Reply and re-request the review

Only after the push is confirmed (step 4):

- Reply in each addressed thread (fixed or declined — not ignored ones):
  `gh api repos/{owner}/{repo}/pulls/<pr>/comments/<comment-id>/replies -f body="Fixed in <sha>: <what changed>"`
  (or the decline reason).
- **Resolve each fixed thread** (fixed only — declined and ignored threads stay open for human
  reviewers):
  ```bash
  gh api graphql -F id=<thread_id> -f query='
  mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' \
    --jq '.data.resolveReviewThread.thread.isResolved'
  ```
  It must print `true`; if it fails (e.g. missing permission), say so in the report rather than
  retrying.
- Post the trigger and keep its id and timestamp:
  ```bash
  gh api repos/{owner}/{repo}/issues/<pr>/comments -f body="@codex review" --jq '.id, .created_at'
  ```
  Stack mode: one trigger per PR that got a fix or a decline this round; keep `(pr, id,
  created_at)` for each.
- **Claude**: if this round's commit fixed at least one Claude finding on the PR, ask Claude to
  review again. Declines alone don't (its next review reads the replies anyway). First see
  whether a review of the new head already started by itself (repos set to review every push):
  ```bash
  gh api "repos/{owner}/{repo}/commits/<head-sha>/check-runs?per_page=100" \
    --jq '.check_runs[] | select(.app.slug == "claude") | {status, title: .output.title}'
  ```
  A run that is `queued` or `in_progress` → don't post, just watch it. Otherwise post the
  trigger as its own top-level comment (never in the same comment as `@codex review`: Codex puts
  its 👍 on that one) and keep its timestamp as Claude's `since` for that PR:
  ```bash
  gh api repos/{owner}/{repo}/issues/<pr>/comments -f body="@claude review" --jq '.created_at'
  ```

## 7. Watch until Codex reacts

Start a `Monitor` (load it with ToolSearch if it is deferred), `timeout_ms: 1800000`, from the
repository checkout:

```bash
~/.claude/skills/fix-pr/watch-codex.sh <pr> <since> [<trigger-comment-id>]
```

Omit the trigger id when watching a freshly opened PR (the 👍 then lands on the PR itself). The
script polls every 45s and prints exactly one line before exiting:

| Output | Next |
|---|---|
| `CODEX_APPROVED` | Done → step 8. |
| `CODEX_FEEDBACK reviews=N inline=N comments=N` | Back to step 2 with `since` = trigger time. If every new comment is ignored, or the only new item is a Codex note saying it found no issues, stop → step 8. |
| `PR_NOT_OPEN state=…` | Step 5. |

**Stack mode** watches every triggered PR in one Monitor:

```bash
~/.claude/skills/fix-pr/watch-stack.sh <pr>,<since>[,<trigger-comment-id>] [<pr>,<since>[,<trigger>] ...]
```

It prints one `<pr> <result>` line per PR as each one lands (same results as above) and exits
when all of them have one. Act on the lines per PR: any `CODEX_FEEDBACK` → another round over the
work set; `PR_NOT_OPEN` → "Merged layer mid-loop"; all `CODEX_APPROVED` → step 8.

**When a Claude review is pending** (requested in step 6, or already running), chain its watcher
after the Codex one in the same Monitor command, so the Monitor ends when both bots are done:

```bash
~/.claude/skills/fix-pr/watch-codex.sh <pr> <since> <trigger-comment-id>; ~/.claude/skills/fix-pr/watch-claude.sh <pr>,<claude-since>
```

Stack mode: `watch-stack.sh <specs…>; watch-claude.sh <pr>,<claude-since> [<pr>,<claude-since> …]`
with one spec per PR that has a Claude review pending. It prints one line per PR:

| Output | Next |
|---|---|
| `<pr> CLAUDE_REVIEWED inline=0 title=Code review found no issues` | Claude is done on that PR. |
| `<pr> CLAUDE_REVIEWED inline=N title=…` (N > 0) | New findings → back to step 2 with Claude's `since`. |
| `<pr> CLAUDE_REVIEWED … title=Code review declined` | The review did not run (budget). Don't re-request; say so in the report. |
| `<pr> PR_NOT_OPEN state=…` | Step 5. |

Any other title with `inline=0` (`title=unknown`, `… skipped — no new changes`, `… not repeated —
earlier findings still open`): read Claude's latest review summary (step 2) before deciding.

Start the next round only when every watcher has printed its line: pushing while a bot is still
reviewing makes it review a stale commit. The run is done when Codex's result is terminal
(`CODEX_APPROVED` or only-ignored feedback) **and** Claude left nothing new to address.

While watching, don't poll by hand — end the turn with a one-line status. If the monitor expires
with no event, re-arm it (stack mode: only with the PRs that have not printed yet); after ~90
minutes without a reaction from a watched bot, stop and tell the user (the bot may be down or
not enabled on the repo).

There is **no default cap** on fix rounds. If `rounds: N` was given, stop after N fix rounds and
summarize the open comments for the user. Otherwise the loop only ends on 👍, on only-ignored
comments, or on one of the stop-and-ask conditions (repeated declined point, product decision,
rebase conflict, closed PR, Codex silent ~90 minutes).

## 8. Report

Give the user:

- the PR link (and follow-up PR, if one was opened); stack mode: every PR of the work set with
  its layer position;
- each round's fixes with their commit SHAs (and whether their threads were resolved), and
  comments declined with the reason — per PR in stack mode;
- **ignored comments**: priority, `path:line`, one-line summary, and the rule that matched — with
  any likely real defect flagged first;
- the final Codex state: 👍, or "stopped: only ignored comments remain" (per PR in stack mode);
  if a `rounds:` cap stopped the loop, say so and list what is still open;
- the Claude state, when the PR has a Claude review: findings fixed / declined, 🟣 pre-existing
  findings left for the user, how many `@claude review` requests were posted, and the title of
  its last check run (flag `Code review declined`);
- leftovers, e.g. a re-created branch to delete or comments left on an already-merged PR.
