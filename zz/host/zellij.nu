# The session zz is running inside: its tabs, its pane names, its layouts.
#
# Every `zellij action` in the module is here, and so is the one check for
# whether there is a session at all. The two answers to being outside one are
# deliberately different: naming a pane is decoration, so it goes quiet, while
# opening a tab is the whole of what was asked for, so it says so.
#
# `^zellij` throughout — this module is itself called `zellij` once imported, and
# the caret keeps the binary and the module from reading as the same word.
use ../pick
use ../choose

def inside []: nothing -> bool {
  $env.ZELLIJ? | is-not-empty
}

# Name the focused pane. Outside a session there is nothing to name.
export def rename-pane [name: string] {
  if (inside) { ^zellij action rename-pane $name }
}

# Name the focused tab.
export def rename-tab [name: string] {
  if (inside) { ^zellij action rename-tab $name }
}

# The layouts on disk, by bare name. Doubles as a completion source.
export def layouts []: nothing -> list<string> {
  ls ($env.HOME | path join ".config/zellij/layouts/*.kdl" | into glob)
  | get name
  | each { |p| $p | path basename | str replace ".kdl" "" }
}

# The file a layout name stands for.
def layout-path [name: string]: nothing -> string {
  [$env.HOME ".config" "zellij" "layouts" $"($name).kdl"] | path join
}

# Pick a layout by reading it. `null` when nothing was chosen.
export def choose-layout []: nothing -> any {
  layouts
  | choose {
    prompt: "zellij layout"
    display: {|| $in }
    # --raw: a layout is KDL, and `open` would hand back a parsed value that
    # the preview pane has no use for — the point here is to read the file.
    preview: {|| open --raw (layout-path $in) }
  }
}

# Open a tab using the given layout, in a zoxide-picked dir.
# The tab is renamed to the dir's basename.
export def tab [layout: string, prompt: string, query?: string] {
  if not (inside) {
    error make {msg: "not inside a zellij session"}
  }
  let dir = (pick $prompt $query)
  if ($dir == null) { return }
  let name = ($dir | path basename)
  ^zellij action new-tab --cwd $dir --layout $layout --name $name
  # The layout's `tab name=...` wins over --name, so rename explicitly.
  rename-tab $name
}
