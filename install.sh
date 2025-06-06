#!/bin/sh
set -e

PLUGIN_NAME="talk2term"
PLUGIN_REPO="https://github.com/prodevs-kol/zsh-talk2term.git"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
PLUGIN_DIR="$ZSH_CUSTOM/plugins/$PLUGIN_NAME"
ZSHRC="$HOME/.zshrc"

# Clone the plugin repo
if [ -d "$PLUGIN_DIR" ]; then
  echo "$PLUGIN_NAME already installed at $PLUGIN_DIR. Skipping clone."
else
  echo "Cloning $PLUGIN_NAME into $PLUGIN_DIR..."
  git clone --depth=1 "$PLUGIN_REPO" "$PLUGIN_DIR"
fi

# Ensure main plugin file is named talk2term.plugin.zsh
if [ -f "$PLUGIN_DIR/talk2term.zsh" ] && [ ! -f "$PLUGIN_DIR/talk2term.plugin.zsh" ]; then
  echo "Renaming talk2term.zsh to talk2term.plugin.zsh..."
  mv "$PLUGIN_DIR/talk2term.zsh" "$PLUGIN_DIR/talk2term.plugin.zsh"
fi

# Add plugin to .zshrc if not present
if grep -q "plugins=.*$PLUGIN_NAME" "$ZSHRC"; then
  echo "$PLUGIN_NAME already present in plugins list."
else
  echo "Adding $PLUGIN_NAME to plugins list in $ZSHRC..."
  cp "$ZSHRC" "$ZSHRC.bak.t2t"
  sed -i '' "/^plugins=/ s/)/ $PLUGIN_NAME)/" "$ZSHRC"
fi

echo "\n✅ Installation complete!"
echo "To activate, run: source ~/.zshrc" 