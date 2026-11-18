#!/bin/zsh
# Regression for PRO-8492 / 12–13 Nov 2026 daily tests:
# `$target_offset:linear` is eaten by zsh history modifier `:l`.
# The plugin must brace `$name:` before eval.
#
# Usage: zsh tests/zsh-colon-modifiers.zsh

emulate -L zsh
setopt err_exit no_unset pipe_fail

plugin_dir=${0:A:h:h}
source "$plugin_dir/talk2term.zsh"

fail() {
  print -u2 "FAIL: $*"
  exit 1
}

bad='offset=$target_offset:linear=true measured_I=$mi:measured_TP=$mtp:x'
fixed=$(_t2t_rewrite_zsh_colon_modifiers "$bad")
[[ "$fixed" == *'offset=${target_offset}:linear=true'* ]] \
  || fail "expected braced target_offset: $fixed"
[[ "$fixed" == *'measured_I=${mi}:measured_TP=${mtp}:x'* ]] \
  || fail "expected braced mi/mtp: $fixed"
[[ "$fixed" != *'$target_offset:linear'* ]] \
  || fail "bare \$target_offset:linear still present: $fixed"

already='offset=${target_offset}:linear=true'
[[ "$(_t2t_rewrite_zsh_colon_modifiers "$already")" == "$already" ]] \
  || fail "already-braced form must stay unchanged"

plain='echo hello'
[[ "$(_t2t_rewrite_zsh_colon_modifiers "$plain")" == "$plain" ]] \
  || fail "unrelated command rewritten"

# Prove eval under zsh: bare form breaks, rewritten form keeps :linear.
broken=$(zsh -fc 'target_offset=-0.96; eval "print -r -- offset=\$target_offset:linear=true"')
[[ "$broken" == 'offset=-0.96inear=true' ]] \
  || fail "expected bare form to eat :l, got: $broken"

ok=$(
  cmd=$(_t2t_rewrite_zsh_colon_modifiers 'print -r -- offset=$target_offset:linear=true')
  _t2t_run_returned_command "target_offset=-0.96; $cmd"
)
[[ "$ok" == 'offset=-0.96:linear=true' ]] \
  || fail "expected braced eval to keep :linear, got: $ok"

print "ok: zsh colon-modifier brace rewrite (PRO-8492)"
