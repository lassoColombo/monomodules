# nvim, opened five ways.
#
# It sits in host/ for the same reason zellij.nu does: it is something done WITH
# a directory, not something zz knows about directories. Only the `--fuzzy` and
# `--tab` branches go anywhere near a picker; the rest never touch zoxide at all.
use ../pick
use zellij.nu

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
    ^nvim ($file | path expand)
    zellij rename-pane $"nvim ($file)"
    return
  }
  if $tab {
    zellij tab nvim "nvim tab in"
    return
  }
  if $fuzzy {
    let dir = (pick "nvim in")
    if ($dir == null) { return }
    commandline edit --replace $"cd ($dir); nvim ."
    zellij rename-pane ($dir | path basename)
    return
  }
  zellij rename-pane (pwd | path basename)
  ^nvim .
}
