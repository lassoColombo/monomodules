# nvim, opened four ways.
#
# It sits in host/ because it is something done WITH a directory, not something
# zz knows about directories. Only the `--fuzzy` branch goes anywhere near a
# picker; the rest never touch zoxide at all.
use ../pick

# Open nvim. With piped input, edit it. With `--fuzzy`, pick a dir first.
export def main [
  file?: string = '',
  --fuzzy(-f)
] {
  let input = $in
  if ($input | is-not-empty) {
    commandline edit --replace $"($input | path expand) | nvim - "
    return
  }
  if ($file | is-not-empty) {
    ^$env.editor ($file | path expand)
    return
  }
  if $fuzzy {
    let dir = (pick $"($env.editor) in")
    if ($dir == null) { return }
    commandline edit --replace $"cd ($dir); ($env.editor) ."
    return
  }
  ^$env.editor .
}
