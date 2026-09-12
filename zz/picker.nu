# zz's two pickers, and the one switch between them.
#
# `sk` (the nu_plugin_skim command) has a preview pane; Nushell's own `input
# list` does not. That is the only difference that matters, and everything else
# in this file exists to serve the first one — the pane's position, its size, the
# keys that scroll it, and the width it hands to a preview closure.
#
# Flip SK to false and zz is back on the built-in picker, with preview.nu left
# unreachable. Nothing outside this module is consulted: zz is nobody's library,
# so it makes its own choice rather than reading it from a config hook.
#
# The plugin check is the same switch thrown on zz's behalf. `sk` parses fine
# without the plugin registered and only fails when called, and the `-n`
# launchers (zellij's Alt-a binding) start a Nushell with no plugin registry at
# all — zz should quietly use the built-in there rather than break.
const SK = true

def ready []: nothing -> bool {
  $SK and (plugin list | where name == "skim" | is-not-empty)
}

# Both pickers take the items as pipeline input and one record:
#
#   {prompt: string, display: closure, preview: closure, multi: bool}
#
# `display` renders one item as its row, the item on `$in`. `preview` renders it
# into the pane — the item on `$in` again, the pane's WIDTH as a parameter — and
# is simply never called by the picker that has no pane.
export def choose [opts: record] {
  if (ready) { $in | sk-pick $opts } else { $in | builtin-pick $opts }
}

# ---------------
#  sk
# ---------------

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
def sk-pick [opts: record] {
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

# ---------------
#  input list
# ---------------

# No preview pane, so `opts.preview` is never called and preview.nu never runs.
# The whole terminal is the list, which is why nothing trims a row here.
#
# The prompt gets zz's own accents — ANSI names, so the colours come from the
# terminal's palette (yellow → star yellow, blue → sky-swirl blue) and the
# palette stays the single source of truth.
def builtin-pick [opts: record] {
  let items = $in
  let prompt = $"(ansi yellow_bold)▸(ansi reset) (ansi blue_bold)($opts.prompt)(ansi reset)"
  if ($opts.multi? | default false) {
    $items | input list --fuzzy --multi --display $opts.display $prompt
  } else {
    $items | input list --fuzzy --display $opts.display $prompt
  }
}
