# What a directory looks like to a human: the row it gets in the list, and the
# pane beside it. Nothing in this file runs under the built-in picker, which has
# no pane — see picker.nu, and the SK switch at the top of it.
#
# The preview is re-rendered every time the cursor moves, so everything here has
# to stay cheap: two git calls that read no further than the index, and one `ls`.

# `$HOME` written as `~`: a zoxide list is mostly one user's own tree, and 15
# columns of "/Users/colombos" on every row say nothing.
export def short [path: string] {
  $path | str replace $env.HOME "~"
}

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
export def dir-preview [width: int]: record -> string {
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
