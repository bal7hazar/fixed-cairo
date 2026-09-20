# glam.cairo

@AGENTS.md

## Claude-specific

- The main session is the orchestrator (see `docs/PLAN.md`); porters are sub-agents launched with
  worktree isolation, one module each, one pull request each.
- Work in the provided worktree only; never `cd` to the main checkout; never use bare `git stash`.
