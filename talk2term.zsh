# talk2term.zsh - Talk2Term ZSH Plugin
#
# Converts natural language to shell commands using Talk2Term API.
#
# Usage:
#   t2t <your prompt>     # Free (Lite)
#   t2t-p <your prompt>   # Paid (Pro)
#
# Requirements: curl, jq
#
# API Key: Store your API key (from /profile) in ~/.talk2term as a single line.
#   Example: echo "sk-..." > ~/.talk2term && chmod 600 ~/.talk2term

# --- OPTION ISOLATION ---
# Prevents user shell options from affecting plugin behavior (and vice versa).
emulate -L zsh
setopt extended_glob no_short_loops

# --- RUNTIME DEPENDENCY CHECK ---
# If installed via antigen/zinit (not install.sh), deps were never checked.
{
  local -a _t2t_missing=()
  (( $+commands[curl] )) || _t2t_missing+=(curl)
  (( $+commands[jq] ))   || _t2t_missing+=(jq)

  if (( ${#_t2t_missing} )); then
    print -P "%F{red}[talk2term]%f Missing dependencies: ${_t2t_missing[*]}" >&2
    print -P "%F{yellow}[talk2term]%f Install with:" >&2
    if (( $+commands[brew] )); then
      print -P "  brew install ${_t2t_missing[*]}" >&2
    elif (( $+commands[apt-get] )); then
      print -P "  sudo apt-get install ${_t2t_missing[*]}" >&2
    elif (( $+commands[pacman] )); then
      print -P "  sudo pacman -S ${_t2t_missing[*]}" >&2
    elif (( $+commands[dnf] )); then
      print -P "  sudo dnf install ${_t2t_missing[*]}" >&2
    else
      print -P "  Please install: ${_t2t_missing[*]}" >&2
    fi
    return 1
  fi
}

_t2t_help() {
  cat <<'EOF'
Talk2Term ZSH Plugin Usage:
  t2t <your prompt>     # Free (Lite)
  t2t-p <your prompt>   # Paid (Pro)
  t2t-credit           # Check credits
  t2t-reset            # Reset conversation context
  t2t-context          # Show recent conversation
  t2t-update           # Update plugin to latest version

Examples:
  t2t list all files modified today
  t2t now show only .js files      # Uses conversation context
  t2t-p find all .py files recursively

Get your API key from: https://talk2term.prodevs.in/profile
EOF
}

# --- SHARED HELPERS ---

# Sanitize a string for safe terminal display — strips ANSI escapes
# and non-printable control characters to prevent terminal manipulation.
_t2t_sanitize_output() {
  # Use actual escape character for portability (macOS sed doesn't support \x1b)
  local ESC=$'\e' BEL=$'\a'
  sed "s/${ESC}\[[0-9;]*[a-zA-Z]//g; s/${ESC}\][^${BEL}]*${BEL}//g; s/${ESC}[^[][^a-zA-Z]*[a-zA-Z]//g" \
    | tr -d '\000-\010\013\014\016-\037\177'
}

# Reset ZLE prompt if running inside the line editor.
_t2t_maybe_reset_prompt() {
  [[ -n $ZLE_LINE_EDITOR ]] && zle reset-prompt
}

# Derive the base URL (strip /convert) for subcommand endpoints.
_t2t_base_url() {
  print -r -- "${T2T_API_URL%/convert}"
}

# Read API key from config file.
# Returns 0 on success (key in $REPLY), 1 on failure (error printed).
_t2t_read_api_key() {
  if [[ ! -f "$T2T_KEY_FILE" ]]; then
    print -u2 "[talk2term] API key file not found: $T2T_KEY_FILE"
    print -u2 "  Create it with: echo 'YOUR_KEY' > $T2T_KEY_FILE && chmod 600 $T2T_KEY_FILE"
    return 1
  fi

  # Enforce strict file permissions — refuse if group/world readable
  local perms
  if [[ "$_T2T_PLATFORM" == "macos" ]]; then
    perms=$(stat -f "%OLp" "$T2T_KEY_FILE" 2>/dev/null)
  else
    perms=$(stat -c "%a" "$T2T_KEY_FILE" 2>/dev/null)
  fi
  if [[ -n "$perms" && "$perms" != "600" && "$perms" != "400" ]]; then
    print -u2 "[talk2term] WARNING: $T2T_KEY_FILE has permissions $perms (should be 600)"
    print -u2 "  Fixing permissions automatically..."
    chmod 600 "$T2T_KEY_FILE" 2>/dev/null || {
      print -u2 "  Could not fix. Run: chmod 600 $T2T_KEY_FILE"
      return 1
    }
  fi

  REPLY=$(head -n 1 "$T2T_KEY_FILE" | tr -d '\r\n')
  if [[ -z "$REPLY" ]]; then
    print -u2 "[talk2term] API key is empty in $T2T_KEY_FILE."
    return 1
  fi
  return 0
}

# Validate API URL to prevent credential exfiltration.
# Allows the official domain, localhost (dev), and user-configured trusted domains.
_t2t_validate_api_url() {
  local url="$1"
  # Allow the official domain
  if [[ "$url" == https://talk2term.prodevs.in/* ]]; then
    return 0
  fi
  # Allow localhost for development
  if [[ "$url" == http://localhost:* || "$url" == http://127.0.0.1:* ]]; then
    return 0
  fi
  # Allow user-configured trusted domains for self-hosted instances
  if [[ -n "$T2T_TRUSTED_DOMAINS" ]]; then
    local _domain
    for _domain in ${(s: :)T2T_TRUSTED_DOMAINS}; do
      if [[ "$url" == ${_domain}/* ]]; then
        return 0
      fi
    done
  fi
  print -u2 "[talk2term] SECURITY: Refusing to send API key to untrusted URL."
  print -u2 "  Current T2T_API_URL: $url"
  print -u2 "  Expected: https://talk2term.prodevs.in/..."
  print -u2 "  If you self-host, set T2T_TRUSTED_DOMAINS before sourcing the plugin."
  return 1
}

# Validate a session ID — must be alphanumeric + dash + underscore only.
# Prevents path traversal via crafted session IDs.
_t2t_validate_session_id() {
  local sid="$1"
  if [[ -z "$sid" || "$sid" == "null" ]]; then
    return 1
  fi
  if [[ "$sid" =~ ^[a-zA-Z0-9_-]{1,128}$ ]]; then
    return 0
  fi
  print -u2 "[talk2term] Warning: invalid session_id format received, ignoring."
  return 1
}

# Build JSON payload safely using jq.
# WHY: Direct string interpolation into JSON allows injection via quotes/backslashes.
_t2t_build_json() {
  if ! (( $+commands[jq] )); then
    print -u2 "[talk2term] jq is no longer available. Please reinstall it."
    return 1
  fi
  jq -n \
    --arg prompt "$1" \
    --arg model "$2" \
    --arg terminal_window_id "$3" \
    --arg session_id "$4" \
    '{prompt: $prompt, model: $model, terminal_window_id: $terminal_window_id, session_id: $session_id}'
}

# Copy text to clipboard — supports macOS, Linux (X11 + Wayland), WSL, MSYS2/Cygwin.
_t2t_clipboard_copy() {
  case "$_T2T_PLATFORM" in
    macos)
      pbcopy
      ;;
    wsl)
      clip.exe
      ;;
    linux)
      if (( $+commands[xclip] )); then
        xclip -selection clipboard
      elif (( $+commands[xsel] )); then
        xsel --clipboard --input
      elif (( $+commands[wl-copy] )); then
        wl-copy
      else
        return 1
      fi
      ;;
    windows-native)
      cat > /dev/clipboard 2>/dev/null || return 1
      ;;
    *)
      return 1
      ;;
  esac
}

# Check if a command looks potentially dangerous.
# Returns 0 if dangerous, 1 if safe.
# Best-effort denylist — cannot catch all destructive commands (e.g. encoded payloads).
_t2t_is_dangerous_command() {
  local cmd="$1"
  local lcmd="${cmd:l}"  # lowercase for all checks

  # Destructive file operations
  [[ "$lcmd" == *"rm -rf"* ]] && return 0
  [[ "$lcmd" == *"rm -fr"* ]] && return 0

  # Filesystem operations
  [[ "$lcmd" == *"mkfs."* ]] && return 0
  [[ "$lcmd" == *"fdisk"* ]] && return 0
  [[ "$lcmd" == *"dd if="*"of=/dev/"* ]] && return 0
  [[ "$lcmd" == *"> /dev/sd"* ]] && return 0
  [[ "$lcmd" == *"> /dev/nvm"* ]] && return 0
  [[ "$lcmd" == *"find / -delete"* ]] && return 0
  [[ "$lcmd" == *"find . -delete"* ]] && return 0
  [[ "$lcmd" == *"shred "* ]] && return 0
  [[ "$lcmd" == *"wipefs"* ]] && return 0

  # Privilege escalation
  [[ "$lcmd" == *"sudo su"* ]] && return 0
  [[ "$lcmd" == *"sudo chmod u+s"* ]] && return 0
  [[ "$lcmd" == *"chmod 777 /"* ]] && return 0
  [[ "$lcmd" == *"chmod -r 777"* ]] && return 0

  # System file modification
  [[ "$lcmd" == *"/etc/passwd"* ]] && return 0
  [[ "$lcmd" == *"/etc/shadow"* ]] && return 0

  # Pipe to interpreter (reverse shells, malicious downloads)
  [[ "$lcmd" == *"| sh"* ]] && return 0
  [[ "$lcmd" == *"| bash"* ]] && return 0
  [[ "$lcmd" == *"| zsh"* ]] && return 0
  [[ "$lcmd" == *"|sh"* ]] && return 0
  [[ "$lcmd" == *"|bash"* ]] && return 0
  [[ "$lcmd" == *"|zsh"* ]] && return 0
  [[ "$lcmd" == *"| python"* ]] && return 0
  [[ "$lcmd" == *"| perl"* ]] && return 0
  [[ "$lcmd" == *"| ruby"* ]] && return 0
  [[ "$lcmd" == *"base64"*"| sh"* ]] && return 0
  [[ "$lcmd" =~ 'nc[[:space:]].*-e[[:space:]]*/bin/' ]] && return 0
  [[ "$lcmd" =~ 'bash[[:space:]]+-i[[:space:]]+>&' ]] && return 0

  # Fork bombs
  [[ "$lcmd" == *":(){:|:&};:"* ]] && return 0

  # sudo with destructive commands
  [[ "$lcmd" == *"sudo rm "* ]] && return 0
  [[ "$lcmd" == *"sudo mkfs"* ]] && return 0
  [[ "$lcmd" == *"sudo dd "* ]] && return 0

  return 1  # Not dangerous
}

# --- CONFIG ---
# typeset -g prevents re-assignment on re-source. Override in .zshrc BEFORE sourcing.
(( ! ${+T2T_API_URL} ))  && typeset -g T2T_API_URL='https://talk2term.prodevs.in/api/zsh-talk2term/convert'
(( ! ${+T2T_KEY_FILE} )) && typeset -g T2T_KEY_FILE="$HOME/.talk2term"

# Optional: additional trusted domains for self-hosted instances
# Set T2T_TRUSTED_DOMAINS="https://myserver.com" before sourcing
(( ! ${+T2T_TRUSTED_DOMAINS} )) && typeset -g T2T_TRUSTED_DOMAINS=""

# --- PLATFORM DETECTION ---
# Cached at source time (no repeated forks).
typeset -g _T2T_PLATFORM
if [[ "$OSTYPE" == darwin* ]]; then
  _T2T_PLATFORM="macos"
elif [[ "$OSTYPE" == linux* ]]; then
  if [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
    _T2T_PLATFORM="wsl"
  else
    _T2T_PLATFORM="linux"
  fi
elif [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
  _T2T_PLATFORM="windows-native"
else
  _T2T_PLATFORM="unknown"
fi

# --- SESSION MANAGEMENT ---
# Generate unique terminal window ID using cryptographic randomness
_t2t_get_terminal_id() {
  # Prefer /dev/urandom for cryptographic randomness
  if [[ -r /dev/urandom ]]; then
    LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom 2>/dev/null | head -c 32
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s:%s:%s:%s' "${TTY}" "$$" "$(date +%s%N)" "$RANDOM$RANDOM$RANDOM" \
      | sha256sum | cut -c1-32
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s:%s:%s:%s' "${TTY}" "$$" "$(date +%s)" "$RANDOM$RANDOM$RANDOM" \
      | shasum -a 256 | cut -c1-32
  else
    printf '%s:%s:%s:%s' "${TTY}" "$$" "$(date +%s)" "$RANDOM$RANDOM$RANDOM" \
      | od -An -tx1 | tr -d ' \n' | cut -c1-32
  fi
}

# Session storage
if [[ -z "$T2T_SESSION_ID" ]]; then
  T2T_TERMINAL_ID=$(_t2t_get_terminal_id)
  T2T_SESSION_ID=""  # Will be set by API response
fi

# --- MAIN FUNCTION ---
_t2t_handle() {
  emulate -L zsh
  local buffer="$1"
  local prefix prompt model resp command err

  if [[ "$buffer" == t2t:* ]]; then
    prefix="t2t:"
    model="lite"
  elif [[ "$buffer" == t2t-p:* ]]; then
    prefix="t2t-p:"
    model="pro"
  else
    return 1  # Not our prefix
  fi

  prompt="${buffer#$prefix}"
  prompt="${prompt## }"  # Trim leading space
  if [[ -z "$prompt" ]]; then
    _t2t_help
    _t2t_maybe_reset_prompt
    return 0
  fi

  # --- Validate API URL ---
  if ! _t2t_validate_api_url "$T2T_API_URL"; then
    _t2t_maybe_reset_prompt
    return 0
  fi

  # --- Read API Key ---
  if ! _t2t_read_api_key; then
    _t2t_maybe_reset_prompt
    return 0
  fi
  local api_key="$REPLY"

  # --- API CALL ---
  local tmpfile
  tmpfile=$(mktemp "${TMPDIR:-/tmp}/t2t.XXXXXX") || {
    print -u2 "[talk2term] Failed to create temp file."
    _t2t_maybe_reset_prompt
    return 0
  }

  printf "[talk2term] Working...\r"
  local json_payload
  json_payload=$(_t2t_build_json "$prompt" "$model" "$T2T_TERMINAL_ID" "$T2T_SESSION_ID")
  # Use always block for guaranteed tmpfile cleanup (avoids trap leakage across functions)
  {
    curl -sS -X POST "$T2T_API_URL" \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $api_key" \
      --max-time 30 \
      --data "$json_payload" \
      > "$tmpfile" 2>&1
    printf "\r%*s\r\n" ${COLUMNS:-80} " " # clear line

    # --- HANDLE RESPONSE ---
    if ! resp=$(cat "$tmpfile"); then
      print -u2 "[talk2term] Error reading API response."
      _t2t_maybe_reset_prompt
      return 0
    fi
  } always {
    rm -f "$tmpfile" 2>/dev/null
  }

  # Check for network or API error
  if [[ -z "$resp" ]]; then
    print -u2 "[talk2term] No response from API."
    _t2t_maybe_reset_prompt
    return 0
  fi

  # Validate response is JSON before parsing
  if ! echo "$resp" | jq empty 2>/dev/null; then
    print -u2 "[talk2term] Invalid response from server (not JSON). Check your network/proxy."
    print -u2 "[talk2term] Raw (truncated): ${resp[1,200]}"
    _t2t_maybe_reset_prompt
    return 0
  fi

  # Parse response fields
  command=$(echo "$resp" | jq -r '.command // empty')
  err=$(echo "$resp" | jq -r '.error // empty')
  local session_id
  session_id=$(echo "$resp" | jq -r '.session_id // empty')

  # Validate and update session ID if provided
  if _t2t_validate_session_id "$session_id"; then
    T2T_SESSION_ID="$session_id"
  fi

  if [[ -n "$err" ]]; then
    # Sanitize error output — strip escape sequences to prevent terminal manipulation
    local err_safe
    err_safe=$(printf '%s' "$err" | _t2t_sanitize_output | head -c 300)
    if [[ "$err_safe" == *"API key"* || "$err_safe" == *"Invalid or inactive"* ]]; then
      print -u2 "[talk2term] Invalid or missing API key. Please check $T2T_KEY_FILE."
    elif [[ "$err_safe" == *"Not enough credits"* || "$err_safe" == *"free limit reached"* ]]; then
      print -u2 "[talk2term] $err_safe"
      print -u2 "  Get more credits at: https://talk2term.prodevs.in"
    elif [[ "$err_safe" == *"deprecated"* ]]; then
      print -u2 "[talk2term] This feature is no longer available. Please update the plugin."
    else
      print -u2 "[talk2term] API error: $err_safe"
    fi
    local suggestion
    suggestion=$(echo "$resp" | jq -r '.suggestion // empty')
    if [[ -n "$suggestion" && "$suggestion" != "null" ]]; then
      local suggestion_safe
      suggestion_safe=$(printf '%s' "$suggestion" | _t2t_sanitize_output | head -c 200)
      print -u2 "[talk2term] Suggestion: $suggestion_safe"
    fi
    _t2t_maybe_reset_prompt
    return 0
  fi

  if [[ -z "$command" || "$command" == "null" ]]; then
    print -u2 "[talk2term] Invalid or empty response from API."
    _t2t_maybe_reset_prompt
    return 0
  fi

  # --- DISPLAY COMMAND ---
  # Use print without -P for API-controlled content to prevent ZSH prompt
  # sequence injection (%F, %n, %m etc. could leak system info or mislead)
  print -P "\n%F{cyan}Translated Command:%f"
  print -r -- "  $command"

  # Warn about potentially dangerous commands (best-effort denylist)
  if _t2t_is_dangerous_command "$command"; then
    print -P "%F{red}  WARNING: This command may be destructive. Review carefully before executing.%f"
  fi

  print -Pn "Execute? (y/n): "
  read -k 1 reply
  print
  if [[ "$reply" == [yY] ]]; then
    print "[talk2term] Executing: $command"
    eval "$command"
  else
    if echo -n "$command" | _t2t_clipboard_copy 2>/dev/null; then
      print "[talk2term] Cancelled. Command copied to clipboard."
    else
      print "[talk2term] Cancelled."
    fi
  fi
  _t2t_maybe_reset_prompt
  return 0
}

# --- ZLE WIDGET & KEYBINDING (only if interactive ZLE session) ---
if [[ -n $ZSH_VERSION && $- == *i* && -n $ZLE_LINE_EDITOR ]]; then
  _t2t_zle_widget() {
    _t2t_handle "$BUFFER"
    # Clear buffer if handled
    if [[ "$BUFFER" == t2t:* || "$BUFFER" == t2t-p:* ]]; then
      BUFFER=""
      CURSOR=0
    fi
  }
  zle -N _t2t_zle_widget

  # Save original accept-line only once
  if ! zle -l | grep -q '^_t2t_orig_accept_line$'; then
    zle -N _t2t_orig_accept_line accept-line
  fi

  _t2t_accept_line() {
    if [[ "$BUFFER" == t2t:* || "$BUFFER" == t2t-p:* ]]; then
      _t2t_zle_widget
      zle reset-prompt
      return
    else
      if zle -l | grep -q '^_t2t_orig_accept_line$'; then
        _t2t_orig_accept_line
      else
        zle accept-line
      fi
    fi
  }
  zle -N accept-line _t2t_accept_line
fi

# --- SHELL COMMANDS ---
t2t() {
  if [[ $# -eq 0 || "$1" == "--help" || "$1" == "-h" || "$1" == "help" ]]; then
    _t2t_help
    return 0
  fi
  _t2t_handle "t2t: $*"
}
t2t-p() {
  if [[ $# -eq 0 || "$1" == "--help" || "$1" == "-h" || "$1" == "help" ]]; then
    _t2t_help
    return 0
  fi
  _t2t_handle "t2t-p: $*"
}

# --- SHELL COMMAND: t2t-credit ---
t2t-credit() {
  emulate -L zsh
  if ! _t2t_read_api_key; then return 1; fi
  local api_key="$REPLY"

  if ! _t2t_validate_api_url "$T2T_API_URL"; then return 1; fi

  local resp
  if ! resp=$(curl -sS -X GET "$(_t2t_base_url)/credits" \
    --max-time 15 \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $api_key"); then
    print -u2 "[talk2term] Failed to connect to server."
    return 1
  fi

  # Validate JSON
  if ! echo "$resp" | jq empty 2>/dev/null; then
    print -u2 "[talk2term] Error connecting to Talk2Term server. Try again after some time."
    return 1
  fi
  local credits freeUsesLeft err
  credits=$(echo "$resp" | jq -r '.credits // empty')
  freeUsesLeft=$(echo "$resp" | jq -r '.freeUsesLeft // empty')
  err=$(echo "$resp" | jq -r '.error // empty')
  if [[ -n "$err" ]]; then
    local err_safe
    err_safe=$(printf '%s' "$err" | _t2t_sanitize_output | head -c 300)
    print -u2 "[talk2term] API error: $err_safe"
    return 1
  fi
  print "[talk2term] Credits: $credits | Free Lite uses left today: $freeUsesLeft"
}

# --- SHELL COMMAND: t2t-reset ---
t2t-reset() {
  emulate -L zsh
  if ! _t2t_read_api_key; then return 1; fi
  local api_key="$REPLY"

  if ! _t2t_validate_api_url "$T2T_API_URL"; then return 1; fi

  if [[ -n "$T2T_SESSION_ID" ]]; then
    if _t2t_validate_session_id "$T2T_SESSION_ID"; then
      curl -sS -X DELETE "$(_t2t_base_url)/conversation/$T2T_SESSION_ID" \
        --max-time 15 \
        -H "Authorization: Bearer $api_key" > /dev/null 2>&1
    fi
  fi

  # Reset session variables
  T2T_SESSION_ID=""
  T2T_TERMINAL_ID=$(_t2t_get_terminal_id)
  print "[talk2term] Conversation context reset."
}

# --- SHELL COMMAND: t2t-context ---
t2t-context() {
  emulate -L zsh
  if ! _t2t_read_api_key; then return 1; fi
  local api_key="$REPLY"

  if ! _t2t_validate_api_url "$T2T_API_URL"; then return 1; fi

  if [[ -z "$T2T_SESSION_ID" ]]; then
    print "[talk2term] No active conversation session."
    return 0
  fi

  if ! _t2t_validate_session_id "$T2T_SESSION_ID"; then
    print "[talk2term] Invalid session. Resetting..."
    T2T_SESSION_ID=""
    return 1
  fi

  local resp
  if ! resp=$(curl -sS -X GET "$(_t2t_base_url)/conversation/$T2T_SESSION_ID" \
    --max-time 15 \
    -H "Authorization: Bearer $api_key" 2>/dev/null); then
    print -u2 "[talk2term] Failed to fetch conversation context."
    return 1
  fi

  if [[ -z "$resp" ]]; then
    print -u2 "[talk2term] Failed to fetch conversation context."
    return 1
  fi

  # Validate JSON
  if ! echo "$resp" | jq empty 2>/dev/null; then
    print -u2 "[talk2term] Invalid response from server."
    return 1
  fi

  # Check if session exists
  local error_msg
  error_msg=$(echo "$resp" | jq -r '.error // empty' 2>/dev/null)
  if [[ -n "$error_msg" && "$error_msg" != "null" ]]; then
    if [[ "$error_msg" == *"not found"* ]]; then
      print "[talk2term] No conversation history found."
      T2T_SESSION_ID=""  # Reset if session doesn't exist
    else
      local err_safe
      err_safe=$(printf '%s' "$error_msg" | _t2t_sanitize_output | head -c 300)
      print -u2 "[talk2term] Error: $err_safe"
    fi
    return 1
  fi

  # Display recent messages — sanitize output to prevent terminal escape injection
  print "[talk2term] Recent conversation:"
  echo "$resp" | jq -r '.messages[-10:][] | "  \(.role): \(.content)"' 2>/dev/null \
    | _t2t_sanitize_output \
    || print -u2 "[talk2term] Unable to parse conversation history."
}

# --- SHELL COMMAND: t2t-update ---
t2t-update() {
  emulate -L zsh
  local plugin_dir="${0:A:h}"
  # Fallback: try common install locations
  if [[ ! -d "$plugin_dir/.git" ]]; then
    plugin_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/talk2term"
  fi
  if [[ ! -d "$plugin_dir/.git" ]]; then
    plugin_dir="$HOME/.zsh/zsh-talk2term"
  fi
  if [[ ! -d "$plugin_dir/.git" ]]; then
    print -u2 "[talk2term] Could not find plugin git directory."
    print -u2 "  Run manually: cd <plugin-dir> && git pull"
    return 1
  fi

  print "[talk2term] Updating from $plugin_dir..."
  local old_version=""
  [[ -f "$plugin_dir/.version" ]] && old_version=$(cat "$plugin_dir/.version")

  # Use git -C to avoid cd side effects
  if git -C "$plugin_dir" pull origin main 2>&1; then
    local new_version=""
    [[ -f "$plugin_dir/.version" ]] && new_version=$(cat "$plugin_dir/.version")
    if [[ -n "$old_version" && -n "$new_version" && "$old_version" != "$new_version" ]]; then
      print "[talk2term] Updated: $old_version -> $new_version"
    else
      print "[talk2term] Already up to date."
    fi
    print "[talk2term] Reload with: source ~/.zshrc"
  else
    print -u2 "[talk2term] Update failed. Check your internet connection."
    return 1
  fi
}

# --- END OF FILE ---
