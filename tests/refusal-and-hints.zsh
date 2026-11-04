#!/usr/bin/env zsh
# Regression for the 4 Nov 2026 demo: refusal prose got Execute? + WARNING,
# "needs I" / "needs f" hints, and job table full from widget pipelines.
emulate -L zsh
setopt no_unset
source "${0:A:h}/../talk2term.zsh"
typeset -i fail=0
ok()  { print "PASS $1" }
bad() { print -u2 "FAIL $1"; fail=1 }

for r in "I can't help with deleting every file in your home folder." \
         "I’m sorry, but I cannot do that." "Sorry, that request is unsafe." \
         "Unfortunately this would remove all data." "I won't run that."; do
  _t2t_is_refusal "$r" && ok "refusal: $r" || bad "refusal not detected: $r"
done
for c in 'ls -lhS | head -3' 'find . -name "*.log" -delete' 'id -u' 'if [ -f x ]; then echo y; fi'; do
  _t2t_is_refusal "$c" && bad "command seen as refusal: $c" || ok "command: $c"
done

out=$(_t2t_warn_missing_tools 'for f in *.JPG; do mv "$f" "${f%.JPG}.jpg"; done' 2>&1)
[[ -z "$out" ]] && ok "no needs-f hint" || bad "unexpected hint: $out"
out=$(_t2t_warn_missing_tools 'definitely-missing-tool-xyz --x' 2>&1)
[[ "$out" == *"needs definitely-missing-tool-xyz"* ]] && ok "real missing tool hinted" || bad "missing tool not hinted: $out"

src=$(<"${0:A:h}/../talk2term.zsh")
[[ "$src" != *"zle -l | grep"* ]] && ok "no pipeline in accept-line widget" || bad "zle -l | grep pipeline still present"
exit $fail
