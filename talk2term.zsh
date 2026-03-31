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
#   Example: echo "sk-..." > ~/.talk2term

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
  cat <<EOF
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

# Read API key from config file.
# Returns 0 on success (key in $REPLY), 1 on failure (error printed).
_t2t_read_api_key() {
  if [[ ! -f "$T2T_KEY_FILE" ]]; then
    print -u2 "[talk2term] API key file not found: $T2T_KEY_FILE"
    print -u2 "  Create it with: echo 'YOUR_KEY' > $T2T_KEY_FILE"
    return 1
  fi
  REPLY=$(head -n 1 "$T2T_KEY_FILE" | tr -d '\r\n')
  if [[ -z "$REPLY" ]]; then
    print -u2 "[talk2term] API key is empty in $T2T_KEY_FILE."
    return 1
  fi
  return 0
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

# --- CONFIG ---
# typeset -g prevents re-assignment on re-source. Override in .zshrc BEFORE sourcing.
(( ! ${+T2T_API_URL} ))  && typeset -g T2T_API_URL='https://talk2term.prodevs.in/api/zsh-talk2term/convert'
(( ! ${+T2T_KEY_FILE} )) && typeset -g T2T_KEY_FILE="$HOME/.talk2term"

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
# Generate unique terminal window ID based on TTY and process info
_t2t_get_terminal_id() {
  local input="${TTY}:$$:$(date +%s)"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s\n' "$input" | sha256sum | cut -c1-16
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s\n' "$input" | shasum -a 256 | cut -c1-16
  else
    printf '%s' "$input" | od -An -tx1 | tr -d ' \n' | cut -c1-16
  fi
}

# Session storage
if [[ -z "$T2T_SESSION_ID" ]]; then
  T2T_TERMINAL_ID=$(_t2t_get_terminal_id)
  T2T_SESSION_ID=""  # Will be set by API response
fi

# --- MAIN FUNCTION ---
_t2t_handle() {
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
    if [[ -n $ZLE_LINE_EDITOR ]]; then zle reset-prompt; fi
    return 0
  fi

  # --- Read API Key ---
  if ! _t2t_read_api_key; then
    if [[ -n $ZLE_LINE_EDITOR ]]; then zle reset-prompt; fi
    return 0
  fi
  local api_key="$REPLY"

  # --- API CALL (synchronous, no background job) ---
  local tmpfile
  tmpfile=$(mktemp "${TMPDIR:-/tmp}/t2t.XXXXXX")
  printf "[talk2term] Working...\r"
  local json_payload
  json_payload=$(_t2t_build_json "$prompt" "$model" "$T2T_TERMINAL_ID" "$T2T_SESSION_ID")
  curl -sS -X POST "$T2T_API_URL" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $api_key" \
    --data "$json_payload" \
    > "$tmpfile" 2>&1
  printf "\r%*s\r\n" $(tput cols 2>/dev/null || echo 80) " " # clear line and print newline

  # --- HANDLE RESPONSE ---
  if ! resp=$(cat "$tmpfile"); then
    print -u2 "[talk2term] Error reading API response."
    rm -f "$tmpfile"
    if [[ -n $ZLE_LINE_EDITOR ]]; then zle reset-prompt; fi
    return 0
  fi
  rm -f "$tmpfile"

  # Check for network or API error
  if [[ -z "$resp" ]]; then
    print -u2 "[talk2term] No response from API."
    if [[ -n $ZLE_LINE_EDITOR ]]; then zle reset-prompt; fi
    return 0
  fi

  # Try to parse command and session ID
  command=$(echo "$resp" | jq -r '.command // empty')
  err=$(echo "$resp" | jq -r '.error // empty')
  session_id=$(echo "$resp" | jq -r '.session_id // empty')
  
  # Update session ID if provided
  if [[ -n "$session_id" && "$session_id" != "null" ]]; then
    T2T_SESSION_ID="$session_id"
  fi

  if [[ -n "$err" ]]; then
    if [[ "$err" == *"API key"* || "$err" == *"Invalid or inactive"* ]]; then
      print -u2 "[talk2term] Invalid or missing API key. Please check $T2T_KEY_FILE."
    elif [[ "$err" == *"Not enough credits"* || "$err" == *"free limit reached"* ]]; then
      print -u2 "[talk2term] $err"
      print -u2 "  Get more credits at: https://talk2term.prodevs.in"
    elif [[ "$err" == *"deprecated"* ]]; then
      print -u2 "[talk2term] This feature is no longer available. Please update the plugin."
    else
      print -u2 "[talk2term] API error: $err"
    fi
    local suggestion
    suggestion=$(echo "$resp" | jq -r '.suggestion // empty')
    if [[ -n "$suggestion" && "$suggestion" != "null" ]]; then
      print -u2 "[talk2term] Suggestion: $suggestion"
    fi
    if [[ -n $ZLE_LINE_EDITOR ]]; then zle reset-prompt; fi
    return 0
  fi

  if [[ -z "$command" || "$command" == "null" ]]; then
    print -u2 "[talk2term] Invalid or empty response from API."
    if [[ -n $ZLE_LINE_EDITOR ]]; then zle reset-prompt; fi
    return 0
  fi

  # --- PROMPT USER ---
  print -P "\n%F{cyan}Translated Command:%f %B$command%b"

  # Warn about potentially dangerous commands
  if [[ "$command" == *"rm -rf"* || "$command" == *"sudo"* || "$command" == *"mkfs"* || "$command" == *"dd if="* || "$command" == *"> /dev/"* ]]; then
    print -P "%F{red}Warning: This command may be destructive. Review carefully.%f"
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
  if [[ -n $ZLE_LINE_EDITOR ]]; then zle reset-prompt; fi
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
  if ! _t2t_read_api_key; then return 1; fi
  local api_key="$REPLY"
  local resp credits freeUsesLeft err
  local credits_url="${T2T_API_URL%/convert}/credits"
  resp=$(curl -sS -X GET "$credits_url" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $api_key")
  # Try to parse as JSON, else show connection error
  if ! echo "$resp" | jq . >/dev/null 2>&1; then
    print -u2 "[talk2term] Error connecting to Talk2Term server. Try again after some time."
    return 1
  fi
  credits=$(echo "$resp" | jq -r '.credits // empty')
  freeUsesLeft=$(echo "$resp" | jq -r '.freeUsesLeft // empty')
  err=$(echo "$resp" | jq -r '.error // empty')
  if [[ -n "$err" ]]; then
    print -u2 "[talk2term] API error: $err"
    return 1
  fi
  print "[talk2term] Credits: $credits | Free Lite uses left today: $freeUsesLeft"
}

# --- SHELL COMMAND: t2t-reset ---
t2t-reset() {
  if ! _t2t_read_api_key; then return 1; fi
  local api_key="$REPLY"
  
  if [[ -n "$T2T_SESSION_ID" ]]; then
    local base_url="${T2T_API_URL%/convert}"
    local delete_url="${base_url}/conversation/$T2T_SESSION_ID"
    curl -sS -X DELETE "$delete_url" \
      -H "Authorization: Bearer $api_key" > /dev/null 2>&1
  fi
  
  # Reset session variables
  T2T_SESSION_ID=""
  T2T_TERMINAL_ID=$(_t2t_get_terminal_id)
  print "[talk2term] Conversation context reset."
}

# --- SHELL COMMAND: t2t-context ---
t2t-context() {
  if ! _t2t_read_api_key; then return 1; fi
  local api_key="$REPLY"
  
  if [[ -z "$T2T_SESSION_ID" ]]; then
    print "[talk2term] No active conversation session."
    return 0
  fi
  
  local base_url="${T2T_API_URL%/convert}"
  local get_url="${base_url}/conversation/$T2T_SESSION_ID"
  local resp
  resp=$(curl -sS -X GET "$get_url" \
    -H "Authorization: Bearer $api_key" 2>/dev/null)
    
  if [[ $? -ne 0 ]] || [[ -z "$resp" ]]; then
    print -u2 "[talk2term] Failed to fetch conversation context."
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
      print -u2 "[talk2term] Error: $error_msg"
    fi
    return 1
  fi
  
  # Display recent messages
  print "[talk2term] Recent conversation:"
  echo "$resp" | jq -r '.messages[-10:][] | "  \(.role): \(.content)"' 2>/dev/null || print -u2 "[talk2term] Unable to parse conversation history."
}

# --- SHELL COMMAND: t2t-update ---
t2t-update() {
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

  if (cd "$plugin_dir" && git pull --quiet origin main 2>/dev/null); then
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