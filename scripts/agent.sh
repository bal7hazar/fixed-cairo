#!/usr/bin/env bash
# Orchestrator helper: start or resume a sub-agent in its worktree, DETACHED from the calling
# session (setsid + nohup), so that it survives a restart of the orchestrator session (observed:
# agents started as plain background children die with the session). See docs/ORCHESTRATOR.md.
#
# usage: scripts/agent.sh <task> <claude|codex> <model> <new|resume> <prompt> [codex-session-id] [effort]
#   worktree : <main checkout>/.claude/worktrees/cli-<task>   (create it first with git worktree add)
#   log      : <main checkout>/.claude/worktrees/logs/<task>.log   (+ <task>.pid, <task>.last.md for codex)
#   wait     : tail --pid="$(cat <task>.pid)" -f /dev/null
set -euo pipefail
task=$1 cli=$2 model=$3 mode=$4 prompt=$5 sid=${6:-} effort=${7:-high}
main=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
W=$main/.claude/worktrees
L=$W/logs
wt=$W/cli-$task
mkdir -p "$L"
cd "$wt"
case "$cli:$mode" in
  claude:new)
    cmd=(claude -p "$prompt" --model "$model" --dangerously-skip-permissions --name "$task"
      --output-format text) ;;
  claude:resume)
    cmd=(claude --continue -p "$prompt" --model "$model" --dangerously-skip-permissions
      --output-format text) ;;
  codex:new)
    cmd=(codex exec -C "$wt" -m "$model" -c "model_reasoning_effort=$effort"
      --dangerously-bypass-approvals-and-sandbox -o "$L/$task.last.md" "$prompt") ;;
  codex:resume)
    cmd=(codex exec resume "$sid" -m "$model" -c "model_reasoning_effort=$effort"
      --dangerously-bypass-approvals-and-sandbox -o "$L/$task.last.md" "$prompt") ;;
  *) echo "usage: agent.sh <task> <claude|codex> <model> <new|resume> <prompt> [sid] [effort]" >&2
    exit 2 ;;
esac
echo "--- $(date -u +%FT%TZ) $cli $model $mode" >> "$L/$task.log"
# $0 of the inner shell is the log file, "$@" the agent command line.
setsid nohup bash -c '"$@" < /dev/null >> "$0" 2>&1; echo "exit=$? $(date -u +%FT%TZ)" >> "$0"' \
  "$L/$task.log" "${cmd[@]}" > /dev/null 2>&1 &
echo "$!" > "$L/$task.pid"
echo "$task: started, pid $(cat "$L/$task.pid"), log $L/$task.log"
