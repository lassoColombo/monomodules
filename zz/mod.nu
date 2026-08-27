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

# zoxide entries as {score, path} records, optionally narrowed by query. Records,
# not bare paths: a picker with a preview pane has something to show, and the
# frecency score stays available to whoever renders the row.
def candidates [query?: string] {
  let kw = if ($query | is-empty) { [] } else { [$query] }
  entries --all ...$kw
}

# `$HOME` written as `~`: a zoxide list is mostly one user's own tree, and 15
# columns of "/Users/colombos" on every row say nothing.
def short [path: string] {
  $path | str replace $env.HOME "~"
}

# What a directory IS, for pickers that can show it. `--all` keeps entries whose
# directory is gone (that is what `remove` and `sync` are for), so this has to
# survive a missing path.
#
# Returned as a TABLE, not a string: the picker renders it with `table --width
# <the pane it actually drew>`, so the columns size themselves and nothing here
# has to know how wide the preview is.
def dir-preview [] {
  let path = $in.path
  try {
    ls $path
    | select name type size modified
    | update name { path basename }   # the pane is narrow; the path is the row
    | sort-by type name               # dirs before files, alphabetical within
    | first 200                       # a huge directory is re-rendered per keypress
  } catch { $"— ($path) is gone —" }
}

# The preview pane, for an engine that has one (see `choose`). It sits UNDER the
# list and gets the bigger share of the height. Full width is what these previews
# want: a directory listing is a table, and a table beside the rows has to fit its
# columns into half a screen, where one under them gets the whole of it.
#
# The rows lose nothing by it — a row is one path, and it was never the thing you
# were reading.
#
# Under MIN_ROWS there is no room for both, so the preview goes and the rows take
# the whole pane: skim reads a zero-height pane as "no preview at all".
const PREVIEW = "down:60%"
const MIN_ROWS = 16

def preview-window [] {
  if (term size).rows < $MIN_ROWS { "down:0" } else { $PREVIEW }
}

# Choosing goes through ONE hook: `$env.zz_config.picker`, a closure that takes
# the items as pipeline input and an options record {prompt, display, preview,
# multi, window}. With nothing configured this is Nushell's built-in `input list`, which
# is why zz needs no plugin; an engine that has a preview pane is handed a way to
# render one, and shows you what is inside a directory before you cd into it.
def choose [opts: record] {
  let items = $in
  let custom = $env.zz_config?.picker?
  if ($custom != null) { return ($items | do $custom $opts) }
  # `default` would EVALUATE a closure handed to it, so spell the fallback out.
  let display = if ($opts.display? == null) { {|| $in | to text } } else { $opts.display }
  let prompt = styled-prompt ($opts.prompt? | default "")
  if ($opts.multi? | default false) {
    $items | input list --fuzzy --multi --display $display $prompt
  } else {
    $items | input list --fuzzy --display $display $prompt
  }
}

# single-select picker over zoxide entries. "" when nothing was chosen.
def pick [prompt: string, query?: string] {
  let chosen = (
    candidates $query
    | choose {prompt: $prompt, display: {|| short $in.path }, preview: {|| dir-preview }, window: (preview-window)}
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
      preview: {|| open ([$env.HOME ".config" "zellij" "layouts" $"($in).kdl"] | path join) }
      window: (preview-window)
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
      preview: {|| dir-preview }
      multi: true
      window: (preview-window)
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
