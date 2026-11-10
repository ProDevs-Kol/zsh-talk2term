#!/bin/zsh
# Regression for PRO-8475 / 10 Nov 2026 daily test 17:
# answers that append `Host jump… ForwardAgent yes` after `Host *` never
# take effect (ssh first-match). The plugin must rewrite to prepend +
# cat-over, and `ssh -G` must show forwardagent yes for that host only.
#
# Usage: zsh tests/ssh-config-host-order.zsh

emulate -L zsh
setopt err_exit no_unset pipe_fail

plugin_dir=${0:A:h:h}
source "$plugin_dir/talk2term.zsh"

fail() {
  print -u2 "FAIL: $*"
  exit 1
}

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT

cfg="$sandbox/ssh_config"
printf '%s\n' 'Host *' '    ForwardAgent no' '    ServerAliveInterval 30' > "$cfg"
chmod 600 "$cfg"
mode_before=$(stat -f '%Lp' "$cfg" 2>/dev/null || stat -c '%a' "$cfg")

bad_cmd=$(cat <<'EOF'
awk 'BEGIN{found=0} /^[[:space:]]*[Hh]ost[[:space:]]/ { n=split($0,p,/[[:space:]]+/); isjump=0; for(i=2;i<=n;i++) if(p[i]=="jump.example.test") isjump=1; if(isjump){ inblock=1; found=1; print; print "    ForwardAgent yes"; next } inblock=0 } /^[[:space:]]*[Mm]atch[[:space:]]/ { inblock=0 } inblock && /^[[:space:]]*[Ff]orwardAgent[[:space:]]/ { next } { print } END{ if(!found) printf "\nHost jump.example.test\n    ForwardAgent yes\n" }' cfg/ssh_config > cfg/ssh_config.tmp && mv cfg/ssh_config.tmp cfg/ssh_config
EOF
)
# Point the fixture path at the sandbox file.
bad_cmd=${bad_cmd//cfg\/ssh_config/$cfg}

rewritten=$(_t2t_rewrite_ssh_config_host_order "$bad_cmd")
[[ "$rewritten" != "$bad_cmd" ]] || fail "expected a rewrite for END-append Host block"
[[ "$rewritten" == *"{ printf 'Host jump.example.test\\n    ForwardAgent yes\\n\\n'; cat ${cfg}; }"* ]] \
  || fail "rewrite missing prepend form: $rewritten"
[[ "$rewritten" == *"cat ${cfg}.tmp > ${cfg}"* ]] || fail "rewrite must cat-over to keep mode: $rewritten"
[[ "$rewritten" != *"mv ${cfg}.tmp"* ]] || fail "rewrite must not mv the staging temp: $rewritten"

# Self-temp rm -f on the rewritten form must not trip the destructive warning.
_t2t_is_dangerous_command "$rewritten" && fail "prepend+cat-over+rm staging temp must not warn"

# Execute the rewritten command and prove ssh first-match.
eval "$rewritten"
mode_after=$(stat -f '%Lp' "$cfg" 2>/dev/null || stat -c '%a' "$cfg")
[[ "$mode_after" == "$mode_before" ]] || fail "file mode changed from $mode_before to $mode_after"

jump_fa=$(ssh -G -F "$cfg" jump.example.test | grep -i '^forwardagent' | head -n1)
other_fa=$(ssh -G -F "$cfg" other.example.test | grep -i '^forwardagent' | head -n1)
[[ "${jump_fa:l}" == *"yes"* ]] || fail "jump.example.test expected forwardagent yes, got: $jump_fa"
[[ "${other_fa:l}" == *"no"* ]] || fail "other.example.test expected forwardagent no, got: $other_fa"

# Leave-alone: already a prepend form.
good=$rewritten
again=$(_t2t_rewrite_ssh_config_host_order "$good")
[[ "$again" == "$good" ]] || fail "prepend form must not be rewritten again"

# Leave-alone: unrelated command.
plain="ls -la"
[[ "$(_t2t_rewrite_ssh_config_host_order "$plain")" == "$plain" ]] || fail "unrelated command rewritten"

print "ok: ssh_config Host block prepend rewrite (PRO-8475)"
