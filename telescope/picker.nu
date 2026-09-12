# telescope's two pickers, and the one switch between them.
#
# `sk` (the nu_plugin_skim command) has a preview pane; Nushell's own `input
# list` does not. For telescope that is not a cosmetic difference — the preview
# is the module's whole reason to exist, and on the built-in you drill in blind,
# by key or by column value. It still works. It is just not the same tool.
#
# Flip SK to false and telescope is on the built-in, with preview.nu left
# unreachable. Nothing outside this module is consulted: telescope is nobody's
# library — nothing imports it and it is not published — so it makes its own
# choice rather than reading it from a config hook.
#
# The plugin check is the same switch thrown on telescope's behalf. `sk` parses
# fine without the plugin registered and only fails when called, and a `nu -n`
# has no plugin registry at all — the built-in is the right answer there rather
# than a crash.
const SK = true

def ready []: nothing -> bool {
  $SK and (plugin list | where name == "skim" | is-not-empty)
}

# Both pickers take the items as pipeline input and one record:
#
#   {prompt: string, display: closure, preview: closure}
#
# `display` renders one item as its row, the item on `$in`. `preview` renders it
# into the pane — the item on `$in` again, the pane's WIDTH as a parameter — and
# is simply never called by the picker that has no pane.
#
# No `multi` and no `query`: telescope drills one step at a time, and each step
# starts from a list it has just built. Neither picker is asked for what this
# module has never wanted.
export def choose [opts: record] {
  if (ready) { $in | sk-pick $opts } else { $in | builtin-pick $opts }
}

# ---------------
#  sk
# ---------------

# Where the preview goes and how wide its content may render.
#
# SIDE is generous — the pane holds a `table --expand` of whatever you are
# drilling through, and a value tree would rather have columns than a list of
# keys it has already shown you. zz splits the same terminal 62/38 because its
# rows are paths worth reading; telescope's rows are keys, and the answer is on
# the other side.
#
# Below WIDE_COLS there are not enough columns to split at all, so the preview
# goes underneath and takes the width instead. Under MIN_ROWS there is room for
# neither, and skim reads a zero-height pane as "no preview at all".
#
# The width is measured HERE and handed over, because the closure that uses it
# runs inside the plugin, which has no terminal to measure and would answer `term
# size`'s fallback 80. Two columns come off so the widest row never lands on the
# pane's own edge.
const MIN_ROWS = 16
const WIDE_COLS = 120
const SIDE = 80   # % of a wide terminal the preview takes on the right
const UNDER = 75  # % of a narrow one it takes underneath

def pane []: nothing -> record<window: string, width: int> {
  let t = (term size)
  let beside = ($t.rows >= $MIN_ROWS and $t.columns >= $WIDE_COLS)
  let cols = if $beside { $t.columns * $SIDE // 100 } else { $t.columns }
  {
    window: (
      if $t.rows < $MIN_ROWS { "down:0" } else if $beside { $"right:($SIDE)%:wrap" } else { $"down:($UNDER)%:wrap" }
    )
    width: ([($cols - 2) 40] | math max)
  }
}

# Scrolling the preview. skim already ships two ways to do it — shift-up and
# shift-down move a line, and the mouse wheel scrolls whichever pane the pointer
# is over — but nothing page-wise, which is what a deep value wants.
#
# CTRL, not alt: zellij owns alt-h/j/k/l for pane focus and never forwards them.
# Its `normal` mode is `clear-defaults=true`, so every ctrl key does reach the
# pane. ctrl-d / ctrl-u page it the way they do in nvim.
#
# `--bind` REPLACES a default rather than layering over it, and those two keys
# had defaults worth knowing about: ctrl-d was a second Abort (esc, ctrl-c and
# ctrl-g still are), and ctrl-u cleared the query (ctrl-w still rubs out a word).
const KEYS = {
  ctrl-down: "preview-down"
  ctrl-up: "preview-up"
  ctrl-d: "preview-page-down"
  ctrl-u: "preview-page-up"
}

# The palette is skim's own, from $env.SKIM_DEFAULT_OPTIONS, so nothing here
# names a colour.
def sk-pick [opts: record] {
  let items = $in
  let p = (pane)
  # Wrapped to hand the closure the two things it cannot find out for itself:
  # the pane's width, and that there is a terminal at the far end of this at all.
  # `use_ansi_coloring: auto` reads as "no" in here — this runs inside the
  # plugin, with nothing attached — and a rendered table would arrive grey.
  let preview = {||
    let item = $in
    $env.config.use_ansi_coloring = true
    $item | do $opts.preview $p.width
  }
  $items | sk --format $opts.display --preview $preview --preview-window $p.window --bind $KEYS --layout reverse --prompt $"($opts.prompt) "
}

# ---------------
#  input list
# ---------------

# No preview pane, so `opts.preview` is never called and preview.nu never runs.
# This is telescope with its eyes shut: the keys and column values are still
# there to fuzzy-match on, and Enter still drills.
def builtin-pick [opts: record] {
  $in | input list --fuzzy --display $opts.display $opts.prompt
}
