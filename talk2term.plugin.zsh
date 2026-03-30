# talk2term.plugin.zsh — Framework entry point
# Sources the main plugin file. All logic lives in talk2term.zsh.
# Compatible with: Oh My Zsh, Antigen, Zinit, zplug, Sheldon, manual sourcing.

# Resolve the directory of this file (ZSH Plugin Standard $0 handling)
0="${ZERO:-${${0:#$ZSH_ARGZERO}:-${(%):-%N}}}"
0="${${(M)0:#/*}:-$PWD/$0}"

source "${0:h}/talk2term.zsh"
