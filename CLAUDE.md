# fixed-cairo

@AGENTS.md

## Claude-specific

- The orchestrator session lives in `glam-cairo` (see its `docs/ORCHESTRATOR.md`); sub-agents
  working on this repository are launched from there through the local `claude` / `codex` CLIs in
  their own worktree, one task each, one pull request each.
- Work in the provided worktree only; never `cd` to the main checkout; never use bare `git stash`.
