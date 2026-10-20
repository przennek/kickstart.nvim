#!/bin/sh
# iTerm2 for this Neovim config (macOS): Cmd+<key> works like in IntelliJ.
#   1. links the dynamic profile "Neovim (IntelliJ keys)" and makes it the default profile
#   2. frees Cmd+1…9: iTerm2 uses them to select tabs *before* the profile's key mappings
#      ("Shortcut to choose a tab" = No shortcut; tabs are still in the Window menu).
#      Without this Cmd+1 does nothing in Neovim and only Option+1 (Esc+1) opens the project tree.
# Run it with iTerm2 closed: iTerm2 writes its settings back when it quits.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
profiles="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
guid=6f0c1d52-7a3e-4c55-9d1e-2b8f4a1c9e10

if pgrep -xq iTerm2; then
  echo "Quit iTerm2 first (Cmd+Q), then run this from Terminal.app: iTerm2 overwrites its settings on quit." >&2
  exit 1
fi

mkdir -p "$profiles"
ln -sf "$here/nvim-idea.json" "$profiles/"

# 9 = kPreferenceModifierTagNone ("No shortcut") in iTerm2's Settings → Keys → Navigation Shortcuts
defaults write com.googlecode.iterm2 SwitchTabModifier -int 9
defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "$guid"

echo "Done: profile linked and set as default, Cmd+1…9 go to Neovim. Start iTerm2."
