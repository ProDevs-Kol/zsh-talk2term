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
expect_dangerous "git clean -fd"
expect_dangerous "git clean -fdx"
expect_dangerous "git checkout -f -- file"
expect_dangerous "git branch -D feature-x"
expect_dangerous "rm -f data.json.tmp"
expect_dangerous "rm -r -f data.json.tmp"
expect_dangerous "docker image prune -f"
expect_dangerous "yes | ssh-keygen -f k"
expect_dangerous "ssh-keygen -f k <<< y"
expect_dangerous "echo y | ssh-keygen -f k"

# Staging-only rm -f (own .tmp / mktemp) must stay quiet — PRO-8475 minor.
expect_safe "{ printf 'x\n'; cat nginx.conf; } > nginx.conf.tmp && cat nginx.conf.tmp > nginx.conf && rm -f nginx.conf.tmp"
expect_safe 'tmp=$(mktemp) && curl -sS -D "$tmp" https://example.test/ -o out && rm -f "$tmp"'
expect_safe "awk '1' cfg/ssh_config > cfg/ssh_config.tmp && cat cfg/ssh_config.tmp > cfg/ssh_config && rm -f cfg/ssh_config.tmp"
# 11 Nov 2026 daily rephrase: mktemp var `t` + rm -f "$t" (cat-over ssh_config).
expect_safe 'f=cfg/ssh_config; t=$(mktemp) && { printf "Host build.example.test\n    User deploy\n    Port 2222\n\n"; cat "$f"; } > "$t" && cat "$t" > "$f" && rm -f "$t"'

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
expect_safe "git clean -n"
expect_safe "git clean --dry-run"
expect_safe "git checkout -b feature-x"
expect_safe "git checkout main"
expect_safe "git branch -d feature-x"
expect_safe "rm data.json.tmp"
expect_safe "docker image prune"
expect_safe "ssh-keygen -t ed25519 -f k -N ''"
expect_safe "mkdir -p keys && [ ! -e keys/deploy_ed25519 ] && ssh-keygen -t ed25519 -f keys/deploy_ed25519 -N ''"

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
sample=$(_t2t_attach_file_samples "print the name of every service whose status is down in services.json" 2>/dev/null)
[[ "$sample" == *"FILE STRUCTURE"* ]] || fail "services.json was not sampled"
[[ "$sample" == *"data.services.0.name"* ]] || fail "sample missed data.services.0.name: $sample"
[[ "$sample" == *"data.services.0.status"* ]] || fail "sample missed data.services.0.status: $sample"
[[ "$sample" != *"billing"* ]] || fail "sample included a JSON value"
[[ "$sample" != *"secret-value"* ]] || fail "sample included a nested JSON value"
env_sample=$(_t2t_attach_file_samples "show .env")
[[ "$env_sample" != *"FILE STRUCTURE"* ]] || fail ".env was sampled"
[[ "$env_sample" != *"API_TOKEN"* ]] || fail ".env contents were sent"

# Secret names and credential assignments must not be uploaded.
# Values below are fake markers, not real credentials.
printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' 'FAKEKEYBODY' '-----END OPENSSH PRIVATE KEY-----' > id_ed25519
printf '%s\n' '-----BEGIN EC PRIVATE KEY-----' 'FAKEECDSA' '-----END EC PRIVATE KEY-----' > id_ecdsa
printf '%s\n' 'machine example.com login ada password FAKEPASS123' > .netrc
printf '%s\n' 'apiVersion: v1' 'users:' '- name: fake' '  user:' '    token: FAKETOKEN123' > kubeconfig
printf '%s\n' 'apiVersion: v1' 'users:' '- token: FAKETOKEN456' > prod.kubeconfig
printf '%s\n' '//registry.npmjs.org/:_authToken=FAKENPM123' > .npmrc
printf '%s\n' 'DB_PASSWORD=FAKEDB123' > prod.env
printf '%s\n' 'APP_PASSWORD=FAKEAPP123' > app.env
printf '%s\n' '[default]' 'aws_secret_access_key=FAKEAWS123' > aws_config
printf '%s\n' 'not-a-real-certificate FAKEP12' > client.p12
printf '%s\n' 'not-a-real-certificate FAKEPFX' > client.pfx
printf '%s\n' 'localhost:5432:db:ada:FAKEPGPASS' > .pgpass
printf '%s\n' 'https://ada:FAKEGITPASS@github.com' > .git-credentials
printf '%s\n' '[pypi]' 'password = FAKEPYPI123' > .pypirc
printf '%s\n' '{"password":"FAKETFSTATE"}' > terraform.tfstate
printf '%s\n' 'Host example' 'IdentityFile ~/.ssh/id_ed25519' > config
printf '%s\n' 'password=FAKETXT123' > notes.txt
printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' 'FAKEJSONKEY' > disguised.json
printf '%s\n' '{"aws_secret_access_key":"FAKEAWSJSON"}' > creds.json
printf '%s\n' 'name: web' > app.yaml
printf '%s\n' 'password: FAKEYAML123' > secretish.yaml
printf '\n%s\n%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' 'FAKEKEYNOTE' > keynote.txt
printf '%s\n' 'Authorization: Bearer FAKEREADERTOKEN' > req.log
printf '%s\n' 'DB_PASS=FAKEDBPASS' > settings.txt
printf '%s\n' 'pwd=FAKEPWDVALUE' > local.txt
printf '%s\n' 'passenger=ada' > people.txt
printf '%s\n' 'compass=north' > nav.txt
printf '%s\n' 'name,role' 'billing,admin' > hosts.csv
printf '%s\n' '{"hosts":["web-1"]}' > inventory.json

assert_not_sent() {
  local prompt="$1" marker="$2" sample
  sample=$(_t2t_attach_file_samples "$prompt" 2>/dev/null)
  [[ "$sample" != *"FILE STRUCTURE"* ]] || fail "sampled for: $prompt"
  [[ "$sample" != *"$marker"* ]] || fail "marker leaked for: $prompt :: $sample"
}

assert_not_sent "show the fingerprint of id_ed25519" "FAKEKEYBODY"
assert_not_sent "show the fingerprint of id_ecdsa" "FAKEECDSA"
assert_not_sent "check .netrc syntax" "FAKEPASS123"
assert_not_sent "list contexts in kubeconfig" "FAKETOKEN123"
assert_not_sent "list contexts in prod.kubeconfig" "FAKETOKEN456"
assert_not_sent "what registry does .npmrc use" "FAKENPM123"
assert_not_sent "load prod.env" "FAKEDB123"
assert_not_sent "load app.env" "FAKEAPP123"
assert_not_sent "parse aws_config" "FAKEAWS123"
assert_not_sent "inspect client.p12" "FAKEP12"
assert_not_sent "inspect client.pfx" "FAKEPFX"
assert_not_sent "read .pgpass" "FAKEPGPASS"
assert_not_sent "read .git-credentials" "FAKEGITPASS"
assert_not_sent "read .pypirc" "FAKEPYPI123"
assert_not_sent "parse terraform.tfstate" "FAKETFSTATE"
assert_not_sent "parse config" "IdentityFile"
assert_not_sent "read notes.txt" "FAKETXT123"
assert_not_sent "parse disguised.json" "FAKEJSONKEY"
assert_not_sent "parse creds.json" "FAKEAWSJSON"
assert_not_sent "read secretish.yaml" "FAKEYAML123"
assert_not_sent "read keynote.txt" "FAKEKEYNOTE"
assert_not_sent "read req.log" "FAKEREADERTOKEN"
assert_not_sent "read settings.txt" "FAKEDBPASS"
assert_not_sent "read local.txt" "FAKEPWDVALUE"

yaml_sample=$(_t2t_attach_file_samples "read app.yaml" 2>/dev/null)
[[ "$yaml_sample" == *"FILE STRUCTURE"* ]] || fail "app.yaml was not sampled"
[[ "$yaml_sample" == *"name: web"* ]] || fail "app.yaml structure missing: $yaml_sample"

people_sample=$(_t2t_attach_file_samples "read people.txt" 2>/dev/null)
[[ "$people_sample" == *"passenger=ada"* ]] || fail "passenger assignment was blocked: $people_sample"
nav_sample=$(_t2t_attach_file_samples "read nav.txt" 2>/dev/null)
[[ "$nav_sample" == *"compass=north"* ]] || fail "compass assignment was blocked: $nav_sample"

csv_sample=$(_t2t_attach_file_samples "rows in hosts.csv" 2>/dev/null)
[[ "$csv_sample" == *"name,role"* ]] || fail "csv header missing: $csv_sample"
[[ "$csv_sample" != *"billing"* ]] || fail "csv data row was sent: $csv_sample"

inv=$(_t2t_attach_file_samples "hosts in inventory.json, sorted" 2>/dev/null)
[[ "$inv" == *"hosts"* ]] || fail "comma after the name attached nothing: $inv"
[[ "$inv" != *"web-1"* ]] || fail "json value leaked after comma: $inv"
inv=$(_t2t_attach_file_samples "hosts in inventory.json." 2>/dev/null)
[[ "$inv" == *"FILE STRUCTURE"* ]] || fail "full stop after the name attached nothing"
inv=$(_t2t_attach_file_samples "hosts in (inventory.json)" 2>/dev/null)
[[ "$inv" == *"FILE STRUCTURE"* ]] || fail "parentheses around the name attached nothing"
[[ "$inv" != *"web-1"* ]] || fail "json value leaked from parenthesized name"

notice=$(_t2t_attach_file_samples "show inventory.json" 2>&1 >/dev/null)
[[ "$notice" == *"[talk2term] sent structure of inventory.json to the API"* ]] || fail "missing sample notice: $notice"

# Same file named twice must emit one notice and one FILE STRUCTURE block.
printf '%s\n' 'id-1' 'id-2' > ids.txt
dup_notice=$(_t2t_attach_file_samples "extract from ids.txt unique from ids.txt" 2>&1 >/dev/null)
notice_count=$(print -r -- "$dup_notice" | grep -c 'sent structure of ids.txt' || true)
[[ "$notice_count" == 1 ]] || fail "duplicate sample notice: count=$notice_count body=$dup_notice"
dup_sample=$(_t2t_attach_file_samples "extract from ids.txt unique from ids.txt" 2>/dev/null)
block_count=$(print -r -- "$dup_sample" | grep -c '^--- ids.txt ---' || true)
[[ "$block_count" == 1 ]] || fail "duplicate FILE STRUCTURE block: count=$block_count"

# Quoting hint is once until the marker file exists (not every new shell).
quote_root=$(mktemp -d "${TMPDIR:-/tmp}/t2t-quote.XXXXXX") || fail "mktemp quote root"
quote_marker="$quote_root/quote-warned"
rm -f "$quote_marker"
first=$(T2T_QUOTE_WARN_FILE="$quote_marker" zsh -c '
  emulate -L zsh
  source "'"$plugin_dir"'/talk2term.zsh"
  _t2t_warn_quoting
' 2>&1)
[[ "$first" == *Quote* ]] || fail "first quoting hint missing: $first"
[[ -f "$quote_marker" ]] || fail "quote marker was not written"
second=$(T2T_QUOTE_WARN_FILE="$quote_marker" zsh -c '
  emulate -L zsh
  source "'"$plugin_dir"'/talk2term.zsh"
  _t2t_warn_quoting
' 2>&1)
[[ -z "$second" ]] || fail "quoting hint repeated after marker: $second"
rm -rf "$quote_root"

opt=$(T2T_NO_FILE_SAMPLES=1 _t2t_attach_file_samples "show inventory.json" 2>/dev/null)
[[ "$opt" != *"FILE STRUCTURE"* ]] || fail "T2T_NO_FILE_SAMPLES=1 still sampled"

# Credential directories, symlink targets, and renamed copies.
# HOME is a throwaway directory. Markers are fake.
old_home=$HOME
HOME="$root/fakehome"
mkdir -p "$HOME/.ssh" "$HOME/.gnupg" "$HOME/.aws" "$HOME/.kube" "$HOME/.config/gcloud"
printf '%s\n' 'FAKESSHNOTE' > "$HOME/.ssh/notes.txt"
printf '%s\n' 'FAKEGPGNOTE' > "$HOME/.gnupg/notes.txt"
printf '%s\n' 'FAKEAWSNOTE' > "$HOME/.aws/notes.txt"
printf '%s\n' 'FAKEKUBENOTE' > "$HOME/.kube/notes.txt"
printf '%s\n' 'FAKEGCLOUDNOTE' > "$HOME/.config/gcloud/notes.txt"
printf '%s\n' 'hello-from-home' > "$HOME/ok.txt"
ln -s "$HOME/.ssh/notes.txt" "$root/link.txt"
printf '%s\n' 'client-key-data: FAKECLIENTKEY' 'client-certificate-data: FAKECLIENTCERT' > "$root/kubeconfig.yaml"
printf '%s\n' 'client-key-data: FAKECLUSTERKEY' > "$root/cluster.yaml"
printf '%s\n' '_authToken=FAKECOPYNPM' > "$root/npmrc.txt"
printf '%s\n' 'localhost:5432:db:ada:FAKECOPYPG' > "$root/pgpass.txt"
printf '%s\n' 'https://ada:FAKECOPYGIT@github.com' > "$root/git-credentials.txt"
printf '%s\n' 'FAKEKEYCOPY' > "$root/prod.key.txt"
printf '%s\n' '-----BEGIN PGP PRIVATE KEY BLOCK-----' 'FAKEGPGKEY' > "$root/copy.gpg.txt"
assert_not_sent "read ~/.ssh/notes.txt" "FAKESSHNOTE"
assert_not_sent "read ~/.gnupg/notes.txt" "FAKEGPGNOTE"
assert_not_sent "read ~/.aws/notes.txt" "FAKEAWSNOTE"
assert_not_sent "read ~/.kube/notes.txt" "FAKEKUBENOTE"
assert_not_sent "read ~/.config/gcloud/notes.txt" "FAKEGCLOUDNOTE"
assert_not_sent "read link.txt" "FAKESSHNOTE"
assert_not_sent "read kubeconfig.yaml" "FAKECLIENTKEY"
assert_not_sent "read kubeconfig.yaml" "FAKECLIENTCERT"
assert_not_sent "read cluster.yaml" "FAKECLUSTERKEY"
assert_not_sent "read npmrc.txt" "FAKECOPYNPM"
assert_not_sent "read pgpass.txt" "FAKECOPYPG"
assert_not_sent "read git-credentials.txt" "FAKECOPYGIT"
assert_not_sent "read prod.key.txt" "FAKEKEYCOPY"
assert_not_sent "read copy.gpg.txt" "FAKEGPGKEY"
home_ok=$(_t2t_attach_file_samples "read $HOME/ok.txt" 2>/dev/null)
[[ "$home_ok" == *"hello-from-home"* ]] || fail "a normal file in HOME was blocked: $home_ok"
HOME=$old_home

(
  PATH="$root/bin:$PATH"
  mkdir -p "$root/bin"
  printf '%s\n' '#!/bin/sh' 'exit 1' > "$root/bin/jq"
  chmod +x "$root/bin/jq"
  hash -r
  sample=$(_t2t_attach_file_samples "show services.json" 2>/dev/null)
  [[ "$sample" != *"FILE STRUCTURE"* ]] || exit 1
  [[ "$sample" != *"secret-value"* ]] || exit 1
  [[ "$sample" != *"billing"* ]] || exit 1
) || fail "json sample fell back to raw values when jq failed"

hdr_path=""
curl() {
  local arg
  : > "$root/argv-seen"
  : > "$root/hdr-seen"
  for arg in "$@"; do
    print -r -- "$arg" >> "$root/argv-seen"
    if [[ "$arg" == @* ]]; then
      hdr_path="${arg#@}"
      cat "$hdr_path" > "$root/hdr-seen"
    fi
  done
}
_t2t_curl "super-secret-key" -sS https://example.test >/dev/null
[[ -n "$hdr_path" && ! -e "$hdr_path" ]] || fail "auth header file was left on disk"
[[ "$(cat "$root/hdr-seen")" == "Authorization: Bearer super-secret-key" ]] || fail "header file missing bearer token"
[[ "$(cat "$root/argv-seen")" != *super-secret-key* ]] || fail "api key was present in curl argv"

rm -rf "$root"

# 30 Oct 2026: separators and cron fields are not package names.
hint=$(_t2t_warn_missing_tools 'i=0; while :; do echo hi; done' 2>&1 || true)
[[ "$hint" != *"needs ;"* ]] || fail "semicolon was treated as a package: $hint"
[[ "$hint" != *"needs while"* ]] || fail "while was treated as a package: $hint"
hint=$(_t2t_warn_missing_tools '*/5 * * * * flock -n /tmp/sync.lock /opt/sync.sh >/dev/null 2>&1' 2>&1 || true)
[[ "$hint" != *"needs */5"* ]] || fail "cron field was treated as a package: $hint"
[[ "$hint" != *"needs *:"* ]] || fail "glob was treated as a package: $hint"
hint=$(_t2t_warn_missing_tools 'this-binary-is-not-real --version' 2>&1 || true)
[[ "$hint" == *"needs this-binary-is-not-real"* ]] || fail "missing binary was not reported: $hint"

# A crontab line is detected and is not a normal command.
_t2t_is_crontab_line '*/5 * * * * flock -n /tmp/sync.lock /opt/sync.sh >/dev/null 2>&1' \
  || fail "crontab line was not detected"
_t2t_is_crontab_line '5 0 * * 1 /opt/sync.sh' || fail "numeric crontab line was not detected"
_t2t_is_crontab_line '@daily /opt/sync.sh' || fail "@daily line was not detected"
_t2t_is_crontab_line 'ls -la' && fail "ls was treated as a crontab line"
_t2t_is_crontab_line 'echo *' && fail "echo star was treated as a crontab line"
_t2t_is_crontab_line 'crontab -l' && fail "crontab -l was treated as a schedule line"

# exit must not close this shell, and its variables must not leak.
# err_exit is on, so a real exit would kill this test before the checks.
shell_out=$(
  setopt no_err_exit
  unset t2t_leak_code t2t_leak_i
  _t2t_run_returned_command 't2t_leak_i=7; t2t_leak_code=503; exit 1' 2>&1 || true
  print STILL_HERE
  print "LEAK_I=${t2t_leak_i-unset}"
  print "LEAK_CODE=${t2t_leak_code-unset}"
) || true
[[ "$shell_out" == *STILL_HERE* ]] || fail "exit closed the shell: $shell_out"
[[ "$shell_out" == *LEAK_I=unset* ]] || fail "i leaked into the shell: $shell_out"
[[ "$shell_out" == *LEAK_CODE=unset* ]] || fail "code leaked into the shell: $shell_out"
[[ "$shell_out" == *"Running in a subshell"* ]] || fail "exit ran without the subshell note: $shell_out"

cd /tmp
start_pwd=$PWD
cd_probe=$(mktemp -d)
_t2t_run_returned_command "cd ${(q)cd_probe}"
[[ "$PWD" == "$cd_probe" ]] || fail "cd did not stay in the current shell (pwd=$PWD)"
cd "$start_pwd"
rmdir "$cd_probe"

cd_out=$(
  setopt no_err_exit
  _t2t_run_returned_command 'cd /tmp; exit 1' || true
  print "PWD_AFTER=$PWD"
) || true
[[ "$cd_out" == *"PWD_AFTER=$PWD"* ]] || fail "cd with exit changed the shell or closed it: $cd_out"

# Quoted exit text is not the exit builtin.
_t2t_has_bare_exit 'echo "exit 1"' && fail "quoted exit was treated as the builtin"
_t2t_has_bare_exit 'echo exit-now' && fail "exit-now was treated as the builtin"
_t2t_has_bare_exit 'false || exit 1' || fail "bare exit was missed"

# 10 Nov 2026: top-level assignments must not leak into the user shell.
# Daily test: d=2025-12-31; printf … left d set under naive eval.
assign_out=$(
  setopt no_err_exit
  unset t2t_iso_d
  _t2t_run_returned_command 't2t_iso_d=2025-12-31; print -r -- $t2t_iso_d' 2>&1 || true
  print "LEAK_D=${t2t_iso_d-unset}"
) || true
[[ "$assign_out" == *2025-12-31* ]] || fail "assignment command produced no output: $assign_out"
[[ "$assign_out" == *LEAK_D=unset* ]] || fail "top-level assignment leaked: $assign_out"
[[ "$assign_out" == *"assignments do not change this shell"* ]] || fail "assignment ran without the subshell note: $assign_out"
_t2t_has_top_level_assignment 't2t_iso_d=2025-12-31; print x' || fail "top-level assignment was missed"
_t2t_has_top_level_assignment 'export T2T_EXPORT_PROBE=1' && fail "export assignment was treated as top-level"
unset T2T_EXPORT_PROBE
_t2t_run_returned_command 'export T2T_EXPORT_PROBE=ok'
[[ "${T2T_EXPORT_PROBE-}" == ok ]] || fail "export did not stick in the current shell"
unset T2T_EXPORT_PROBE

# 1 Nov 2026: keep the interactive shell's options (no emulate -L).
setopt nonomatch
nonomatch_out=$(_t2t_run_returned_command 'print *.no-such-t2t-xyz' 2>&1) || true
[[ "$nonomatch_out" == *'*.no-such-t2t-xyz'* ]] || fail "nonomatch literal was lost: $nonomatch_out"
[[ "$nonomatch_out" != *'no matches found'* ]] || fail "emulate reset nonomatch: $nonomatch_out"
unsetopt nonomatch

# 1 Nov 2026: curl exit 28 must not be parsed as the API body.
# The convert call used to redirect stderr into the body file, so the
# timeout text was reported as "not JSON".
if grep -F -A 6 '_t2t_curl "$api_key" -sS -X POST' "$src" | grep -F -q '> "$tmpfile" 2>&1'; then
  fail "convert still mixes curl stderr into the body"
fi

timeout_key=$(mktemp)
chmod 600 "$timeout_key"
print -r -- 'test-key' > "$timeout_key"
old_key_file=$T2T_KEY_FILE
old_api_url=$T2T_API_URL
T2T_KEY_FILE=$timeout_key
T2T_API_URL='https://talk2term.prodevs.in/api/zsh-talk2term/convert'
curl() {
  print -u2 'curl: (28) Operation timed out after 30001 milliseconds with 0 bytes received'
  return 28
}
timeout_dir=$(mktemp -d)
timeout_out=$(
  cd "$timeout_dir" || exit 1
  _t2t_handle 't2t: list files' 2>&1 || true
) || true
T2T_KEY_FILE=$old_key_file
T2T_API_URL=$old_api_url
rm -f "$timeout_key"
rm -rf "$timeout_dir"
unset -f curl
[[ "$timeout_out" == *"did not answer within 30 seconds"* ]] || fail "timeout was not reported: $timeout_out"
[[ "$timeout_out" != *"Raw (truncated)"* ]] || fail "timeout stderr was treated as the body: $timeout_out"
[[ "$timeout_out" != *"not JSON"* ]] || fail "timeout was parsed as a bad JSON body: $timeout_out"

print "ok: destructive warning, prune/delete refusal, file sample, and shell safety"
