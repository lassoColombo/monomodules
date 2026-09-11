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

# ------------
#  preview
# ------------
#
# The preview is re-rendered every time the cursor moves, so everything below it
# has to stay cheap: two git calls that read no further than the index, and one
# `ls`.

# How many changed files the git block prints before it stops and counts the
# rest. The listing under it is the point of the pane, and a repo mid-rebase
# should not push it off the bottom.
const GIT_ROWS = 8

# `git`, run in `path`, handed back as lines. Not a repo, no git installed, and
# nothing to report all come back as the same empty list, so a caller has one
# thing to test. `--no-optional-locks` keeps a preview that re-runs as you scroll
# from writing to the index of every repo it passes over.
def git-lines [path: string, args: list<string>]: nothing -> list<string> {
  let r = try { ^git -C $path --no-optional-locks ...$args | complete } catch { null }
  if ($r == null) or ($r.exit_code != 0) { return [] }
  $r.stdout | lines | where {|l| $l | is-not-empty }
}

# What the repo under `path` is doing: the branch and its distance from upstream,
# the commit it is sitting on, and everything uncommitted. "" when `path` is not
# in a repo at all, which is what keeps this section to directories that have one.
#
# The `-- .` earns its keep: a directory INSIDE a repo is still in the repo, and
# unscoped `status` answers for the whole of it — a preview of ~/.config/snip
# listing edits to ../sketchybar. The tip commit is deliberately NOT scoped; that
# one is about the checkout, not the directory.
#
# Both calls are asked for in COLOR, so nothing here has to know what a
# modification looks like. The one line recolored here is the branch: git hands
# it over as `## a...b [ahead 1]`, and the `##` says nothing once the line is
# alone under a heading.
def git-block [path: string]: nothing -> string {
  let status = (git-lines $path ["-c" "color.status=always" "status" "--short" "--branch" "--" "."])
  if ($status | is-empty) { return "" }

  let head = (git-lines $path ["log" "-1" "--color=always" "--format=%C(auto)%h%C(reset) %s %C(dim)(%cr)%C(reset)"])
  let changes = ($status | skip 1 | first $GIT_ROWS)
  let hidden = (($status | length) - 1 - ($changes | length))

  [
    $"(ansi magenta_bold)\u{e0a0} ($status.0 | ansi strip | str replace '## ' '')(ansi reset)"
    ...$head
    ...$changes
    (if $hidden > 0 { $"(ansi dark_gray)   … ($hidden) more(ansi reset)" })
  ] | compact | str join "\n"
}

# What a directory IS, for pickers that can show it: the line that names it, what
# git makes of it, and what is inside — dotfiles included, since `.git`, `.env`
# and `.claude` are half of what tells two checkouts apart.
#
# `candidates` keeps entries whose directory is gone (that is what `remove` and
# `sync` are for), so this has to survive a missing path.
#
# Returned as a STRING, not a table: three stacked sections only fit in one, and
# skim renders a string with its ANSI intact. It is also why `width` is a
# parameter rather than something measured here — see `preview-width`.
def dir-preview [width: int]: record -> string {
  let dir = $in
  let entries = (try { ls --all $dir.path } catch { null })
  if ($entries == null) { return $"(ansi red)— ($dir.path) is gone —(ansi reset)" }

  # `use_ansi_coloring: auto` reads as "no" wherever this closure runs — inside
  # the plugin, with no terminal attached — and the listing would arrive grey.
  $env.config.use_ansi_coloring = true

  [
    $"(ansi blue_bold)(short $dir.path)(ansi reset) (ansi dark_gray)· ($entries | length) entries · frecency ($dir.score | math round)(ansi reset)"
    (git-block $dir.path)
    ($entries
      | select name type size modified
      | update name { path basename }   # the pane is narrow; the path is the row
      | sort-by type name               # dirs before files, alphabetical within
      | first 200                       # a huge directory is re-rendered per keypress
      | table --width $width --index false --theme none)
  ] | where {|s| $s | is-not-empty } | str join "\n\n"
}

# Where the preview goes and how wide its table may be. One function, because the
# width follows from the split and the two must not disagree.
#
# The listing is the tallest thing in the pane and ROWS are what it runs out of.
# A `right:` pane is the FULL height of the terminal where a `down:` one is only
# a share of it, so a wide terminal hands the preview the side; a narrow one puts
# it back underneath, where the columns are. The rows lose nothing either way — a
# row is one path, and it was never the thing you were reading.
#
# Under MIN_ROWS there is room for neither, and skim reads a zero-height pane as
# "no preview at all".
#
# The width is measured HERE and captured by the closure that uses it: that
# closure runs inside the plugin, which has no terminal to measure and would
# answer skim's fallback 80. Two columns come off so the widest row never lands
# on the pane's own edge.
const MIN_ROWS = 16
const WIDE_COLS = 120
const SIDE = 62   # % of a wide terminal the preview takes on the right
const UNDER = 75  # % of a narrow one it takes underneath

def preview-pane []: nothing -> record<window: string, width: int, label: int> {
  let t = (term size)
  let beside = ($t.rows >= $MIN_ROWS and $t.columns >= $WIDE_COLS)
  let preview_cols = if $beside { $t.columns * $SIDE // 100 } else { $t.columns }
  let list_cols = if $beside { $t.columns - $preview_cols } else { $t.columns }
  {
    window: (
      if $t.rows < $MIN_ROWS { "down:0" } else if $beside { $"right:($SIDE)%" } else { $"down:($UNDER)%" }
    )
    width: ([($preview_cols - 2) 40] | math max)
    label: ([($list_cols - 2) 20] | math max)
  }
}

# A row, trimmed from the LEFT to fit `budget` columns: a path is worth more from
# its tail than its head, and the heading of the preview shows the whole of it
# anyway. `…/` marks a row that lost something.
#
# Only rows that DO NOT fit are touched, which is the whole design. Clamping
# every row to a fixed number of components instead — `path split | last 4` —
# rewrites 120 of these 173 to spare the 17 that overflow, and charges every one
# of them the `~` that says where it lives. skim matches on the row, so a
# component dropped here is a component you can no longer type at: a fair price
# for a row that was going to be cut regardless, and a bad one otherwise.
def label [path: string, budget: int]: nothing -> string {
  let parts = (short $path | path split)
  # `1..0` counts DOWN in nushell, so a one-component path must build no tails.
  let tails = if ($parts | length) < 2 { [] } else {
    1..(($parts | length) - 1) | each {|n| $"…/($parts | skip $n | path join)" }
  }
  # the whole path first, then ever-shorter tails: the first that fits wins, and
  # a basename too long for the pane is as short as this gets.
  ([($parts | path join)] | append $tails | where { ($in | str length) <= $budget } | get 0?)
  | default ($parts | last)
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
  let pane = (preview-pane)
  let chosen = (
    candidates $query
    | choose {prompt: $prompt, display: {|| label $in.path $pane.label }, preview: {|| dir-preview $pane.width }, window: $pane.window}
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
    let pane = (preview-pane)
    layout-completer
    | choose {
      prompt: "zellij layout"
      preview: {|| open ([$env.HOME ".config" "zellij" "layouts" $"($in).kdl"] | path join) }
      window: $pane.window
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
  let pane = (preview-pane)
  let picks = (
    candidates $query
    | choose {
      prompt: "zoxide remove"
      display: {|| label $in.path $pane.label }
      preview: {|| dir-preview $pane.width }
      multi: true
      window: $pane.window
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
