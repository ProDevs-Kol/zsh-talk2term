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

_t2t_help() {
  cat <<EOF
Talk2Term ZSH Plugin Usage:
  t2t <your prompt>     # Free (Lite)
  t2t-p <your prompt>   # Paid (Pro)

Examples:
  t2t list all files modified today
  t2t-p find all .py files recursively

Get your API key from: https://talk2term.prodevs.in/profile
EOF
}

# --- CONFIG ---
T2T_API_URL="https://talk2term.prodevs.in/api/zsh-talk2term/convert"
# T2T_API_URL="http://localhost:3000/api/zsh-talk2term/convert"
T2T_KEY_FILE="$HOME/.talk2term"

# --- SPINNER ---
_t2t_spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\\'
  tput civis 2>/dev/null # hide cursor
  while kill -0 $pid 2>/dev/null; do
    local temp=${spinstr#?}
    printf "\r[talk2term] Working... [%c]  " "$spinstr"
    spinstr=$temp${spinstr%$temp}
    sleep $delay
  done
  printf "\r[talk2term] Working...     \r"
  tput cnorm 2>/dev/null # show cursor
}

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
  if [[ ! -f "$T2T_KEY_FILE" ]]; then
    print -u2 "[talk2term] API key file not found: $T2T_KEY_FILE"
    print -u2 "  Please create this file and paste your API key from /profile."
    if [[ -n $ZLE_LINE_EDITOR ]]; then zle reset-prompt; fi
    return 0
  fi
  local api_key
  api_key=$(head -n 1 "$T2T_KEY_FILE" | tr -d '\r\n')
  if [[ -z "$api_key" ]]; then
    print -u2 "[talk2term] API key is empty in $T2T_KEY_FILE."
    if [[ -n $ZLE_LINE_EDITOR ]]; then zle reset-prompt; fi
    return 0
  fi

  # --- API CALL (synchronous, no background job) ---
  local tmpfile
  tmpfile=$(mktemp /tmp/t2t.XXXXXX)
  printf "[talk2term] Working...\r"
  curl -sS -X POST "$T2T_API_URL" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $api_key" \
    --data "{\"prompt\": \"$prompt\", \"model\": \"$model\"}" \
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

  # Try to parse command
  command=$(echo "$resp" | jq -r '.command // empty')
  err=$(echo "$resp" | jq -r '.error // empty')

  if [[ -n "$err" ]]; then
    if [[ "$err" == *"API key"* || "$err" == *"Invalid or inactive API key"* ]]; then
      print -u2 "[talk2term] Invalid or missing API key. Please check $T2T_KEY_FILE."
    elif [[ "$err" == *"Insufficient credits"* ]]; then
      print -u2 "Insufficient credits for this model."
    else
      print -u2 "[talk2term] API error: $err"
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
  print -Pn "\nTranslated Command: %B$command%b\nExecute? (y/n): "
  read -k 1 reply
  print
  if [[ "$reply" == [yY] ]]; then
    print "[talk2term] Executing: $command"
    eval "$command"
  else
    print "[talk2term] Cancelled."
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
  if [[ $# -eq 0 ]]; then
    _t2t_help
    return 0
  fi
  _t2t_handle "t2t: $*"
}
t2t-p() {
  if [[ $# -eq 0 ]]; then
    _t2t_help
    return 0
  fi
  _t2t_handle "t2t-p: $*"
}

# --- SHELL COMMAND: t2t-credit ---
t2t-credit() {
  if [[ ! -f "$T2T_KEY_FILE" ]]; then
    print -u2 "[talk2term] API key file not found: $T2T_KEY_FILE"
    print -u2 "  Please create this file and paste your API key from /profile."
    return 1
  fi
  local api_key
  api_key=$(head -n 1 "$T2T_KEY_FILE" | tr -d '\r\n')
  if [[ -z "$api_key" ]]; then
    print -u2 "[talk2term] API key is empty in $T2T_KEY_FILE."
    return 1
  fi
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

# --- END OF FILE --- 