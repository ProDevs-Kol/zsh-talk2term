#!/bin/zsh
# Regression for PRO-8470 / 9 Nov 2026 daily honest test:
# `yes | ssh-keygen -f …` silently overwrote an existing private key and the
# danger check stayed quiet. "no prompts" must not mean "overwrite".
#
# Usage: zsh tests/ssh-keygen-overwrite.zsh

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

# Ticket acceptance: yes | into ssh-keygen must be flagged.
expect_dangerous 'yes | ssh-keygen -f k'
expect_dangerous "mkdir -p keys && yes | ssh-keygen -t ed25519 -f keys/deploy_ed25519 -C deploy-ci -N '' -q"
expect_dangerous 'yes | rm -i important.txt'
expect_dangerous "ssh-keygen -t ed25519 -f keys/deploy_ed25519 -C deploy-ci -N '' -q <<< y"
expect_dangerous "ssh-keygen -t ed25519 -f keys/deploy_ed25519 -N '' <<< 'y'"
expect_dangerous "echo y | ssh-keygen -t ed25519 -f keys/deploy_ed25519 -N ''"
expect_dangerous "echo yes | ssh-keygen -f k"
expect_dangerous "printf y | ssh-keygen -f k"

# Plain keygen (stops on an existing file / no auto-yes) stays quiet.
expect_safe "ssh-keygen -t ed25519 -f keys/deploy_ed25519 -C deploy-ci -N '' -q"
expect_safe "mkdir -p keys && [ ! -e keys/deploy_ed25519 ] && ssh-keygen -t ed25519 -f keys/deploy_ed25519 -C deploy-ci -N '' -q"
expect_safe 'ls -la'

bad="mkdir -p keys && yes | ssh-keygen -t ed25519 -f keys/deploy_ed25519 -C deploy-ci -N '' -q"
safe=$(_t2t_rewrite_ssh_keygen_overwrite "$bad")
[[ "$safe" != *'yes |'* ]] || fail "rewrite left yes | in place: $safe"
[[ "$safe" == *'[ ! -e keys/deploy_ed25519 ] && ssh-keygen'* ]] \
  || fail "rewrite missed existence guard: $safe"
[[ "$safe" == *"-f keys/deploy_ed25519"* ]] || fail "rewrite dropped -f path: $safe"
[[ "$safe" == *"mkdir -p keys"* ]] || fail "rewrite dropped mkdir: $safe"

here=$(_t2t_rewrite_ssh_keygen_overwrite "ssh-keygen -t ed25519 -f k -N '' <<< y")
[[ "$here" != *'<<<'* ]] || fail "rewrite left here-string: $here"
[[ "$here" == *'[ ! -e k ] && ssh-keygen'* ]] || fail "here-string rewrite missed guard: $here"

echoed=$(_t2t_rewrite_ssh_keygen_overwrite "echo y | ssh-keygen -f k -N ''")
[[ "$echoed" != *'echo y |'* ]] || fail "rewrite left echo y |: $echoed"
[[ "$echoed" == *'[ ! -e k ] && ssh-keygen'* ]] || fail "echo rewrite missed guard: $echoed"

plain=$(_t2t_rewrite_ssh_keygen_overwrite "ssh-keygen -t ed25519 -f k -N ''")
[[ "$plain" == "ssh-keygen -t ed25519 -f k -N ''" ]] || fail "plain ssh-keygen was rewritten: $plain"

# Probe: existing key hash must stay unchanged when the rewritten command runs.
root=$(mktemp -d)
cd "$root"
mkdir -p keys
ssh-keygen -t ed25519 -f keys/deploy_ed25519 -C seed -N '' -q
before=$(shasum -a 256 keys/deploy_ed25519 | awk '{print $1}')
set +e
eval "$safe"
rc=$?
set -e
after=$(shasum -a 256 keys/deploy_ed25519 | awk '{print $1}')
[[ "$before" == "$after" ]] || fail "rewritten command overwrote the key ($before -> $after)"
(( rc != 0 )) || fail "rewritten command exited 0 when the key already existed"
pub=$(ssh-keygen -l -f keys/deploy_ed25519.pub)
[[ "$pub" == *seed* ]] || fail "public key comment changed: $pub"

# Happy path still creates the key when absent.
rm -f keys/deploy_ed25519 keys/deploy_ed25519.pub
eval "$safe"
[[ -f keys/deploy_ed25519 && -f keys/deploy_ed25519.pub ]] \
  || fail "rewritten command did not create a new key"
pub=$(ssh-keygen -l -f keys/deploy_ed25519.pub)
[[ "$pub" == *deploy-ci* ]] || fail "new key comment wrong: $pub"

rm -rf "$root"
print "ok: ssh-keygen overwrite danger check, rewrite, and probe"
