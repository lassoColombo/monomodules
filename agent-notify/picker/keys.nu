# What a keypress means. PURE: an event and a view in, a view and an action out.
#
#   {view: {sel, query, top}, action: ""}         keep going
#   {view: …,                 action: "jump"}     act on view.sel
#   {view: …,                 action: "cancel"}   the human changed their mind
#
# THE KEYMAP IS SMALL ON PURPOSE. Arrows and their control twins, enter, esc,
# backspace, one way to clear the filter — and four that scroll THE PREVIEW,
# which is the one rectangle here that can hold more than it shows. Everything
# else printable types into the filter. Home/End/PageUp/PageDown are not here
# because a fleet is a handful of agents and a filter reaches any of them faster
# than paging would.
#
#   ctrl-j / ctrl-k   the message, one row
#   ctrl-d / ctrl-u   the message, half a pane
#   ctrl-w            clear the filter — it was ctrl-u until the pair above
#
# ANY UNPRINTABLE KEY WE DO NOT KNOW IS IGNORED rather than typed. An escape
# sequence arriving as `f5` or `insert` must not end up in the query, where it
# would silently filter the list down to nothing and look like a broken picker.
#
# A NON-KEY EVENT IS IGNORED TOO. The loop subscribes to keys alone today, but
# an event with no `code` must never reach `$ev.code` — that would throw inside
# the loop and take the picker down with it.

use rows.nu

# WHAT A MODIFIER IS SPELLED LIKE, and why this is not just `$name in $mods`.
#
# nushell 0.115 reports a held control key as the string `keymodifiers(control)`
# — a Debug format leaking into the record — where the documented value is
# `control`. So `"control" in $ev.modifiers` is false for every control key
# there is, and EVERY CTRL COMBINATION FALLS THROUGH TO THE PRINTABLE BRANCH:
# ctrl-u types a `u`, ctrl-c types a `c` instead of leaving. Found by running
# it, not by the suite — the synthetic events it builds were spelled the way the
# documentation says.
#
# Matching on CONTAINS rather than equals takes both spellings, so this keeps
# working when nushell stops shouting its internals. None of the modifier names
# is a substring of another, so there is nothing to collide with.
def held [mods: list<any>, name: string]: nothing -> bool {
    $mods | any {|m| ($m | into string | str lowercase) | str contains $name }
}

# Leaving. ctrl-g is skim's third abort and costs one line to keep for the
# fingers that learned it there.
def abort? [code: string, ctrl: bool]: nothing -> bool {
    ($code == "esc") or ($ctrl and ($code in ["c" "g"]))
}

# Moving the cursor RETURNS THE PREVIEW TO THE TOP, because the preview is a
# different agent's message now and the row you had reached in the last one
# means nothing in this one.
def move [view: record, rows: list<record>, by: int]: nothing -> record {
    let n = $rows | length
    if $n == 0 { return $view }
    let at = rows index-of $rows $view
    let from = if $at < 0 { 0 } else { $at }
    mut to = $from + $by
    if $to < 0 { $to = 0 }
    if $to > ($n - 1) { $to = $n - 1 }
    $view | merge {sel: ($rows | get $to | get id), pv_top: 0}
}

# A changed filter always returns to the top of the list. The alternative — try
# to keep the same agent selected — means the cursor lands somewhere unrelated
# as rows disappear underneath it; `keep-in-view` then re-anchors on whatever
# survives.
def typed [view: record, query: string]: nothing -> record {
    $view | merge {query: $query, sel: "", top: 0, pv_top: 0}
}

# THE PREVIEW SCROLLS AND THE LIST DOES NOT MOVE. `pv_top` is the message's
# first visible row; it is floored at zero here and NOT capped, because how far
# down a message goes is known only to the thing that rendered it. `preview of`
# corrects it and hands the corrected value back (D63).
def scroll [view: record, by: int]: nothing -> record {
    $view | merge {pv_top: ([0 (($view.pv_top? | default 0) + $by)] | math max)}
}

# `page` is the PREVIEW's height, and it is here for one reason: a half page is
# half of something, and the only thing that knows how tall the message pane is
# is the layout. It is passed in rather than read, because this file has never
# touched a terminal and is not going to start.
export def step [ev: record, view: record, rows: list<record>, page: int]: nothing -> record {
    let stay = {view: $view, action: ""}
    if (($ev.type? | default "") != "key") { return $stay }

    let code = $ev.code? | default ""
    let mods = $ev.modifiers? | default []
    let ctrl = held $mods "control"
    let alt = (held $mods "alt") or (held $mods "super")
    let query = $view.query? | default ""

    if (abort? $code $ctrl) { return {view: $view, action: "cancel"} }
    if $code == "enter" {
        if ($rows | is-empty) { return $stay }
        return {view: $view, action: "jump"}
    }
    if ($code == "down") or ($ctrl and $code == "n") { return {view: (move $view $rows 1), action: ""} }
    if ($code == "up") or ($ctrl and $code == "p") { return {view: (move $view $rows -1), action: ""} }
    # The message, a row at a time and half a pane at a time — vim's pair, and
    # the reason it can be vim's pair is that a terminal sends ctrl-j as LF and
    # ENTER AS CR. Probed on a real pty: 0x0a arrives as char `j` with control
    # held, 0x0d as `enter` with nothing held, so binding ctrl-j costs nothing.
    # A half page is at least one row, or a pane too short to halve would bind
    # two keys to doing nothing.
    let half = [1 ($page // 2)] | math max
    if $ctrl and $code == "j" { return {view: (scroll $view 1), action: ""} }
    if $ctrl and $code == "k" { return {view: (scroll $view -1), action: ""} }
    if $ctrl and $code == "d" { return {view: (scroll $view $half), action: ""} }
    if $ctrl and $code == "u" { return {view: (scroll $view (0 - $half)), action: ""} }
    # CLEARING THE FILTER MOVED HERE, off ctrl-u, when the preview learned to
    # scroll: ctrl-d/ctrl-u are one gesture and splitting them would be worse
    # than moving a binding nothing else wants. ctrl-w is readline's
    # neighbouring kill, and on a filter this short "kill a word" and "kill the
    # line" are the same keystroke anyway.
    if $ctrl and $code == "w" { return {view: (typed $view ""), action: ""} }
    if (not $ctrl) and (not $alt) and ($code == "backspace") {
        if ($query | is-empty) { return $stay }
        return {view: (typed $view ($query | str substring 0..<(($query | str length) - 1))), action: ""}
    }
    # Printable, and only printable — see the header.
    if (($ev.key_type? | default "") == "char") and (not $ctrl) and (not $alt) {
        return {view: (typed $view $"($query)($code)"), action: ""}
    }
    $stay
}
