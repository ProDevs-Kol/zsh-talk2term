#!/bin/sh
set -e

PLUGIN_NAME="talk2term"
PLUGIN_REPO="https://github.com/prodevs-kol/zsh-talk2term.git"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
PLUGIN_DIR="$ZSH_CUSTOM/plugins/$PLUGIN_NAME"
ZSHRC="$HOME/.zshrc"

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

# Clone the plugin repo
if [ -d "$PLUGIN_DIR" ]; then
  printf "%s already installed at %s. Updating...\n" "$PLUGIN_NAME" "$PLUGIN_DIR"
  cd "$PLUGIN_DIR" && git pull --quiet && cd - >/dev/null
else
  printf "Cloning %s into %s...\n" "$PLUGIN_NAME" "$PLUGIN_DIR"
  git clone --depth=1 "$PLUGIN_REPO" "$PLUGIN_DIR"
fi

# Ensure main plugin file is named talk2term.plugin.zsh
if [ -f "$PLUGIN_DIR/talk2term.zsh" ] && [ ! -f "$PLUGIN_DIR/talk2term.plugin.zsh" ]; then
  printf "Renaming talk2term.zsh to talk2term.plugin.zsh...\n"
  mv "$PLUGIN_DIR/talk2term.zsh" "$PLUGIN_DIR/talk2term.plugin.zsh"
fi

# Add plugin to .zshrc if not present
if [ -f "$ZSHRC" ]; then
  if grep -q "plugins=.*$PLUGIN_NAME" "$ZSHRC"; then
    printf "%s already present in plugins list.\n" "$PLUGIN_NAME"
  else
    printf "Adding %s to plugins list in %s...\n" "$PLUGIN_NAME" "$ZSHRC"
    cp "$ZSHRC" "$ZSHRC.bak.t2t"
    # Cross-platform sed: use temp file instead of -i flag
    sed "/^plugins=/ s/)/ $PLUGIN_NAME)/" "$ZSHRC" > "$ZSHRC.t2t.tmp" && mv "$ZSHRC.t2t.tmp" "$ZSHRC"
  fi
else
  printf "Warning: %s not found. Add 'source %s/talk2term.plugin.zsh' to your shell config.\n" "$ZSHRC" "$PLUGIN_DIR"
fi

printf "\nInstallation complete!\n"
printf "To activate, run: source ~/.zshrc\n"
