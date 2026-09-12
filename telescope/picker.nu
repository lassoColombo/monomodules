# telescope's picker: skim, and only skim.
#
# There is no built-in fallback here on purpose. `input list` cannot draw a
# preview pane, and the preview IS this module — without one you are fuzzy-
# matching on keys you can already see, to drill into a value you cannot. That is
# not a degraded telescope, it is a worse `get`. So skim (the `sk` command from
# nu_plugin_skim) is a hard dependency, and `require-picker` says so in as many
# words rather than letting `sk` fail as an unknown external command.
#
# This is the one module where that trade is right. zz's list of paths is worth
# choosing from either way, so zz carries both pickers on a switch; telescope has
# nothing to offer without a pane.

# Checked at the ENTRY points — `explore` and `find` — not here, because every
# `choose` in this module sits inside a `try` that turns an error into "the user
# pressed Esc". A missing plugin would be swallowed as a cancel and telescope
# would hand your value straight back, which is the one failure worth being loud
# about.
export def require-picker [] {
  if (plugin list | where name == "skim" | is-empty) {
    error make --unspanned {msg: "telescope needs nu_plugin_skim — `plugin add ~/.cargo/bin/nu_plugin_skim` then `plugin use skim`"}
  }
}

# Where the preview goes and how wide its content may render.
#
# SIDE is generous — the pane holds a `table --expand` of whatever you are
# drilling through, and a value tree would rather have columns than a longer list
# of keys it has already shown you. zz splits the same terminal 62/38 because its
# rows are paths worth reading; telescope's rows are keys, and the answer is on
# the other side.
#
# Below WIDE_COLS there are not enough columns to split at all, so the preview
# goes underneath and takes the width instead. Under MIN_ROWS there is room for
# neither — and since a telescope with no preview is not telescope, that is the
# one case where the pane is simply too small for the tool.
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
#
# The palette is skim's own, from $env.SKIM_DEFAULT_OPTIONS, so nothing here
# names a colour.
const KEYS = {
  ctrl-down: "preview-down"
  ctrl-up: "preview-up"
  ctrl-d: "preview-page-down"
  ctrl-u: "preview-page-up"
}

# Items in as pipeline input, one record of what they are:
#
#   {prompt: string, display: closure, preview: closure}
#
# `display` renders one item as its row, the item on `$in`. `preview` renders it
# into the pane — the item on `$in` again, the pane's WIDTH as a parameter.
#
# No `multi` and no `query`: telescope drills one step at a time, and each step
# starts from a list it has just built.
export def choose [opts: record] {
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
