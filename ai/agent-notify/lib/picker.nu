# Terminal twin of the SketchyBar drawers: the live agents as a filterable list,
# with the SELECTED agent's message previewed underneath it in full. Returns the
# chosen record, or null when there is nothing to show or the user cancels.
# Presentation ONLY — the `browse` verb in mod.nu owns the jump.
#
# Hand-rolled on `input listen` rather than `input list`, because the built-in
# picker has no preview pane: the message had to be squeezed into a table column,
# which is exactly what made it unreadable. WHAT to show still comes entirely
# from lib/view.nu — the same helpers the bar paints with — so the two surfaces
# cannot drift apart; only the terminal-side chrome lives here.
#
# The frame is redrawn in place on every keystroke (see `paint`): the caret is
# parked on its first line, so the next frame just clears from there down. Its
# height comes from the pane, and the list keeps the height of the UNFILTERED
# set, so nothing jumps around while you type.

use view.nu *
use title.nu *

const PV_MAX = 10           # preview lines, when the pane can afford them
const LIST_MIN = 3          # never squeeze the list below this
const COLS_FALLBACK = 100   # when the pane size is unknown (no tty)

# state → terminal colour: the palette-facing half of the mapping the bar makes
# with its own hex values. ANSI names, so the terminal theme stays in charge —
# the shapes themselves are `glyph-of`, shared with every other surface.
def color-of [state: string] {
    if $state == "needs-attention" { ansi light_red_bold
    } else if $state == "awaiting" { ansi yellow_bold
    } else if $state == "working" { ansi cyan
    } else { ansi dark_gray }
}

def rep [ch: string, n: int] { if $n <= 0 { "" } else { 0..<$n | each { $ch } | str join "" } }

# Cut a string to `width` visible chars, ellipsised — untouched when it fits, so
# a label keeps the exact spacing the bar gives it (view.nu does the wrapping).
def cut [text: string, width: int] {
    if ($text | str length) <= $width { $text } else { wrap-text $text $width 1 | get -o 0 | default "" }
}

# The rows to choose from: one cell per agent, in the shared order, each carrying
# the record it came from so the selection maps straight back.
def cells-of [recs: list<any>] {
    sort-agents $recs | each {|r|
        let s = $r.state? | default "idle"
        # `bare-title` joins the non-empty halves, so an idle agent (no glyph)
        # still lines up with the rest of the column.
        # `msg` is the flattened copy the filter matches against; `text` is the
        # message as stored, line structure intact, for the preview pane below.
        let text = $r.preview? | default ""
        { kind: $s, state: (bare-title (glyph-of $s) $s), agent: (label $r), msg: (one-line $text), text: $text, rec: $r }
    }
}

# Free-text filter, over the same text the frame shows.
def matches [cell: record, query: string] {
    if ($query | is-empty) { return true }
    ($"($cell.state) ($cell.agent) ($cell.msg)" | str lowercase) | str contains ($query | str lowercase)
}

# One frame, as plain lines: query, rule, the list window (padded to a fixed
# height), rule, the selected agent's message. Pure — no I/O, so the layout can
# be exercised without a terminal.
def frame [cells: list<any>, sel: int, query: string, off: int, list_h: int, pv_h: int, cols: int] {
    let count = if ($cells | is-empty) { "no match" } else { $"($sel + 1)/($cells | length)" }
    let head = $"❯ ($query)"
    let pad = rep " " ([1 ($cols - ($head | str length) - ($count | str length) - 1)] | math max)
    let rule = $"(ansi dark_gray)(rep '─' $cols)(ansi reset)"

    let w_state = $cells | each {|c| $c.state | str length } | append 0 | math max
    let w_agent = [10 ($cols - $w_state - 4)] | math max
    let rows = $cells | skip $off | take $list_h | enumerate | each {|e|
        let c = $e.item
        let on = ($e.index + $off) == $sel
        let st = $c.state + (rep " " ($w_state - ($c.state | str length)))
        let name = cut $c.agent $w_agent
        $"(if $on { $'(ansi green_bold)❯(ansi reset) ' } else { '  ' })(color-of $c.kind)($st)(ansi reset)  (if $on { ansi default_bold } else { '' })($name)(ansi reset)"
    }

    let cur = $cells | get -o $sel
    let text = if ($cur == null) { "" } else if ($cur.msg | is-empty) { "— no message —" } else { $cur.text }
    # Plain foreground: this is the text you opened the picker to read. The dim
    # ink is for chrome (rules, counter), not for content.
    let pv = preview-lines $text ($cols - 4) $pv_h | each {|l| $"  ($l)" }

    # Both blocks are padded to their full height: a fixed frame means the eye
    # (and the redraw arithmetic) never has to chase a moving layout.
    let gap_rows = 0..<([0 ($list_h - ($rows | length))] | math max) | each { "" }
    let gap_pv = 0..<([0 ($pv_h - ($pv | length))] | math max) | each { "" }
    let head_line = $"(ansi green_bold)($head)(ansi reset)($pad)(ansi dark_gray)($count)(ansi reset)"
    [$head_line $rule]
    | append $rows | append $gap_rows
    | append $rule | append $pv | append $gap_pv
}

# Wipe the frame: the caret is parked ON its first line, so clearing from there
# down removes it whole.
def wipe [] { print -n $"(ansi -e '1G')(ansi -e '0J')" }

# Draw a frame in place of the last one and park the caret at the end of the
# query. The terminal's own cursor IS the caret — nothing is hidden, so an
# interrupt can never leave the terminal without one.
def paint [lines: list<string>, caret: int] {
    wipe
    print ($lines | str join "\n")
    # `print` ends with a newline, so the caret is one line BELOW the frame:
    # walking up its full height is what lands on the query line.
    print -n (ansi -e $"($lines | length)F")
    if $caret > 0 { print -n (ansi -e $"($caret)C") }
}

# What a keypress means. Anything else is ignored (no beeping, no surprises).
def action [k: record] {
    let ctrl = ($k.modifiers? | default [] | any {|m| $m =~ "control" })
    let code = $k.code? | default ""
    if ($k.key_type? | default "") == "char" {
        if $ctrl {
            # ctrl-j / ctrl-m ARE Enter: some terminals hand the newline over as a
            # control char in raw mode instead of the `enter` key below.
            if $code in ["j" "m"] { "accept"
            } else if $code == "c" { "cancel" } else if $code == "n" { "down" } else if $code == "p" { "up"
            } else if $code in ["u" "w"] { "clear" } else { "none" }
        } else if ($k.modifiers? | default [] | any {|m| ($m =~ "alt") or ($m =~ "super") }) { "none"
        } else { $"type:($code)" }
    } else if $code in ["esc"] { "cancel"
    } else if $code in ["enter"] { "accept"
    } else if $code in ["up" "backtab"] { "up"
    } else if $code in ["down" "tab"] { "down"
    } else if $code in ["backspace" "delete"] { "back"
    } else { "none" }
}

# Present the agents, return the picked record (null on cancel / nothing to show).
export def pick [recs: list<any>, query?: string] {
    let all = cells-of $recs
    # Nothing to pick from is not worth a full-screen frame — say so and leave.
    if ($all | where {|c| matches $c ($query | default "") } | is-empty) {
        print $"(ansi dark_gray)(if ($all | is-empty) { 'no agents' } else { $'no agent matches ($query)' })(ansi reset)"
        return null
    }

    mut q = $query | default ""
    mut sel = 0
    mut off = 0
    mut out: any = null   # `any`: a bare null would type-lock the binding to nothing

    loop {
        let sz = term size
        let cols = if (($sz.columns? | default 0) > 20) { $sz.columns } else { $COLS_FALLBACK }
        let spare = ($sz.rows? | default 24) - 4
        # The list keeps the unfiltered height, so the preview never jumps while typing.
        let list_h = [([($all | length) $LIST_MIN] | math max) ([($spare - 3) $LIST_MIN] | math max)] | math min
        # Preview height: what the longest message needs (over the WHOLE set, so
        # filtering never moves it), capped by PV_MAX and by what is left.
        let want_pv = $all | each {|c| preview-lines $c.text ($cols - 4) $PV_MAX | length } | append 1 | math max
        let pv_h = [$PV_MAX $want_pv ([($spare - $list_h) 1] | math max)] | math min

        let view = $all | where {|c| matches $c $q }
        $sel = [0 ([$sel (($view | length) - 1)] | math min)] | math max
        if $sel < $off { $off = $sel }
        if $sel >= ($off + $list_h) { $off = $sel - $list_h + 1 }

        paint (frame $view $sel $q $off $list_h $pv_h $cols) (2 + ($q | str length))

        let a = action (input listen --types [key])
        if $a == "cancel" { break }
        if $a == "accept" { $out = ($view | get -o $sel | get -o rec); break }
        if $a == "up" { $sel = [0 ($sel - 1)] | math max }
        if $a == "down" { $sel = [($sel + 1) (($view | length) - 1)] | math min }
        if $a == "back" { $q = ($q | str substring 0..<-1); $sel = 0; $off = 0 }
        if $a == "clear" { $q = ""; $sel = 0; $off = 0 }
        if ($a | str starts-with "type:") { $q = $q + ($a | str substring 5..); $sel = 0; $off = 0 }
    }

    wipe
    $out
}
