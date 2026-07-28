# zoxide-driven directory picker and friends.
# All commands present a picker over zoxide entries; an optional `query`
# narrows the list.

# ------------
#  internal
# ------------

# decorate a picker prompt with starry-cat accents. Uses ANSI names so the
# rendered colors come from alacritty's palette (yellow → base0A star
# yellow, blue → base0D sky-swirl blue), keeping the palette as the single
# source of truth.
def styled-prompt [text: string]: nothing -> string {
  $"(ansi yellow_bold)▸(ansi reset) (ansi blue_bold)($text)(ansi reset)"
}

# completion source listing layouts in ~/.config/zellij/layouts/.
def layout-completer [] {
  ls ($env.HOME | path join ".config/zellij/layouts/*.kdl" | into glob)
  | get name
  | each { |p| $p | path basename | str replace ".kdl" "" }
}

# zoxide entries, optionally narrowed by query.
def candidates [query?: string] {
  let kw = if ($query | is-empty) { [] } else { [$query] }
  entries --all ...$kw | get path
}

# single-select picker over zoxide entries.
def pick [prompt: string, query?: string] {
  candidates $query
  | input list --fuzzy (styled-prompt $prompt)
  | default ""
}

# open a zellij tab using the given layout, in a zoxide-picked dir.
# The tab is renamed to the dir's basename.
def apply-layout [layout: string, prompt: string, query?: string] {
  if ($env.ZELLIJ? | is-empty) {
    print "not inside a zellij session"
    return
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
}

# Open a zellij tab using a chosen layout, in a zoxide-picked dir.
# If no layout is given, prompt over available layouts.
export def tab [layout?: string@layout-completer, query?: string] {
  let layout = if ($layout | is-empty) {
    layout-completer
    | input list --fuzzy (styled-prompt "zellij layout")
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
    | input list --fuzzy --multi (styled-prompt "zoxide remove")
    | default []
  )
  if ($picks | is-not-empty) {
    zoxide remove ...$picks
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
    return
  }
  if $tab {
    apply-layout nvim "nvim tab in"
    return
  }
  if $fuzzy {
    let dir = (pick "nvim in")
    commandline edit --replace $"cd ($dir); nvim ."
    return
  }
  ^nvim .
}
