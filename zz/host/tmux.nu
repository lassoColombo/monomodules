# The tmux session zz is running inside: its windows, its pane names, its layouts.
#
# zellij.nu's twin, with the same five commands, so mux.nu can hand a call to
# whichever of the two is in charge. The one check for being inside a session
# answers the same way zellij.nu's does: naming a pane goes quiet, opening a tab
# says so.
#
# tmux has no layout files. A layout here is a nushell script in
# ~/.config/tmux/layouts whose `main [pane dir]` furnishes a window that already
# exists, given its first pane. A pane's name is its @name option, which the
# tmux.conf frames show in place of the title programs set.
#
# `^tmux` throughout, for the reason zellij.nu spells `^zellij`.
use ../pick
use ../choose

def inside []: nothing -> bool {
  $env.TMUX? | is-not-empty
}

# Name the focused pane. Outside a session there is nothing to name.
export def rename-pane [name: string] {
  if (inside) { ^tmux set -p -t $env.TMUX_PANE @name $name }
}

# Name the focused tab.
export def rename-tab [name: string] {
  if (inside) { ^tmux rename-window -t $env.TMUX_PANE $name }
}

# The layouts on disk, by bare name. Doubles as a completion source.
export def layouts []: nothing -> list<string> {
  ls ($env.HOME | path join ".config/tmux/layouts/*.nu" | into glob)
  | get name
  | each { |p| $p | path basename | str replace ".nu" "" }
}

# The file a layout name stands for.
def layout-path [name: string]: nothing -> string {
  [$env.HOME ".config" "tmux" "layouts" $"($name).nu"] | path join
}

# Pick a layout by reading it. `null` when nothing was chosen.
export def choose-layout []: nothing -> any {
  layouts
  | choose {
    prompt: "tmux layout"
    display: {|| $in }
    preview: {|| open --raw (layout-path $in) }
  }
}

# Open a tab using the given layout, in a zoxide-picked dir.
# The tab is named after the dir's basename.
export def tab [layout: string, prompt: string, query?: string] {
  if not (inside) {
    error make {msg: "not inside a tmux session"}
  }
  let dir = (pick $prompt $query)
  if ($dir == null) { return }
  let pane = ^tmux new-window -c $dir -n ($dir | path basename) -P -F "#{pane_id}"
  ^nu (layout-path $layout) $pane $dir
}
