# The whole screen, as a list of strings.
#
# PURE, AND IT NEVER PRINTS. That is D34 for the third time — after the bar's
# `message` and zellij's `commands` — and here it is what makes an interactive
# program testable at all: a suite asserts an entire picker frame, line for
# line, with no terminal, no subprocess and no zellij.
#
#   agents ❯ zz                              ● 1 awaiting  ● 2 working
#   ──────────────────────────────────────────────────────────────────
#   > awaiting  monomodules  home
#     working   bar-preview  home
#   ──────────────────────────────────────────────────────────────────
#   ▊ Committed as 7fd6289.
#     Used git commit with the staged index only…
#   ──────────────────────────────────────────────────────────────────
#   ↑↓ move · ^j^k read · ^d^u page · enter jump · esc cancel  ▾ 12
#
# ── COLOUR (§9b.2 — the rest of it, D64) ──────────────────────────────────────
# ANSI NAMES, NOT HEX, which is the half of §9b.2 that was decided before any of
# it was written: the bar sits on a desktop and picks its own colours, but a
# terminal has a theme and a display inside it should obey. One consequence is
# worth knowing on this machine's Rosé Pine: ANSI 8 — `dark_gray` — is the
# OVERLAY tone, the colour a selection is drawn ON, so as text it is very nearly
# the background. Dim chrome is `white_dimmed` instead, the same way cmdprompt
# draws its box.
#
# THE STATES KEEP THEIR MEANINGS. Foam is turning, gold is talking to you, love
# is stuck — the three the SketchyBar counters wear and the three the zellij
# pane titles carry. One vocabulary, learned once, said here in ANSI because
# that is what a terminal speaks.
#
# ── WIDTH ─────────────────────────────────────────────────────────────────────
# Every line is truncated to the terminal's width, and every line is cleaned of
# control characters first. Both are belts: the real protection is that the loop
# turns AUTOWRAP OFF (`picker/tty.nu`), so a line too long for the terminal is
# clipped by the terminal rather than wrapped onto the next row — which would
# push the rest of the frame down and corrupt it. Measuring display columns
# exactly is not possible from here (a grapheme is not a column), so the picker
# does not try: it clips generously and lets the terminal be right.

const RULE = "─"

# The three worth counting, most urgent first — the same three the bar puts on a
# counter, and left in the same order as `rows.nu`'s `URGENCY`. Idle is not one:
# an agent with nothing to say does not need a number.
const COUNTED = ["needs-attention" "awaiting" "working"]

# EVERY BINDING, IN ONE PLACE. Adding one is a row here and a branch in
# `keys.nu`, and the reason this is a table rather than a sentence is that the
# key and the word it does are inked differently: a key is a thing you invoke,
# which is iris, and the word is a hint, which is dim.
const KEYS = [["↑↓" "move"] ["^j^k" "read"] ["^d^u" "page"]
              ["enter" "jump"] ["esc" "cancel"] ["^w" "clear"]]

# What you type at, and the only piece whose WIDTH IS LOAD-BEARING: `caret` puts
# the terminal's cursor at the end of the query, so it counts these graphemes.
# Keeping the prompt as pieces rather than as a string is what stops that count
# and this text drifting apart.
const HEAD = [{c: "brand", t: "agents"} {c: "key", t: " ❯ "}]

const INK = {
    # the preview's two kinds (D62)
    head: "yellow_bold"
    code: "blue"
    # the chrome
    brand: "yellow_bold"       # rose — the protagonist, and where you type
    mark: "yellow_bold"        # the `>`, and the name it points at
    key: "blue"                # iris — the hue that carries anything callable
    hint: "white_dimmed"
    # ROSE, LIKE THE PANE'S OWN FRAME. A rule is the only full-width thing here,
    # so it is what ties the picker to the border zellij draws around it rather
    # than something to be got out of the way. Rose at normal weight; the three
    # things that are PROTAGONISTS — the prompt, the marker and the name it
    # points at — are the same hue in BOLD, which is what keeps them louder than
    # a line that runs the width of the terminal.
    rule: "yellow"
    location-label: "white_dimmed"
    # the states, in the vocabulary the bar and the pane titles already use
    needs-attention: "red"     # love
    awaiting: "magenta"        # gold, on this palette
    working: "cyan"            # foam
    idle: "white_dimmed"
}

# A KIND THAT IS NOT IN THE MAP IS NOT PAINTED, which is how a preview paragraph
# stays the terminal's own foreground and how a name stays whatever the reader
# set their text to.
def ink [c: any, t: string]: nothing -> string {
    let name = if ($c == null) { null } else { $INK | get -o $c }
    if ($name == null) or ($t | is-empty) { return $t }
    $"(ansi $name)($t)(ansi reset)"
}

def rep [s: string, n: int]: nothing -> string {
    if $n <= 0 { return "" }
    1..$n | each {|| $s } | str join
}

# Anything that could move the cursor or widen a line, taken out. Tabs become a
# space for the same reason: one tab can carry a line past the right edge.
def clean [line: string]: nothing -> string {
    $line
    | ansi strip
    | str replace --all --regex "\t" " "
    | str replace --all --regex "[\u{0}-\u{8}\u{b}-\u{1f}\u{7f}]" " "
}

# Cleaned and cut, WITHOUT trimming — the spaces between a row's columns are
# load-bearing and this runs on each piece separately.
def cut [s: string, width: int]: nothing -> string {
    let c = clean $s
    if ($c | str length --grapheme-clusters) <= $width { return $c }
    $c | str substring --grapheme-clusters 0..<$width
}

def clip [s: string, width: int]: nothing -> string { cut $s $width | str trim --right }

def pad [s: string, width: int]: nothing -> string {
    clean $s | fill --width $width --alignment left
}

# ── pieces ────────────────────────────────────────────────────────────────────
# A line is built as `{c, t}` — an ink, and the text it covers — and MEASURED IN
# PLAIN TEXT, coloured only at the end. Same order as the preview, for the same
# two reasons: a terminal counts what a reader sees rather than what a line
# holds, and some of this text was written by an agent.

def wide [ps: list<record>]: nothing -> int {
    $ps | each {|p| $p.t | str length --grapheme-clusters } | append 0 | math sum
}

# Pieces to a finished line. What falls past the right edge is dropped, the
# piece straddling it is cut, and the tail is trimmed — a repaint finishes every
# line with EL, so a trailing space is never needed and would only mean the
# suite asserting invisible characters.
def line [ps: list<record>, width: int]: nothing -> string {
    mut kept = []
    mut room = $width
    for p in $ps {
        if $room <= 0 { break }
        let t = cut $p.t $room
        $room = $room - ($t | str length --grapheme-clusters)
        $kept = $kept ++ [($p | update t $t)]
    }
    trim-tail $kept | each {|p| ink $p.c $p.t } | str join
}

# Trailing space taken off the END OF THE LINE, not the end of a piece: an agent
# with no place leaves an empty one there, and behind it a separator, and behind
# THAT the padding that lined its name up. Trimming only the last piece would
# leave all of it — a row of invisible characters for the suite to assert.
#
# No output signature: a def annotated with one cannot END IN A LOOP — nushell
# reads the loop as producing nothing and rejects the whole def (§10, the same
# rule that keeps `resolve-binary` unannotated for ending in `error make`).
def trim-tail [ps: list<record>] {
    mut out = $ps
    loop {
        if ($out | is-empty) { return [] }
        let end = $out | last | update t (($out | last).t | str trim --right)
        if ($end.t | is-not-empty) { return (($out | drop 1) ++ [$end]) }
        $out = $out | drop 1
    }
}

# Two halves, the right one pushed to the edge. THE RIGHT HALF GOES FIRST when a
# terminal is too narrow for both: it is the glanceable extra, and the left half
# is what the line is for.
def bar [left: list<record>, right: list<record>, width: int]: nothing -> string {
    let l = wide $left
    let r = wide $right
    if (($r == 0) or (($l + $r + 2) > $width)) { return (line $left $width) }
    line ($left ++ [{c: null, t: (rep " " ($width - $l - $r))}] ++ $right) $width
}

# Lines of chrome the frame always spends, and it must match `render` exactly:
# the header, the footer, and the three rules that separate them from the list
# and the preview. Counted wrong, the frame is one line taller than the terminal
# — which scrolls it, and the next repaint homes to the wrong row and stays
# wrong. The cap at the end of `render` is the belt; this is the braces.
const NON_LIST_LINES = 5

# How the screen is divided. The list takes what it needs up to half of what is
# left; the preview takes the rest — which is the right way round, because the
# rows say WHICH agents exist and the preview says what the one under the cursor
# actually wants from you.
export def measure [size: record, count: int]: nothing -> record {
    let height = $size.rows? | default 24
    let width = $size.columns? | default 80
    let avail = $height - $NON_LIST_LINES
    if $avail < 2 {
        return {list: 1, preview: 0, width: $width, height: $height}
    }
    let want = [$count 1] | math max
    let list = [$want ($avail // 2)] | math min
    {list: $list, preview: ($avail - $list), width: $width, height: $height}
}

# Where the terminal cursor should sit: at the end of what you have typed, which
# is what makes it the filter's caret and means the picker never has to hide it
# (and so can never leave it hidden). 1-based, the way terminals count.
export def caret [view: record]: nothing -> int {
    # One line, because an arithmetic expression does not continue across lines
    # with the operator at either end — nushell reads the next line as a fresh
    # pipeline and `+` is not a command (§10).
    let typed = ($view.query? | default "") | str length --grapheme-clusters
    ((wide $HEAD) + $typed + 1)
}

# What the fleet is doing, at a glance, while you read one agent's answer. A
# state nothing is in is not shown: a zero is not news, and the row is filter.
def tally [rows: list<record>]: nothing -> list<record> {
    $COUNTED | each {|st|
        let n = $rows | where state == $st | length
        if $n == 0 { [] } else { [{c: $st, t: $"● ($n) ($st)"} {c: null, t: "  "}] }
    } | flatten
}

# One agent. The state carries its own colour, the place is dim because it is
# context rather than current-session, and the SELECTION IS ROSE — the marker
# and the name together, so the cursor is one object rather than a stray `>`.
def listing [r: record, on: bool, ws: record]: nothing -> list<record> {
    [ {c: (if $on { "mark" } else { null }), t: (if $on { "> " } else { "  " })}
      {c: $r.state, t: (pad $r.state $ws.state)}
      {c: null, t: "  "}
      {c: (if $on { "mark" } else { null }), t: (pad $r.name $ws.name)}
      {c: null, t: "  "}
      {c: "location-label", t: $r.location-label} ]
}

export def render [
    rows: list<record>      # the filtered rows, in order
    view: record            # {sel, query, top, pv_top}
    lay: record             # from `layout`
    preview: list<record>   # the selected agent's message, as {k, t}, cut to lay.preview
]: nothing -> list<string> {
    let w = $lay.width
    let rule = line [{c: "rule", t: (rep $RULE $w)}] $w

    let ws = {
        state: ($rows | each {|r| $r.state | str length --grapheme-clusters } | append 1 | math max)
        name: ($rows | each {|r| clean $r.name | str length --grapheme-clusters } | append 1 | math max)
    }

    let listed = if ($rows | is-empty) {
        # Why it is empty, because the two reasons need different reactions:
        # backspace, or go and start an agent.
        let why = if ((($view.query? | default "") | is-empty)) { "  (no agents)" } else { "  (nothing matches)" }
        [(line [{c: "hint", t: $why}] $w)]
    } else {
        $rows
        | enumerate
        | skip $view.top
        | first $lay.list
        | each {|e| line (listing $e.item ($e.item.id == ($view.sel? | default "")) $ws) $w }
    }

    # How far down the message you have read, and nothing at all when you have
    # not — an indicator that is always there stops being one.
    let at = $view.pv_top? | default 0
    let where = if $at > 0 { [{c: "hint", t: $"▾ ($at)"}] } else { [] }
    let keys = $KEYS | each {|k| [{c: "key", t: ($k | first)} {c: "hint", t: $" ($k | last)  "}] } | flatten

    let body = [
        (bar ($HEAD ++ [{c: null, t: ($view.query? | default "")}]) (tally $rows) $w)
        $rule
        ...$listed
        $rule
        # Clipped, THEN coloured — see `line`. The preview's text is an agent's,
        # so the strip inside `clean` stays a defence: colour goes on after it,
        # where nothing in a message can smuggle an escape through.
        ...($preview | first $lay.preview | each {|r| line [{c: $r.k, t: $r.t}] $w })
        $rule
        (bar $keys $where $w)
    ]
    # Never more lines than the terminal has: one row too many scrolls the frame
    # and the next repaint lands in the wrong place.
    $body | first ([($body | length) $lay.height] | math min)
}
