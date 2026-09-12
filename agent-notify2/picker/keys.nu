# What a keypress means. PURE: an event and a view in, a view and an action out.
#
#   {view: {sel, query, top}, action: ""}         keep going
#   {view: …,                 action: "jump"}     act on view.sel
#   {view: …,                 action: "cancel"}   the human changed their mind
#
# THE KEYMAP IS SMALL ON PURPOSE. Arrows and their control twins, enter, esc,
# backspace, and one way to clear the filter. Everything else printable types
# into the filter. Home/End/PageUp/PageDown are not here because a fleet is a
# handful of agents and a filter reaches any of them faster than paging would.
#
# ANY UNPRINTABLE KEY WE DO NOT KNOW IS IGNORED rather than typed. An escape
# sequence arriving as `f5` or `insert` must not end up in the query, where it
# would silently filter the list down to nothing and look like a broken picker.
#
# A NON-KEY EVENT IS IGNORED TOO. The loop subscribes to keys alone today, but an
# event with no `code` must never reach `$ev.code` — that would throw inside the
# loop and take the picker down with it.

use rows.nu

# WHAT A MODIFIER IS SPELLED LIKE, and why this is not just `$name in $mods`.
#
# nushell 0.115 reports a held control key as the string `keymodifiers(control)`
# — a Debug format leaking into the record — where the documented value is
# `control`. So `"control" in $ev.modifiers` is false for every control key there
# is, and EVERY CTRL COMBINATION FALLS THROUGH TO THE PRINTABLE BRANCH: ctrl-u
# types a `u`, ctrl-c types a `c` instead of leaving. Found by running it, not by
# the suite — the synthetic events it builds were spelled the way the
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

def move [view: record, rows: list<record>, by: int]: nothing -> record {
    let n = $rows | length
    if $n == 0 { return $view }
    let at = rows index-of $rows $view
    let from = if $at < 0 { 0 } else { $at }
    mut to = $from + $by
    if $to < 0 { $to = 0 }
    if $to > ($n - 1) { $to = $n - 1 }
    $view | merge {sel: ($rows | get $to | get id)}
}

# A changed filter always returns to the top of the list. The alternative — try
# to keep the same agent selected — means the cursor lands somewhere unrelated as
# rows disappear underneath it; `settle` then re-anchors on whatever survives.
def typed [view: record, query: string]: nothing -> record {
    $view | merge {query: $query, sel: "", top: 0}
}

export def step [ev: record, view: record, rows: list<record>]: nothing -> record {
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
    if $ctrl and $code == "u" { return {view: (typed $view ""), action: ""} }
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
