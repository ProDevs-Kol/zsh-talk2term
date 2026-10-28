#!/bin/zsh
# Regression for the 27 Oct 2026 daily test:
# find -path logs/keep -prune -o … -delete removed logs/keep/old3.log
# and the destructive warning fired 0/12.
#
# Usage: zsh tests/dangerous-command.zsh

emulate -L zsh
setopt err_exit no_unset pipe_fail

plugin_dir=${0:A:h:h}
source "$plugin_dir/talk2term.zsh"

fail() {
  print -u2 "FAIL: $*"
  exit 1
}

expect_dangerous() {
  local cmd="$1"
  if _t2t_is_dangerous_command "$cmd"; then
    return 0
  fi
  fail "expected a destructive warning for: $cmd"
}

expect_safe() {
  local cmd="$1"
  if _t2t_is_dangerous_command "$cmd"; then
    fail "expected no destructive warning for: $cmd"
  fi
}

# Daily-test commands that must warn.
expect_dangerous "find logs -path logs/keep -prune -o -name '*.log' -mtime +30 -print -delete"
expect_dangerous "lsof -ti:8765 | xargs -r kill -9"
expect_dangerous "kill -9 4321"
expect_dangerous "kill -SIGKILL 4321"
expect_dangerous "kill -s KILL 4321"
expect_dangerous "git filter-repo --path secrets.env --force"
expect_dangerous "git filter-branch -- --all"
expect_dangerous "git push --force origin main"
expect_dangerous "git push -f origin main"
expect_dangerous "git reset --hard HEAD~1"

# Ordinary commands must stay quiet.
expect_safe "ls -la"
expect_safe "find logs -name '*.log' -print"
expect_safe "git status"
expect_safe "git push origin main"
expect_safe "git reset --soft HEAD~1"
expect_safe "kill -TERM 4321"
expect_safe "docker container prune -f"

bad="find logs -path logs/keep -prune -o -name '*.log' -mtime +30 -print -delete"
_t2t_find_prune_delete_conflict "$bad" || fail "prune+delete was not refused"

# The execute path must consult the conflict check before eval.
src="$plugin_dir/talk2term.zsh"
conflict_line=$(grep -n '_t2t_find_prune_delete_conflict "$command"' "$src" | head -1 | cut -d: -f1)
eval_line=$(grep -n 'eval "$command"' "$src" | head -1 | cut -d: -f1)
[[ -n "$conflict_line" && -n "$eval_line" && "$conflict_line" -lt "$eval_line" ]] \
  || fail "prune+delete refusal is not before eval (conflict=$conflict_line eval=$eval_line)"

root=$(mktemp -d)
cd "$root"
mkdir -p logs/keep
touch -t 202001010000 logs/old.log logs/keep/old3.log
touch logs/recent.log

# The plugin refuses this command, so the protected file must survive.
if _t2t_find_prune_delete_conflict "$bad"; then
  :
else
  eval "$bad"
fi
[[ -f logs/keep/old3.log ]] || fail "protected logs/keep/old3.log was deleted"

# The depth-safe form still deletes the old log outside logs/keep.
find logs -name '*.log' -mtime +30 -not -path 'logs/keep/*' -delete
[[ -f logs/keep/old3.log ]] || fail "safe -not -path form deleted logs/keep/old3.log"
[[ ! -f logs/old.log ]] || fail "safe form left logs/old.log in place"
[[ -f logs/recent.log ]] || fail "safe form deleted a recent log"

rm -rf "$root"
print "ok: destructive warning and prune/delete refusal"
