# nvim, opened five ways.
#
# It sits in host/ for the same reason zellij.nu and tmux.nu do: it is something done WITH
# a directory, not something zz knows about directories. Only the `--fuzzy` and
# `--tab` branches go anywhere near a picker; the rest never touch zoxide at all.
use ../pick
use mux.nu

# Open nvim. With piped input, edit it. With `--fuzzy`, pick a dir first.
export def main [
  file?: string = '',
  --fuzzy(-f)
  --tab(-t)
] {
  let input = $in
  if ($input | is-not-empty) {
    commandline edit --replace $"($input | path expand) | nvim - "
    return
  }
  if ($file | is-not-empty) {
    mux rename-pane ($file | path basename)
    ^$env.editor ($file | path expand)
    return
  }
  if $tab {
    mux tab nvim $"($env.editor) tab in"
    return
  }
  if $fuzzy {
    let dir = (pick $"($env.editor) in")
    if ($dir == null) { return }
    commandline edit --replace $"cd ($dir); ($env.editor) ."
    mux rename-pane ($dir | path basename)
    return
  }
  mux rename-pane (pwd | path basename)
  ^$env.editor .
}
