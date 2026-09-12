# zoxide-driven directory picker and friends.
# All commands present a picker over zoxide entries; an optional `query`
# narrows the list.
#
# This file is what there is to choose from and what each row reads as. How the
# choosing LOOKS is picker.nu's — including which picker it is, on the SK switch
# at the top of it — and what a directory looks like in a preview pane is
# preview.nu's.
use picker.nu choose
use preview.nu [short dir-preview]

# ------------
#  internal
# ------------

# completion source listing layouts in ~/.config/zellij/layouts/.
def layout-completer [] {
  ls ($env.HOME | path join ".config/zellij/layouts/*.kdl" | into glob)
  | get name
  | each { |p| $p | path basename | str replace ".kdl" "" }
}

# zoxide entries as {score, path} records, optionally narrowed by query. Records,
# not bare paths: a picker with a preview pane has something to show, and the
# frecency score stays available to whoever renders the row.
def candidates [query?: string] {
  let kw = if ($query | is-empty) { [] } else { [$query] }
  entries --all ...$kw
}

# single-select picker over zoxide entries. "" when nothing was chosen.
def pick [prompt: string, query?: string] {
  let chosen = (
    candidates $query
    | choose {prompt: $prompt, display: {|| short $in.path }, preview: {|width| dir-preview $width }}
  )
  if ($chosen == null) { "" } else { $chosen.path }
}

# open a zellij tab using the given layout, in a zoxide-picked dir.
# The tab is renamed to the dir's basename.
def apply-layout [layout: string, prompt: string, query?: string] {
  if ($env.ZELLIJ? | is-empty) {
    error make "not inside a zellij session"
  }
  let dir = (pick $prompt $query)
  if ($dir | is-empty) { return }
  let name = ($dir | path basename)
  zellij action new-tab --cwd $dir --layout $layout --name $name
  # The layout's `tab name=...` wins over --name, so rename explicitly.
  zellij action rename-tab $name
}

# ----------
#  public
# ----------

# List zoxide entries as a table of { score, path }.
# Keywords narrow results the same way `zoxide query` does.
export def entries [
  ...keywords: string  # narrow results by matching keywords
  --all(-a)            # include unavailable directories
  --base-dir: string   # only search within this directory
  --exclude: string    # exclude the given directory
]: nothing -> table<score: float, path: string> {
  (zoxide query
    --list
    --score
    ...(if $all { [--all] } else { [] })
    ...(if ($base_dir | is-not-empty) { [--base-dir $base_dir] } else { [] })
    ...(if ($exclude | is-not-empty) { [--exclude $exclude] } else { [] })
    ...$keywords)
  | lines
  | parse --regex '^\s*(?<score>[\d.]+)\s+(?<path>.+)$'
  | update score { into float }
}

# cd into a zoxide-picked dir.
export def --env main [query?: string] {
  let dir = (pick "cd to" $query)
  if ($dir | is-empty) { return }
  cd $dir
  zellij action rename-pane ($dir | path basename)
}

# Open a zellij tab using a chosen layout, in a zoxide-picked dir.
# If no layout is given, prompt over available layouts.
export def tab [layout?: string@layout-completer, query?: string] {
  let layout = if ($layout | is-empty) {
    layout-completer
    | choose {
      prompt: "zellij layout"
      display: {|| $in }
      # --raw: a layout is KDL, and `open` would hand back a parsed value that
      # the preview pane has no use for — the point here is to read the file.
      preview: {|| open --raw ([$env.HOME ".config" "zellij" "layouts" $"($in).kdl"] | path join) }
    }
    | default ""
  } else {
    $layout
  }
  if ($layout | is-empty) { return }
  apply-layout $layout $"new ($layout) tab" $query
}

# Copy a zoxide-picked path to the system clipboard.
export def cp [query?: string] {
  pick "copy path" $query | clip copy
}

# Remove zoxide entries (multi-select).
export def remove [query?: string] {
  let picks = (
    candidates $query
    | choose {
      prompt: "zoxide remove"
      display: {|| short $in.path }
      preview: {|width| dir-preview $width }
      multi: true
    }
    | default []
  )
  if ($picks | is-not-empty) {
    zoxide remove ...($picks | get path)
  }
}

# Add cwd to zoxide
export def add [query?: string] {
  zoxide add (pwd)
}

# Remove zoxide entries whose directories no longer exist.
export def sync [] {
  let stale = entries --all | where { |e| not ($e.path | path exists) }
  if ($stale | is-empty) {
    print "no stale entries"
    return
  }
  zoxide remove ...($stale | get path)
  print $"removed ($stale | length) stale entries"
}

# Open nvim. With piped input, edit it. With `--fuzzy`, pick a dir first.
export def editor [
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
    zellij action rename-pane $"nvim ($file)"
    return
  }
  if $tab {
    apply-layout nvim "nvim tab in"
    return
  }
  if $fuzzy {
    let dir = (pick "nvim in")
    commandline edit --replace $"cd ($dir); nvim ."
    zellij action rename-pane ($dir | path basename)
    return
  }
  zellij action rename-pane (pwd | path basename)
  ^nvim .
}
