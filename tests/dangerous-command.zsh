#!/bin/zsh
# Regression for the 27–28 Oct 2026 daily tests:
# find -path … -prune -o … -delete removed the path the user meant to keep,
# jq filters were built without reading the file, and the destructive
# warning fired 0 times.
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
expect_dangerous "find cache -path cache/pinned -prune -o -type f -name '*.tmp' -mtime +7 -delete"
expect_dangerous "lsof -ti:8765 | xargs -r kill -9"
expect_dangerous "kill -9 4321"
expect_dangerous "kill -SIGKILL 4321"
expect_dangerous "kill -s KILL 4321"
expect_dangerous "fuser -k 9123/tcp"
expect_dangerous "pkill -9 node"
expect_dangerous "pkill -SIGKILL node"
expect_dangerous "git filter-repo --path secrets.env --force"
expect_dangerous "git filter-branch -- --all"
expect_dangerous "git push --force origin main"
expect_dangerous "git push -f origin main"
expect_dangerous "git reset --hard ORIG_HEAD"
expect_dangerous "git reset --hard HEAD~1"

# Ordinary commands, and the TERM-first stop forms, must stay quiet.
expect_safe "ls -la"
expect_safe "find logs -name '*.log' -print"
expect_safe "git status"
expect_safe "git push origin main"
expect_safe "git reset --soft HEAD~1"
expect_safe "kill -TERM 4321"
expect_safe "kill 4321"
expect_safe "fuser -k -TERM 9123/tcp"
expect_safe "fuser -k -SIGTERM 9123/tcp"
expect_safe "pkill -TERM node"
expect_safe "docker container prune -f"

bad="find cache -path cache/pinned -prune -o -type f -name '*.tmp' -mtime +7 -delete"
_t2t_find_prune_delete_conflict "$bad" || fail "prune+delete was not refused"

# The execute path must consult the conflict check before eval.
src="$plugin_dir/talk2term.zsh"
conflict_line=$(grep -n '_t2t_find_prune_delete_conflict "$command"' "$src" | head -1 | cut -d: -f1)
eval_line=$(grep -n 'eval "$command"' "$src" | head -1 | cut -d: -f1)
[[ -n "$conflict_line" && -n "$eval_line" && "$conflict_line" -lt "$eval_line" ]] \
  || fail "prune+delete refusal is not before eval (conflict=$conflict_line eval=$eval_line)"

root=$(mktemp -d)
cd "$root"
mkdir -p cache/pinned logs/keep
touch -t 202001010000 cache/old.tmp cache/pinned/keep.tmp logs/old.log logs/keep/old3.log
touch cache/recent.tmp logs/recent.log

# The plugin refuses this command, so the protected file must survive.
if _t2t_find_prune_delete_conflict "$bad"; then
  :
else
  eval "$bad"
fi
[[ -f cache/pinned/keep.tmp ]] || fail "protected cache/pinned/keep.tmp was deleted"
[[ -f cache/old.tmp ]] || fail "refused command still deleted cache/old.tmp"

# The depth-safe form deletes the old file outside the pinned directory.
find cache -type f -name '*.tmp' -mtime +7 ! -path 'cache/pinned/*' -delete
[[ -f cache/pinned/keep.tmp ]] || fail "safe form deleted cache/pinned/keep.tmp"
[[ ! -f cache/old.tmp ]] || fail "safe form left cache/old.tmp in place"
[[ -f cache/recent.tmp ]] || fail "safe form deleted a recent tmp file"

# A nested JSON object must be described by its real paths, not a guessed top-level array.
# Values stay out of the sample.
printf '%s\n' '{"meta":{"generated":"secret-value"},"data":{"services":[{"name":"billing","status":"down"},{"name":"mailer","status":"down"},{"name":"api","status":"up"}]}}' > services.json
printf '%s\n' 'API_TOKEN=secret' > .env
sample=$(_t2t_attach_file_samples "print the name of every service whose status is down in services.json")
[[ "$sample" == *"FILE STRUCTURE"* ]] || fail "services.json was not sampled"
[[ "$sample" == *"data.services.0.name"* ]] || fail "sample missed data.services.0.name: $sample"
[[ "$sample" == *"data.services.0.status"* ]] || fail "sample missed data.services.0.status: $sample"
[[ "$sample" != *"billing"* ]] || fail "sample included a JSON value"
[[ "$sample" != *"secret-value"* ]] || fail "sample included a nested JSON value"
env_sample=$(_t2t_attach_file_samples "show .env")
[[ "$env_sample" != *"FILE STRUCTURE"* ]] || fail ".env was sampled"
[[ "$env_sample" != *"API_TOKEN"* ]] || fail ".env contents were sent"

rm -rf "$root"
print "ok: destructive warning, prune/delete refusal, and file sample"
