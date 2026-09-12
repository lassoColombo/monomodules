# The picker with a pane, and everything the pane needs.

# Where the preview goes and how wide its content may render.
#
# The listing is the tallest thing in the pane and ROWS are what it runs out of.
# A `right:` pane is the FULL height of the terminal where a `down:` one is only
# a share of it, so a wide terminal hands the preview the side; a narrow one puts
# it back underneath, where the columns are. The rows lose nothing either way —
# a row is one path, and it was never the thing you were reading.
#
# Under MIN_ROWS there is room for neither, and skim reads a zero-height pane as
# "no preview at all".
#
# The width is measured HERE and handed over, because the closure that uses it
# runs inside the plugin, which has no terminal to measure and would answer `term
# size`'s fallback 80. Two columns come off so the widest row never lands on the
# pane's own edge.
const MIN_ROWS = 16
const WIDE_COLS = 120
const SIDE = 62   # % of a wide terminal the preview takes on the right
const UNDER = 75  # % of a narrow one it takes underneath

def pane []: nothing -> record<window: string, width: int> {
  let t = (term size)
  let beside = ($t.rows >= $MIN_ROWS and $t.columns >= $WIDE_COLS)
  let cols = if $beside { $t.columns * $SIDE // 100 } else { $t.columns }
  {
    window: (
      if $t.rows < $MIN_ROWS { "down:0" } else if $beside { $"right:($SIDE)%" } else { $"down:($UNDER)%" }
    )
    width: ([($cols - 2) 40] | math max)
  }
}

# Scrolling the preview. skim already ships two ways to do it — shift-up and
# shift-down move a line, and the mouse wheel scrolls whichever pane the pointer
# is over — but nothing page-wise, which is what a listing longer than its pane
# wants.
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
export def pick [opts: record] {
  let items = $in
  let p = (pane)
  # Wrapped to hand the closure the two things it cannot find out for itself:
  # the pane's width, and that there is a terminal at the far end of this at all.
  # `use_ansi_coloring: auto` reads as "no" in here — this runs inside the
  # plugin, with nothing attached — and a coloured render would arrive grey.
  let preview = {||
    let item = $in
    $env.config.use_ansi_coloring = true
    $item | do $opts.preview $p.width
  }
  let prompt = $"($opts.prompt) "

  if ($opts.multi? | default false) {
    $items | sk --multi --format $opts.display --preview $preview --preview-window $p.window --bind $KEYS --layout reverse --prompt $prompt
  } else {
    $items | sk --format $opts.display --preview $preview --preview-window $p.window --bind $KEYS --layout reverse --prompt $prompt
  }
}
