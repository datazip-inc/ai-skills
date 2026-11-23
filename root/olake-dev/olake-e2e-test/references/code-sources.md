# Code sources

How to get each repo's code for a stack, and what to record about it in `stack.md`.
`<repo>` is `olake`, `olake-ui` or `olake-helm`, all public on `github.com/datazip-inc`.

## Local checkout

Used when the user wants their local changes tested: uncommitted work, unpushed commits, or "my current changes".
The path comes from the plugin settings, and the skill asks for it when it is empty.

Collect, without changing anything in the checkout (it fetches only `origin/<base>`):

```bash
${CLAUDE_SKILL_DIR}/scripts/checkout-info.sh <path> [base]
```

`base` is the branch the change will merge into: `staging` unless the user names another.
It prints `branch`, `sha`, `behind`, `ahead`, `dirty`, `diff_hash`, `run_tag` and the files changed against the base.
Show "behind by N" in the intake message when `behind` is above 0.
Builds run in place, so the user's uncommitted changes are included.

## Managed clone

Used for a pushed branch, tag or SHA. No local path is needed.
One clone per repo lives in `~/.olake-dev/repos/`, and each run gets its own worktree.

```bash
git clone -q --filter=blob:none https://github.com/datazip-inc/<repo>.git ~/.olake-dev/repos/<repo>   # first time only
git -C ~/.olake-dev/repos/<repo> fetch -q origin
git -C ~/.olake-dev/repos/<repo> worktree add --detach <run-dir>/src/<repo> origin/<branch>             # or a tag or SHA
${CLAUDE_SKILL_DIR}/scripts/checkout-info.sh <run-dir>/src/<repo> [base]
```

A ref that does not resolve after the fetch is a blocker: show the exact error and ask the user to check the name or push the branch.

On a reused stack the worktree already exists, and `worktree add` fails on it.
Move it to the new ref instead; it is the skill's own worktree, not a user's checkout:

```bash
git -C ~/.olake-dev/repos/<repo> fetch -q origin
git -C <run-dir>/src/<repo> checkout -q --detach origin/<branch>                                        # or a tag or SHA
${CLAUDE_SKILL_DIR}/scripts/checkout-info.sh <run-dir>/src/<repo> [base]
```

At cleanup, remove the worktree and keep the clone, so the next run only fetches:

```bash
git -C ~/.olake-dev/repos/<repo> worktree remove <run-dir>/src/<repo>
```

## Released images

Used for a repo that is not part of the change: no build, and no `latest`.
Pin the newest published release tag, so every test of the same code uses the same images:

```bash
${CLAUDE_SKILL_DIR}/scripts/release-tag.sh olakego/source-<driver>   # or olakego/ui, olakego/ui-worker
```

It reads the `vX.Y.Z` tags of the image's repo (olake for drivers, olake-ui for `olakego/ui`, olake-helm for `olakego/ui-worker`) and prints `tag=<tag>` for the newest one that is published.
A `skipped=` line means a newer tag has no image yet: say so in the report.
Record each pinned tag in `stack.md` and in the report setup.
