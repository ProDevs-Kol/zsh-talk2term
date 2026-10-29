#!/bin/sh
# Install the Talk2Term ZSH plugin from pinned tag PLUGIN_REF.
#
# Oh My Zsh is optional. When it is absent, the plugin is cloned to
# ~/.zsh/talk2term and sourced from ~/.zshrc. This script does not log
# the user in and does not write an API key.
set -e

PLUGIN_NAME="talk2term"
PLUGIN_REPO="https://github.com/prodevs-kol/zsh-talk2term.git"
# Keep in sync with .version (v prefix) and T2T_PLUGIN_REF in talk2term.zsh.
PLUGIN_REF="v1.2.5"

# --- Dependency checks ---
missing_deps=""
command -v curl >/dev/null 2>&1 || missing_deps="$missing_deps curl"
command -v jq >/dev/null 2>&1 || missing_deps="$missing_deps jq"
command -v git >/dev/null 2>&1 || missing_deps="$missing_deps git"
command -v zsh >/dev/null 2>&1 || missing_deps="$missing_deps zsh"

if [ -n "$missing_deps" ]; then
  printf "Error: Missing required dependencies:%s\n" "$missing_deps"
  printf "Please install them first:\n"
  printf "  macOS:  brew install%s\n" "$missing_deps"
  printf "  Ubuntu: sudo apt install%s\n" "$missing_deps"
  exit 1
fi

# zsh 5.8 or newer. Compare major.minor only.
if ! zsh -c '
  ver=$ZSH_VERSION
  major=${ver%%.*}
  rest=${ver#*.}
  minor=${rest%%.*}
  case $major in *[!0-9]*) exit 1 ;; esac
  case $minor in *[!0-9]*) exit 1 ;; esac
  if [ "$major" -gt 5 ]; then exit 0; fi
  if [ "$major" -eq 5 ] && [ "$minor" -ge 8 ]; then exit 0; fi
  exit 1
'; then
  printf "Error: zsh 5.8 or newer is required (found %s).\n" "$(zsh -c 'print -r -- $ZSH_VERSION')"
  exit 1
fi

# Install under Oh My Zsh when it is present. Otherwise use ~/.zsh/talk2term.
USE_OMZ=0
if [ -d "$HOME/.oh-my-zsh" ] || [ -n "${ZSH:-}" ]; then
  USE_OMZ=1
  case "${ZSH_CUSTOM:-}" in
    "$HOME"/*) ;;
    "")
      if [ -n "${ZSH:-}" ] && [ -d "${ZSH}/custom" ]; then
        ZSH_CUSTOM="${ZSH}/custom"
      else
        ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
      fi
      ;;
    *)
      printf "Warning: ZSH_CUSTOM (%s) is outside HOME. Using default.\n" "$ZSH_CUSTOM"
      ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
      ;;
  esac
  PLUGIN_DIR="$ZSH_CUSTOM/plugins/$PLUGIN_NAME"
else
  PLUGIN_DIR="$HOME/.zsh/$PLUGIN_NAME"
fi

ZSHRC="$HOME/.zshrc"

# Clone the pinned tag, or move an existing checkout onto that tag.
# Does not pull unpinned main.
if [ -d "$PLUGIN_DIR/.git" ]; then
  printf "%s already installed at %s. Checking out %s...\n" "$PLUGIN_NAME" "$PLUGIN_DIR" "$PLUGIN_REF"
  git -C "$PLUGIN_DIR" fetch --depth=1 origin "refs/tags/${PLUGIN_REF}:refs/tags/${PLUGIN_REF}"
  git -C "$PLUGIN_DIR" checkout --detach "$PLUGIN_REF"
elif [ -d "$PLUGIN_DIR" ]; then
  printf "Error: %s exists but is not a git checkout. Move it aside and run this installer again.\n" "$PLUGIN_DIR"
  exit 1
else
  printf "Cloning %s (%s) into %s...\n" "$PLUGIN_NAME" "$PLUGIN_REF" "$PLUGIN_DIR"
  mkdir -p "$(dirname "$PLUGIN_DIR")"
  git clone --depth=1 --branch "$PLUGIN_REF" "$PLUGIN_REPO" "$PLUGIN_DIR"
fi

# Verify plugin files exist
if [ ! -f "$PLUGIN_DIR/talk2term.plugin.zsh" ] && [ ! -f "$PLUGIN_DIR/talk2term.zsh" ]; then
  printf "Error: Plugin files not found in %s\n" "$PLUGIN_DIR"
  exit 1
fi

# Add plugin to .zshrc
if [ -f "$ZSHRC" ]; then
  if grep -q "plugins=.*$PLUGIN_NAME" "$ZSHRC" || grep -q "talk2term" "$ZSHRC"; then
    printf "%s already configured in %s.\n" "$PLUGIN_NAME" "$ZSHRC"
  elif [ "$USE_OMZ" -eq 1 ] && grep -q "^plugins=" "$ZSHRC"; then
    printf "Adding %s to Oh My Zsh plugins in %s...\n" "$PLUGIN_NAME" "$ZSHRC"
    cp "$ZSHRC" "$ZSHRC.bak.t2t"
    sed "/^plugins=/ s/)/ $PLUGIN_NAME)/" "$ZSHRC" > "$ZSHRC.t2t.tmp" && mv "$ZSHRC.t2t.tmp" "$ZSHRC"
  else
    printf "Adding source line to %s...\n" "$ZSHRC"
    cp "$ZSHRC" "$ZSHRC.bak.t2t"
    printf '\n# Talk2Term ZSH Plugin\nsource "%s/talk2term.plugin.zsh"\n' "$PLUGIN_DIR" >> "$ZSHRC"
  fi
else
  printf "Creating %s with a source line for %s...\n" "$ZSHRC" "$PLUGIN_DIR"
  printf '# Talk2Term ZSH Plugin\nsource "%s/talk2term.plugin.zsh"\n' "$PLUGIN_DIR" > "$ZSHRC"
fi

# Create API key file with secure permissions if not exists
KEY_FILE="$HOME/.talk2term"
if [ ! -f "$KEY_FILE" ]; then
  printf "\nSetup: log in at https://talk2term.prodevs.in (magic-link email).\n"
  printf "Copy an API key from https://talk2term.prodevs.in/profile\n"
  printf "Then save it:\n"
  printf "  echo 'YOUR_API_KEY' > %s && chmod 600 %s\n" "$KEY_FILE" "$KEY_FILE"
  printf "Then run: t2t list files\n"
else
  chmod 600 "$KEY_FILE" 2>/dev/null || true
fi

printf "\nInstallation complete (%s).\n" "$PLUGIN_REF"
printf "To activate, run: source ~/.zshrc\n"
printf "A t2t request takes about 20 seconds. That is the API, not the installer.\n"
