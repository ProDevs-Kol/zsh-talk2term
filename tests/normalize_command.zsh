#!/usr/bin/env zsh
# Exercises _t2t_normalize_command for fenced and backticked replies.
emulate -L zsh
setopt no_unset

source "${0:A:h}/../talk2term.zsh"

typeset -i fail=0

check() {
  local name="$1" expected_status="$2" expected="$3" input="$4"
  local out rc
  out=$(_t2t_normalize_command "$input")
  rc=$?
  if (( rc != expected_status )); then
    print -u2 "FAIL $name status=$rc expected=$expected_status"
    fail=1
    return
  fi
  if [[ "$out" != "$expected" ]]; then
    print -u2 "FAIL $name"
    print -u2 "  out=[$out]"
    print -u2 "  expected=[$expected]"
    fail=1
    return
  fi
  print "PASS $name"
}

fenced='```bash
for f in *.png; do convert "$f" "${f%.png}.jpg" & done; wait
```'
plain_png='for f in *.png; do convert "$f" "${f%.png}.jpg" & done; wait'
backticked='`lsof -ti:8765 | xargs -r kill -9`'
plain_kill='lsof -ti:8765 | xargs -r kill -9'
multi='```bash
echo one
```
```bash
echo two
```'

check "bash fence" 0 "$plain_png" "$fenced"
check "backticks" 0 "$plain_kill" "$backticked"
check "plain command" 0 "ls -la" "ls -la"
check "one substitution" 0 'echo `date`' 'echo `date`'
check "two fences" 2 "" "$multi"
check "two backtick lines" 2 "" '`echo one`
`echo two`'

if (( fail )); then
  exit 1
fi
print "all passed"
