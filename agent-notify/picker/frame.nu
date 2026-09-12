# The whole screen, as a list of strings.
#
# PURE, AND IT NEVER PRINTS. That is D34 for the third time — after the bar's
# `message` and zellij's `commands` — and here it is what makes an interactive
# program testable at all: a suite asserts an entire picker frame, line for line,
# with no terminal, no subprocess and no zellij.
#
#   agents  zz
#   ──────────────────────────────────────
#   > awaiting  monomodules  home/root
#     working   bar-preview  home/root
#   ──────────────────────────────────────
#   ⏺ Committed as 7fd6289.
#     Used git commit with the staged index only…
#   ──────────────────────────────────────
#   ↑↓ move · enter jump · esc cancel · type to filter
#
# DELIBERATELY PLAIN. No colour and no glyphs yet: the state is spelled out, the
# selection is a `>`, and that is the whole vocabulary. A palette is a separate
# question and gets a separate pass (plan.md §9b.2) — freezing one now would only
# mean asserting escape codes in the suite and revising them later. Whoever adds
# it should read §9b.2 first: the suite compares WHOLE FRAMES, and colour put in
# naively turns every one of those assertions into an escape-code diff.
#
# ── WIDTH ────────────────────────────────────────────────────────────────────
# Every line is truncated to the terminal's width, and every line is cleaned of
# control characters first. Both are belts: the real protection is that the loop
# turns AUTOWRAP OFF (`picker/tty.nu`), so a line too long for the terminal is
# clipped by the terminal rather than wrapped onto the next row — which would
# push the rest of the frame down and corrupt it. Measuring display columns
# exactly is not possible from here (a grapheme is not a column), so the picker
# does not try: it clips generously and lets the terminal be right.

const PROMPT = "agents  "
const RULE = "─"
const FOOT = "↑↓ move · enter jump · esc cancel · type to filter"

# Lines of chrome the frame always spends, and it must match `render` exactly:
# the header, the footer, and the three rules that separate them from the list
# and the preview. Counted wrong, the frame is one line taller than the terminal
# — which scrolls it, and the next repaint homes to the wrong row and stays
# wrong. The cap at the end of `render` is the belt; this is the braces.
const CHROME = 5

# How the screen is divided. The list takes what it needs up to half of what is
# left; the preview takes the rest — which is the right way round, because the
# rows say WHICH agents exist and the preview says what the one under the cursor
# actually wants from you.
export def layout [size: record, count: int]: nothing -> record {
    let height = $size.rows? | default 24
    let width = $size.columns? | default 80
    let avail = $height - $CHROME
    if $avail < 2 {
        return {list: 1, preview: 0, width: $width, height: $height}
    }
    let want = [$count 1] | math max
    let list = [$want ($avail // 2)] | math min
    {list: $list, preview: ($avail - $list), width: $width, height: $height}
}

# Anything that could move the cursor or widen a line, taken out. Tabs become a
# space for the same reason: one tab can carry a line past the right edge.
def clean [line: string]: nothing -> string {
    $line
    | ansi strip
    | str replace --all --regex "\t" " "
    | str replace --all --regex "[\u{0}-\u{8}\u{b}-\u{1f}\u{7f}]" " "
}

# Trailing space is taken off as well as excess width. It is never needed — the
# repaint finishes every line with `EL`, which erases whatever was there — and
# carrying it would only mean the suite asserting invisible characters.
def clip [line: string, width: int]: nothing -> string {
    let s = clean $line | str trim --right
    if ($s | str length --grapheme-clusters) <= $width { return $s }
    $s | str substring --grapheme-clusters 0..<$width | str trim --right
}

def pad [s: string, width: int]: nothing -> string {
    $s | fill --width $width --alignment left
}

# Where the terminal cursor should sit: at the end of what you have typed, which
# is what makes it the filter's caret and means the picker never has to hide it
# (and so can never leave it hidden). 1-based, the way terminals count.
export def caret [view: record]: nothing -> int {
    # One line, because an arithmetic expression does not continue across lines
    # with the operator at either end — nushell reads the next line as a fresh
    # pipeline and `+` is not a command (§10).
    let typed = ($view.query? | default "") | str length --grapheme-clusters
    (($PROMPT | str length --grapheme-clusters) + $typed + 1)
}

export def render [
    rows: list<record>      # the filtered rows, in order
    view: record            # {sel, query, top}
    lay: record             # from `layout`
    preview: list<string>   # the selected agent's screen, already cut to lay.preview
]: nothing -> list<string> {
    let w = $lay.width
    let rule = 1..$w | each {|| $RULE } | str join

    let w_state = $rows | each {|r| $r.state | str length --grapheme-clusters } | append 1 | math max
    let w_name = $rows | each {|r| $r.name | str length --grapheme-clusters } | append 1 | math max

    let listed = if ($rows | is-empty) {
        # Why it is empty, because the two reasons need different reactions:
        # backspace, or go and start an agent.
        if (($view.query? | default "") | is-empty) { ["  (no agents)"] } else { ["  (nothing matches)"] }
    } else {
        $rows
        | enumerate
        | skip $view.top
        | first $lay.list
        | each {|e|
            let mark = if ($e.item.id == ($view.sel? | default "")) { "> " } else { "  " }
            $"($mark)(pad $e.item.state $w_state)  (pad $e.item.name $w_name)  ($e.item.place)"
          }
    }

    let body = [
        $"($PROMPT)($view.query? | default '')"
        $rule
        ...$listed
        $rule
        ...($preview | first $lay.preview)
        $rule
        $FOOT
    ]
    # Never more lines than the terminal has: one row too many scrolls the frame
    # and the next repaint lands in the wrong place.
    $body | each {|l| clip $l $w } | first ([($body | length) $lay.height] | math min)
}
