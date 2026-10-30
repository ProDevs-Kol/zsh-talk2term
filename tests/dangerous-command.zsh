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

print "ok: destructive warning, prune/delete refusal, file sample, and shell safety"
