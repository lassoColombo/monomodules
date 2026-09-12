# zoxide-driven directory picker and friends.
# All commands present a picker over zoxide entries; an optional `query`
# narrows the list.

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
# a picker renders a string with its ANSI intact. `width` is the pane's, handed
# over by the picker that owns it — this closure runs wherever that picker runs,
# which may be somewhere with no terminal to measure.
def dir-preview [width: int]: record -> string {
  let dir = $in
  let entries = (try { ls --all $dir.path } catch { null })
  if ($entries == null) { return $"(ansi red)— ($dir.path) is gone —(ansi reset)" }

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

# Choosing goes through ONE hook: `$env.zz_config.picker`, a closure that takes
# the items as pipeline input and an options record {prompt, display, preview,
# multi} — see ~/.config/nushell/module-hooks.nu. zz says what there is to choose
# from and what each item says; the frame, the sizing, the preview pane and every
# key belong to the picker, which is why nothing handed over here is a number.
#
# With nothing configured that picker is Nushell's built-in `input list`, which
# is why zz needs no plugin. It has no preview pane and drops `preview` on the
# floor; an engine that has one is handed the width to fill it, and shows you
# what is inside a directory before you cd into it.
def choose [opts: record] {
  let items = $in
  let custom = $env.zz_config?.picker?
  if ($custom != null) { return ($items | do $custom $opts) }
  if ($opts.multi? | default false) {
    $items | input list --fuzzy --multi --display $opts.display $opts.prompt
  } else {
    $items | input list --fuzzy --display $opts.display $opts.prompt
  }
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
