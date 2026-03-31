#!/bin/sh
set -e

PLUGIN_NAME="talk2term"
PLUGIN_REPO="https://github.com/prodevs-kol/zsh-talk2term.git"

# Validate ZSH_CUSTOM is under HOME to prevent path hijacking
case "${ZSH_CUSTOM:-}" in
  "$HOME"/*) ;;  # OK — under home directory
  "")
    ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
    ;;
  *)
    printf "Warning: ZSH_CUSTOM (%s) is outside HOME. Using default.\n" "$ZSH_CUSTOM"
    ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
    ;;
esac

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

# Clone or update the plugin repo
if [ -d "$PLUGIN_DIR" ]; then
  printf "%s already installed at %s. Updating...\n" "$PLUGIN_NAME" "$PLUGIN_DIR"
  # Use git -C to avoid cd side effects and properly quote paths
  git -C "$PLUGIN_DIR" pull --quiet origin main || {
    printf "Warning: Update failed. Continuing with existing version.\n"
  }
else
  printf "Cloning %s into %s...\n" "$PLUGIN_NAME" "$PLUGIN_DIR"
  git clone --depth=1 "$PLUGIN_REPO" "$PLUGIN_DIR"
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
  elif grep -q "^plugins=" "$ZSHRC"; then
    # Oh My Zsh detected — add to plugins array
    printf "Adding %s to Oh My Zsh plugins in %s...\n" "$PLUGIN_NAME" "$ZSHRC"
    cp "$ZSHRC" "$ZSHRC.bak.t2t"
    sed "/^plugins=/ s/)/ $PLUGIN_NAME)/" "$ZSHRC" > "$ZSHRC.t2t.tmp" && mv "$ZSHRC.t2t.tmp" "$ZSHRC"
  else
    # No Oh My Zsh — add source line directly
    printf "Adding source line to %s...\n" "$ZSHRC"
    cp "$ZSHRC" "$ZSHRC.bak.t2t"
    printf '\n# Talk2Term ZSH Plugin\nsource "%s/talk2term.plugin.zsh"\n' "$PLUGIN_DIR" >> "$ZSHRC"
  fi
else
  printf "Warning: %s not found.\n" "$ZSHRC"
  printf "Add this to your shell config:\n"
  printf '  source "%s/talk2term.plugin.zsh"\n' "$PLUGIN_DIR"
fi

# Create API key file with secure permissions if not exists
KEY_FILE="$HOME/.talk2term"
if [ ! -f "$KEY_FILE" ]; then
  printf "\nSetup: Create your API key file:\n"
  printf "  echo 'YOUR_API_KEY' > %s && chmod 600 %s\n" "$KEY_FILE" "$KEY_FILE"
  printf "  Get your key at: https://talk2term.prodevs.in/profile\n"
else
  # Fix permissions on existing key file
  chmod 600 "$KEY_FILE" 2>/dev/null || true
fi

printf "\nInstallation complete!\n"
printf "To activate, run: source ~/.zshrc\n"
