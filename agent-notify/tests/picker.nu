# Step 6 — the picker: rows, the filter, the selection, the frame, and the keys.
#
# NO TERMINAL IS OPENED HERE, and nothing is installed. That is the whole reason
# `picker/` is shaped the way it is: three calls in `picker/mod.nu` touch the
# world and every other line is a pure function of data, so an interactive
# program can be asserted frame by frame with `check`.
#
# The locator comes from `tests/fake.nu` — three questions answered out of the
# record itself. It is to the picker what the fake SURFACE is to dispatch: proof
# that the contract is answerable without the tool, on a machine with neither
# zellij nor tmux.
#
# THE PREVIEW IS ASSERTED HERE NOW, which it never could be before: it used to be
# a live pane dump and is the stored message since step 8 (D58), so it is a pure
# function like the rest and `picker/preview.nu` is tested like the rest.
#
# What is deliberately NOT here: `picker choose`. It is the loop, it blocks on a
# key, and it cannot be driven from a suite — which is exactly why it holds
# nothing but the three I/O calls and hands every decision to the files below.

use ../picker/rows.nu
use ../picker/frame.nu
use ../picker/preview.nu
use ../picker/keys.nu
use ../picker/tty.nu
use ../picker/locators.nu
use fake.nu
use assert.nu *

# Four agents, one per state, two of them sharing a place and one in no pane at
# all — so urgency, the tie-break and the unclaimed case are all in one fixture.
def fleet []: nothing -> list<record> {
    [ {id: "aaa", state: "working", name: "alpha", message: "compiling the thing"
       fake: {where: "box/one"}}
      {id: "bbb", state: "awaiting", name: "bravo", message: "## Ready\n\nshall I **continue**?"
       fake: {where: "box/two"}}
      {id: "ccc", state: "idle", name: "charlie", fake: {where: "box/one"}}
      {id: "ddd", state: "needs-attention", name: "delta", message: "stuck on auth"} ]
}

def built []: nothing -> list<record> { rows build (fleet) (fake locator) }

# `--ctrl` uses the spelling nushell ACTUALLY emits — `keymodifiers(control)`,
# a Debug format leaking into the record — because the documented `control` is
# what the first version of `keys.nu` matched on, and every control key therefore
# typed its own letter instead. `--ctrl-plain` is the documented spelling, so
# both are asserted and neither can quietly stop working.
def key [code: string, --ctrl, --ctrl-plain, --char]: nothing -> record {
    let mods = if $ctrl { ["keymodifiers(control)"] } else if $ctrl_plain { ["control"] } else { [] }
    { type: "key"
      key_type: (if ($char or $ctrl or $ctrl_plain) { "char" } else { "other" })
      code: $code
      modifiers: $mods }
}

export def main [] {
    # ── which agent comes first ──────────────────────────────────────────────
    # A fleet list has exactly one useful order: whoever needs you most. Idle
    # sorts LAST rather than being hidden — an agent you have finished with is
    # still one you may want to go back to.
    let a = [
        (check "most urgent first, and idle last — not hidden, just last"
               (built | get id) ["ddd" "bbb" "aaa" "ccc"])
        (check "every row carries its record, so a pick needs no second lookup"
               (built | first | get rec.name) "delta")
        (check "an empty store makes no rows at all" (rows build [] (fake locator)) [])
    ]

    # ── what the locator supplies ────────────────────────────────────────────
    # The picker cannot know where an agent lives. It asks whatever claimed it,
    # and an agent nothing claims is still a row — just one with nowhere to go.
    let b = [
        (check "`place` comes from the locator that claimed the record"
               (built | where id == "bbb" | get 0.place) "box/two")
        (check "…and a record nothing claims has no place" (built | where id == "ddd" | get 0.place) "")
        (check "a claimed record carries the locator that claimed it"
               (built | where id == "bbb" | get 0.via | is-not-empty) true)
        (check "…and an unclaimed one carries null, which is how the caller knows"
               (built | where id == "ddd" | get 0.via) null)
        (check "a locator answers THREE questions — `screen` went with the pane preview"
               ((fake locator).fake | columns | sort) ["claims" "go" "info" "place"])
    ]

    # ── the preview: what the agent last SAID ────────────────────────────────
    # Not what is on its terminal, which is what this used to dump (D58). A
    # message is markdown, so it goes through the same flattener the bar's
    # drawer uses — one rendering, one place to fix it.
    let sel_b = rows selected (built) {sel: "bbb"}
    let b2 = [
        (check "the preview is the message, with its markdown taken off"
               (preview of $sel_b 4 40) ["Ready" "" "shall I continue?"])
        (check "it is cut from the TOP — a message's first line is its point"
               (preview of $sel_b 1 40) ["Ready…"])
        (check "…and to the width of the pane"
               (preview of (rows selected (built) {sel: "aaa"}) 4 8) ["compili…"])
        (check "AN AGENT WITH NO PANE STILL HAS A PREVIEW — which is the whole point"
               (preview of (rows selected (built) {sel: "ddd"}) 4 40) ["stuck on auth"])
        (check "an agent that has said nothing says so, rather than showing a blank"
               (preview of (rows selected (built) {sel: "ccc"}) 4 40) ["—"])
        (check "no room is no preview, not an error"
               [(preview of $sel_b 0 40) (preview of $sel_b 4 0)] [[] []])
        (check "and an empty list previews nothing at all" (preview of null 4 40) [])
    ]

    # ── what to call an agent ────────────────────────────────────────────────
    let names = rows build [
        {id: "1", state: "idle", name: "said-so"}
        {id: "2", state: "idle", cwd: "/home/me/projects/thing"}
        {id: "0123456789abcdef", state: "idle"}
    ] {}
    let c = [
        (check "a name the agent gave itself wins" ($names | where id == "1" | get 0.name) "said-so")
        (check "…else the directory it is working in"
               ($names | where id == "2" | get 0.name) "thing")
        (check "…else enough of its id to tell it from the others"
               ($names | where id == "0123456789abcdef" | get 0.name) "01234567")
    ]

    # ── the filter ───────────────────────────────────────────────────────────
    # Substring, case-insensitive, and nothing cleverer: predictable beats
    # ranked when the list is a handful of rows.
    let d = [
        (check "an empty query is everything" (rows narrow (built) "" | length) 4)
        (check "a substring of the name narrows it" (rows narrow (built) "brav" | get id) ["bbb"])
        (check "…and case does not matter" (rows narrow (built) "BRAV" | get id) ["bbb"])
        (check "a state is a filter too, which is how you ask 'who is stuck'"
               (rows narrow (built) "needs" | get id) ["ddd"])
        (check "so is where it lives" (rows narrow (built) "box/one" | get id) ["aaa" "ccc"])
        (check "BUT NOT SOMETHING IT SAID — the filter can only match what you can see"
               (rows narrow (built) "stuck on auth") [])
        (check "…which is what stops a two-letter query matching kilobytes of old prose"
               (rows narrow (built) "auth") [])
        (check "matching nothing is an empty list, not an error"
               (rows narrow (built) "zzzz") [])
    ]

    # ── THE SELECTION IS AN ID, NEVER AN INDEX ───────────────────────────────
    # The headline, and the reason `settle` exists. The store is re-read every
    # frame, so an agent changing state re-sorts the list WHILE YOU LOOK AT IT.
    # An index would leave the cursor pointing at whoever slid into that slot.
    let before = built
    let after = rows build (fleet | each {|r|
        if $r.id == "aaa" { $r | merge {state: "needs-attention"} } else { $r }
    }) (fake locator)
    let held = rows settle {sel: "aaa", query: "", top: 0} $after 10
    let e = [
        (check "the agent was third before it changed state" (rows index-of $before {sel: "aaa"}) 2)
        (check "…and second after, because the list re-sorted under it"
               (rows index-of $after {sel: "aaa"}) 1)
        (check "THE SELECTION FOLLOWED THE AGENT, not the slot it used to be in"
               $held.sel "aaa")
        (check "an index would have kept slot 2 — which is now A DIFFERENT AGENT"
               ($after | get 2 | get id) "bbb")
        (check "a selection that has gone falls to the top rather than erroring"
               (rows settle {sel: "vanished", query: "", top: 0} $after 10 | get sel) "ddd")
        (check "…and an empty list selects nothing at all"
               (rows settle {sel: "aaa", query: "", top: 3} [] 10 | select sel top) {sel: "", top: 0})
        (check "`selected` hands back the whole row" (rows selected $after {sel: "bbb"} | get name) "bravo")
        (check "…and null when there is no such row" (rows selected $after {sel: "gone"}) null)
    ]

    # ── scrolling ────────────────────────────────────────────────────────────
    # `top` is the first visible row and moves only far enough to keep the
    # selection on screen.
    let many = rows build (0..7 | each {|i| {id: $"id($i)", state: "idle", name: $"agent($i)"} }) {}
    let f = [
        (check "a selection below the window drags it down"
               (rows settle {sel: "id5", query: "", top: 0} $many 3 | get top) 3)
        (check "…and one above drags it back up"
               (rows settle {sel: "id1", query: "", top: 4} $many 3 | get top) 1)
        (check "a window already showing the selection does not move"
               (rows settle {sel: "id4", query: "", top: 3} $many 3 | get top) 3)
        (check "a window past the end of a shrunken list is pulled back"
               (rows settle {sel: "id0", query: "", top: 6} $many 3 | get top) 0)
        (check "a list shorter than the window starts at the top"
               (rows settle {sel: "id1", query: "", top: 0} ($many | first 2) 5 | get top) 0)
    ]

    # ── how the screen is divided ────────────────────────────────────────────
    # The list takes what it needs up to half of what is left; the preview takes
    # the rest, because the rows say WHICH agents exist and the preview says what
    # the one under the cursor wants from you.
    let g = [
        (check "four agents in sixteen rows: four for the list, the rest to the preview"
               (frame layout {rows: 16, columns: 40} 4 | select list preview) {list: 4, preview: 7})
        (check "a crowd cannot take more than half"
               (frame layout {rows: 16, columns: 40} 20 | select list preview) {list: 5, preview: 6})
        (check "an empty list still gets a line to say so"
               (frame layout {rows: 16, columns: 40} 0 | select list preview) {list: 1, preview: 10})
        (check "a terminal with no room for a preview spends it all on the list"
               (frame layout {rows: 6, columns: 40} 4 | select list preview) {list: 1, preview: 0})
        (check "…and one with no room at all does not go negative"
               (frame layout {rows: 2, columns: 40} 4 | select list preview) {list: 1, preview: 0})
        (check "the width comes through for the rules and the clipping"
               (frame layout {rows: 16, columns: 40} 4 | get width) 40)
    ]

    # ── THE WHOLE FRAME, LINE FOR LINE ───────────────────────────────────────
    # The reason `render` returns strings and never prints (D34, after the bar's
    # `message` and zellij's `commands`): an entire picker screen is a value, so
    # it can simply be compared.
    let lay = frame layout {rows: 16, columns: 40} 4
    let shot = frame render (built) {sel: "bbb", query: "", top: 0} $lay ["screen line 1" "screen line 2"]
    let h = [
        (check "the frame, exactly" $shot [
            "agents"
            "────────────────────────────────────────"
            "  needs-attention  delta"
            "> awaiting         bravo    box/two"
            "  working          alpha    box/one"
            "  idle             charlie  box/one"
            "────────────────────────────────────────"
            "screen line 1"
            "screen line 2"
            "────────────────────────────────────────"
            "↑↓ move · enter jump · esc cancel · type"
        ])
        (check "the marker is on the selected row and nowhere else"
               ($shot | where {|l| $l | str starts-with "> " } | length) 1)
        (check "moving the selection moves the marker"
               (frame render (built) {sel: "ccc", query: "", top: 0} $lay []
                | where {|l| $l | str starts-with "> " } | get 0 | str contains "charlie") true)
        (check "what you type is the header, which is where the cursor sits"
               (frame render (built) {sel: "bbb", query: "brav", top: 0} $lay [] | first) "agents  brav")
        (check "the caret lands just past what you typed" (frame caret {query: "brav"}) 13)
        (check "…and at the prompt when nothing is typed" (frame caret {}) 9)
    ]

    # ── the frame cannot be made to overflow ─────────────────────────────────
    # A line that wraps pushes every row below it down, and the next repaint
    # homes to the top and stays wrong. Autowrap is off (`tty.nu`) and these are
    # the belts.
    let narrow_lay = frame layout {rows: 16, columns: 12} 4
    let nasty = frame render (built) {sel: "bbb", query: "", top: 0} $narrow_lay [
        "a\u{7}b\u{1b}[31mc"          # a bell and an escape sequence
        "tab\there"
        "0123456789abcdefghij"
    ]
    let short_lay = frame layout {rows: 8, columns: 40} 4
    let i = [
        (check "every line is clipped to the terminal's width"
               ($nasty | each {|l| $l | str length --grapheme-clusters } | math max) 12)
        (check "a bell and an escape sequence never reach the screen"
               ($nasty | where {|l| ($l | str contains "\u{7}") or ($l | str contains "\u{1b}") } | length) 0)
        (check "…and a tab, which one of would carry a line past the right edge"
               ($nasty | where {|l| $l | str contains "\t" } | length) 0)
        (check "the frame is never taller than the terminal"
               (frame render (built) {sel: "bbb", query: "", top: 0} $short_lay ["x" "y" "z"] | length) 8)
        (check "a filter that matches nothing says THAT, so backspace is the obvious move"
               (frame render [] {sel: "", query: "zz", top: 0} $lay [] | get 2) "  (nothing matches)")
        (check "…and an empty store says something else, because the fix is different"
               (frame render [] {sel: "", query: "", top: 0} $lay [] | get 2) "  (no agents)")
    ]

    # ── the repaint ──────────────────────────────────────────────────────────
    # Nothing is ever erased in advance: the cursor homes, each line is written
    # over what was there and finished with EL, and one ED takes away the rows a
    # shorter frame left behind. So there is no blank moment to see.
    let painted = tty paint ["one" "two"] 11
    let j = [
        (check "the repaint homes rather than clearing" ($painted | str starts-with "\u{1b}[H") true)
        (check "it never clears the screen up front"
               ($painted | str contains "\u{1b}[H\u{1b}[J") false)
        (check "every line erases its own tail" ($painted | str contains "one\u{1b}[K\r\ntwo\u{1b}[K") true)
        (check "and the last one erases everything below it"
               ($painted | str contains "\u{1b}[K\u{1b}[J") true)
        (check "the cursor ends where the caret says, which makes it the filter's"
               ($painted | str ends-with "\u{1b}[1;11H") true)
        (check "autowrap goes off, so a long line is clipped by the terminal"
               (tty setup) "\u{1b}[?7l")
        (check "…and is handed back, along with a cursor we never hid"
               (tty restore | str starts-with "\u{1b}[?7h") true)
    ]

    # ── what a key means ─────────────────────────────────────────────────────
    let rs = built
    let at_b = {sel: "bbb", query: "", top: 0}
    let k = [
        (check "down moves to the next agent" (keys step (key "down") $at_b $rs | get view.sel) "aaa")
        (check "up moves to the previous one" (keys step (key "up") $at_b $rs | get view.sel) "ddd")
        (check "ctrl-n is down" (keys step (key "n" --ctrl) $at_b $rs | get view.sel) "aaa")
        (check "ctrl-p is up" (keys step (key "p" --ctrl) $at_b $rs | get view.sel) "ddd")
        (check "the top of the list is the top of the list"
               (keys step (key "up") {sel: "ddd", query: "", top: 0} $rs | get view.sel) "ddd")
        (check "…and so is the bottom"
               (keys step (key "down") {sel: "ccc", query: "", top: 0} $rs | get view.sel) "ccc")
        (check "enter chooses" (keys step (key "enter") $at_b $rs | get action) "jump")
        (check "…but not when there is nothing to choose"
               (keys step (key "enter") $at_b [] | get action) "")
        (check "esc leaves" (keys step (key "esc") $at_b $rs | get action) "cancel")
        (check "so does ctrl-c" (keys step (key "c" --ctrl) $at_b $rs | get action) "cancel")
        (check "so does ctrl-g, for fingers that learned it in skim"
               (keys step (key "g" --ctrl) $at_b $rs | get action) "cancel")
        (check "A CONTROL KEY IS A CONTROL KEY, whichever way nushell spells the modifier
           — matched wrong, ctrl-c types a 'c' instead of leaving"
               [ (keys step (key "c" --ctrl) $at_b $rs | get action)
                 (keys step (key "c" --ctrl-plain) $at_b $rs | get action) ]
               ["cancel" "cancel"])
        (check "…and neither spelling ever reaches the filter"
               [ (keys step (key "u" --ctrl) $at_b $rs | get view.query)
                 (keys step (key "u" --ctrl-plain) $at_b $rs | get view.query) ]
               ["" ""])
    ]

    let typing = keys step (key "z" --char) {sel: "bbb", query: "bra", top: 4} $rs
    let l = [
        (check "a printable key types into the filter" $typing.view.query "braz")
        (check "…and returns to the top, because the list underneath just changed"
               ($typing.view | select sel top) {sel: "", top: 0})
        (check "backspace rubs one out"
               (keys step (key "backspace") {sel: "bbb", query: "brav", top: 0} $rs | get view.query) "bra")
        (check "…and on an empty filter does nothing at all"
               (keys step (key "backspace") $at_b $rs | get view) $at_b)
        (check "ctrl-u clears the filter"
               (keys step (key "u" --ctrl) {sel: "bbb", query: "brav", top: 0} $rs | get view.query) "")
        (check "A KEY WE DO NOT KNOW IS IGNORED, NOT TYPED — an f5 arriving as text
           would filter the list down to nothing and look like a broken picker"
               (keys step (key "f5") $at_b $rs | get view) $at_b)
        (check "a ctrl combination we do not use is ignored too"
               (keys step (key "q" --ctrl --char) $at_b $rs | get view) $at_b)
        (check "and an event that is not a key never reaches `$ev.code`"
               (keys step {type: "resize", width: 80, height: 24} $at_b $rs | get view) $at_b)
    ]

    # ── the locator table ────────────────────────────────────────────────────
    # One row per integration that can answer the three questions. The RECORD
    # picks its own — not the config file, which says what the store is pushed to
    # and nothing else (D47).
    let m = [
        (check "zellij ships as a locator" (locators known) ["zellij"])
        (check "a record naming a tool is claimed by it"
               (locators owner {fake: {where: "box/one"}} --table (fake locator) | is-not-empty) true)
        (check "…and one naming none is claimed by nobody"
               (locators owner {id: "x"} --table (fake locator)) null)
        (check "a real zellij record is claimed only when it says where it is, completely"
               [ (locators owner {zellij: {session: "home", pane_id: "3"}} | is-not-empty)
                 (locators owner {zellij: {session: "home"}}) ]
               [true null])
    ]

    summarise ($a ++ $b ++ $b2 ++ $c ++ $d ++ $e ++ $f ++ $g ++ $h ++ $i ++ $j ++ $k ++ $l ++ $m) --title "picker"
}
