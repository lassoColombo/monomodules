# zz — a zoxide entry, chosen, then handed to whoever does something with it.
#
# This file is the command surface and nothing else: one line of intent per verb.
# Anything longer than that line belongs to one of the four below.
#
#   db.nu       zoxide, read and write. The only file that shells out to it.
#   pick/       entries → one chosen directory. The hinge, and what a row and a
#               preview pane read as.
#   choose/     how choosing LOOKS — which picker, and the pane's geometry.
#               Knows nothing about directories.
#   host/       what gets DONE with a chosen path: nvim.
use db.nu
use pick

export use db.nu entries
export use host/editor.nu

# cd into a zoxide-picked dir.
export def --env main [query?: string] {
  let dir = (pick "cd to" $query)
  if ($dir == null) { return }
  cd $dir
}

# Copy a zoxide-picked path to the system clipboard.
export def cp [query?: string] {
  let dir = (pick "copy path" $query)
  if ($dir == null) { return }
  $dir | clip copy
}

# Remove zoxide entries (multi-select).
export def remove [query?: string] {
  db remove ...(pick many "zoxide remove" $query)
}

# Add cwd to zoxide.
export def add [] {
  db add (pwd)
}

# Remove zoxide entries whose directories no longer exist.
export def sync [] {
  let gone = (db prune)
  if ($gone | is-empty) {
    print "no stale entries"
  } else {
    print $"removed ($gone | length) stale entries"
  }
}
