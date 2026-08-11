# cleanup-worktree

A Claude Code slash command for the "1 issue = 1 session = 1 worktree" workflow.
After a branch is merged, it tears down what that worktree left behind: the
worktree itself, the local and remote branch, any dev server started for it, and
finally fast-forwards `main`.

```
/cleanup-worktree 11              # by issue number
/cleanup-worktree feat/fairy      # by branch name
/cleanup-worktree                 # the worktree you are currently in
```

The point of the command is the guardrails, not the git commands:

- **Refuses to delete unmerged work.** Merge status is checked with `gh pr` (or
  `git branch --merged` when there is no remote) before anything is removed.
- **Refuses to delete uncommitted work.** A dirty worktree stops the run and is
  reported instead of discarded.
- **Frees per-worktree resources.** Parallel-worktree setups usually pin a port
  or a data directory per worktree; those are released so the next session can
  claim them.
- **Always operates via `git -C <main worktree>`.** Removing a worktree while
  the shell's cwd is inside it destroys the cwd and breaks every command that
  follows — this is the single most common way the cleanup goes wrong.
- **Leaves everything else alone.** Unrelated uncommitted changes and other
  worktrees (parallel sessions) are reported, never touched.

Nothing about the command is repo-specific: the main worktree is resolved from
`git worktree list` rather than hardcoded, and branch/worktree naming is matched
rather than assumed.

## Install

```sh
./install.sh                  # user-level: ~/.claude/commands/
./install.sh /path/to/repo    # project-level: <repo>/.claude/commands/
```

This symlinks `cleanup-worktree.md` into the chosen commands directory. Any
existing file at the target is moved aside as `*.bak.<timestamp>`.
