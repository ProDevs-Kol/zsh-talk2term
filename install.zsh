#!/bin/zsh
# install.zsh - Install helper for talk2term ZSH plugin

PLUGIN_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
OHMYZSH_PLUGINS="$HOME/.oh-my-zsh/custom/plugins"

print "[talk2term] To install manually, add the following to your .zshrc:"
print "  source $PLUGIN_DIR/talk2term.zsh"

if [[ -d "$OHMYZSH_PLUGINS" ]]; then
  print "[talk2term] Optionally symlinking to Oh My Zsh custom plugins..."
  ln -sf "$PLUGIN_DIR" "$OHMYZSH_PLUGINS/talk2term"
  print "[talk2term] Symlinked! Add 'talk2term' to your plugins=(...) in .zshrc."
else
  print "[talk2term] Oh My Zsh custom plugins directory not found. Skipping symlink."
fi 