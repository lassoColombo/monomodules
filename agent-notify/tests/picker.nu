# Step 6 — the picker: rows, the filter, the selection, the frame, and the keys.
#
# NO TERMINAL IS OPENED HERE, and nothing is installed. That is the whole reason
# `picker/` is shaped the way it is: three calls in `picker/mod.nu` touch the
# world and every other line is a pure function of data, so an interactive
# program can be asserted frame by frame with `check`.
#
# The locator comes from `tests/fake.nu` — three questions answered out of the
# record itself. It is to the picker what the fake DISPLAY is to dispatch: proof
# that the contract is answerable without the tool, on a machine with neither
# zellij nor tmux.
#
# THE PREVIEW IS ASSERTED HERE NOW, which it never could be before: it used to
# be a live pane dump and is the stored message since step 8 (D58), so it is a
# pure function like the rest and `picker/preview.nu` is tested like the rest.
#
# What is deliberately NOT here: `picker choose`. It is the loop, it blocks on a
# key, and it cannot be driven from a suite — which is exactly why it holds
# nothing but the three I/O calls and hands every decision to the files below.

use ../picker/rows.nu
use ../picker/layout.nu
use ../picker/preview.nu

# `preview of` returns ROWS — `{k, t}` — so a frame assertion has to hand
# `render` the same shape. `text` is the kind that is NOT painted, which is what
# keeps these assertions free of escape codes (§9b.2).
def say [ls: list<string>]: nothing -> list<record> { $ls | each {|t| {k: "text", t: $t} } }

# …and the other way, for assertions that are about the words rather than what
# kind of thing they are.
def said [seen: record]: nothing -> list<string> { $seen.rows | get t }

# COLOUR IS REAL BUT IT IS THE ONE THING A TEST SHOULD NOT FREEZE — it follows
# the terminal's theme, and a frame asserted line for line (D34) would otherwise
# become an escape-code diff. So a frame is compared with its colour taken off,
# which is what §9b.2 said the precedent was. The assertions that are ABOUT the
# colour reach for the raw frame on purpose, a little further down.
def bare [ls: list<string>]: nothing -> list<string> { $ls | each {|l| $l | ansi strip } }
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

# ON ITS OWN, not in `fleet`: twenty rows of message, so an offset can be read
# straight off the text a preview comes back with. It stays out of the shared
# fixture because the list assertions count what they can see, and a fifth agent
# would push the last of them off the bottom.
#
# A TIGHT LIST, because that is the shape that is exactly one row per line —
# paragraphs would each cost a blank as well (D61) and the arithmetic here would
# stop being readable.
def wordy []: nothing -> any {
    rows selected (rows build [{id: "eee", state: "working", name: "echo", fake: {where: "box/one"}
        message: (1..20 | each {|i| $"- line ($i)" } | str join "\n")}] (fake locator)) {sel: "eee"}
}

def built []: nothing -> list<record> { rows build (fleet) (fake locator) }

# `--ctrl` uses the spelling nushell ACTUALLY emits — `keymodifiers(control)`, a
# Debug format leaking into the record — because the documented `control` is
# what the first version of `keys.nu` matched on, and every control key
# therefore typed its own letter instead. `--ctrl-plain` is the documented
# spelling, so both are asserted and neither can quietly stop working.
def key [code: string, --ctrl, --ctrl-plain, --char]: nothing -> record {
    let mods = if $ctrl { ["keymodifiers(control)"] } else if $ctrl_plain { ["control"] } else { [] }
    { type: "key"
      key_type: (if ($char or $ctrl or $ctrl_plain) { "char" } else { "other" })
      code: $code
      modifiers: $mods }
}

export def main [] {
    # ── which agent comes first ───────────────────────────────────────────────
    # A fleet list has exactly one useful order: whoever needs you most. Idle
    # sorts LAST rather than being hidden — an agent you have finished with is
    # still one you may want to go back to.
    let a = [
        (check "most urgent first, and idle last — not hidden, just last"
               (built | get id) ["ddd" "bbb" "aaa" "ccc"])
        (check "every row carries its record, so a pick needs no second lookup"
               (built | first | get rec.name) "delta")
        (check "an empty session-store makes no rows at all" (rows build [] (fake locator)) [])
    ]

    # ── what the locator supplies ─────────────────────────────────────────────
    # The picker cannot know where an agent lives. It asks whatever claimed it,
    # and an agent nothing claims is still a row — just one with nowhere to go.
    let b = [
        (check "`place` comes from the locator that claimed the record"
               (built | where id == "bbb" | get 0.location-label) "box/two")
        (check "…and a record nothing claims has no place" (built | where id == "ddd" | get 0.location-label) "")
        (check "a claimed record carries the locator that claimed it"
               (built | where id == "bbb" | get 0.via | is-not-empty) true)
        (check "…and an unclaimed one carries null, which is how the caller knows"
               (built | where id == "ddd" | get 0.via) null)
        (check "a locator answers THREE questions — `screen` went with the pane preview"
               ((fake locator).fake | columns | sort) ["go" "info" "location-label" "owns"])
    ]

    # ── the preview: what the agent last SAID ─────────────────────────────────
    # Not what is on its terminal, which is what this used to dump (D58). A
    # message is markdown, so it goes through the same flattener the bar's
    # drawer uses — one rendering, one place to fix it.
    let sel_b = rows selected (built) {sel: "bbb"}
    let b2 = [
        (check "the preview is the message, with its markdown taken off"
               (said (preview of $sel_b 4 40)) ["▊ Ready" "shall I continue?"])
        (check "it is cut from the TOP — a message's first line is its point"
               (said (preview of $sel_b 1 40)) ["▊ Ready…"])
        (check "…and wrapped to the width of the pane"
               (said (preview of (rows selected (built) {sel: "aaa"}) 4 8)) ["compilin" "g the" "thing"])
        (check "AN AGENT WITH NO PANE STILL HAS A PREVIEW — which is the whole point"
               (said (preview of (rows selected (built) {sel: "ddd"}) 4 40)) ["stuck on auth"])
        (check "an agent that has said nothing says so, rather than showing a blank"
               (said (preview of (rows selected (built) {sel: "ccc"}) 4 40)) ["—"])
        (check "…and each row carries WHAT IT IS, because that is what the frame colours by"
               (preview of $sel_b 4 40 | get rows.k) ["head" "text"])
        (check "no room is no preview, not an error"
               [(preview of $sel_b 0 40 | get rows) (preview of $sel_b 4 0 | get rows)] [[] []])
        (check "and an empty list previews nothing at all" (preview of null 4 40 | get rows) [])
    ]

    # ── scrolling the preview (D63) ───────────────────────────────────────────
    # A message is the one thing on this screen that holds more than it shows,
    # and the offset is CORRECTED HERE rather than by the keys: only the render
    # knows where a message ends, because `plain` is given a budget and stops
    # (D61). `at` coming back is what stops ctrl-d running up a number that then
    # has to be undone before the view moves again.
    let long = wordy
    let b3 = [
        (check "with no offset a preview starts at the first line"
               (said (preview of $long 4 40)) ["• line 1" "• line 2" "• line 3" "• line 4…"])
        (check "an offset moves the window down the message, not the list"
               (said (preview of $long 4 40 6)) ["• line 7" "• line 8" "• line 9" "• line 10…"])
        (check "…and the offset it actually used comes back with the rows"
               (preview of $long 4 40 6 | get at) 6)
        (check "SCROLLING STOPS AT THE LAST PAGE rather than off the end of it"
               (preview of $long 4 40 999 | get at) 16)
        (check "…and that last page is full, not one line stranded at the top"
               (said (preview of $long 4 40 999)) ["• line 17" "• line 18" "• line 19" "• line 20"])
        (check "a message that fits shows all of it however far you scroll"
               [(preview of $sel_b 8 40 99 | get at) (said (preview of $sel_b 8 40 99))]
               [0 ["▊ Ready" "shall I continue?"]])
        (check "a negative offset is the top, not an error"
               (preview of $long 4 40 -5 | get at) 0)
        (check "the end is only KNOWN when it is reached, so an offset inside the message is taken as given"
               (preview of $long 4 40 2 | get at) 2)
    ]

    # ── what to call an agent ─────────────────────────────────────────────────
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

    # ── the filter ────────────────────────────────────────────────────────────
    # Substring, case-insensitive, and nothing cleverer: predictable beats
    # ranked when the list is a handful of rows.
    let d = [
        (check "an empty query is everything" (rows filter (built) "" | length) 4)
        (check "a substring of the name narrows it" (rows filter (built) "brav" | get id) ["bbb"])
        (check "…and case does not matter" (rows filter (built) "BRAV" | get id) ["bbb"])
        (check "a state is a filter too, which is how you ask 'who is stuck'"
               (rows filter (built) "needs" | get id) ["ddd"])
        (check "so is where it lives" (rows filter (built) "box/one" | get id) ["aaa" "ccc"])
        (check "BUT NOT SOMETHING IT SAID — the filter can only match what you can see"
               (rows filter (built) "stuck on auth") [])
        (check "…which is what stops a two-letter query matching kilobytes of old prose"
               (rows filter (built) "auth") [])
        (check "matching nothing is an empty list, not an error"
               (rows filter (built) "zzzz") [])
    ]

    # ── THE SELECTION IS AN ID, NEVER AN INDEX ────────────────────────────────
    # The headline, and the reason `keep-in-view` exists. The store is re-read
    # every frame, so an agent changing state re-sorts the list WHILE YOU LOOK
    # AT IT.
    # An index would leave the cursor pointing at whoever slid into that slot.
    let before = built
    let after = rows build (fleet | each {|r|
        if $r.id == "aaa" { $r | merge {state: "needs-attention"} } else { $r }
    }) (fake locator)
    let held = rows keep-in-view {sel: "aaa", query: "", top: 0} $after 10
    let e = [
        (check "the agent was third before it changed state" (rows index-of $before {sel: "aaa"}) 2)
        (check "…and second after, because the list re-sorted under it"
               (rows index-of $after {sel: "aaa"}) 1)
        (check "THE SELECTION FOLLOWED THE AGENT, not the slot it used to be in"
               $held.sel "aaa")
        (check "an index would have kept slot 2 — which is now A DIFFERENT AGENT"
               ($after | get 2 | get id) "bbb")
        (check "a selection that has gone falls to the top rather than erroring"
               (rows keep-in-view {sel: "vanished", query: "", top: 0} $after 10 | get sel) "ddd")
        (check "…and an empty list selects nothing at all"
               (rows keep-in-view {sel: "aaa", query: "", top: 3} [] 10 | select sel top) {sel: "", top: 0})
        (check "`selected` hands back the whole row" (rows selected $after {sel: "bbb"} | get name) "bravo")
        (check "…and null when there is no such row" (rows selected $after {sel: "gone"}) null)
    ]

    # ── scrolling ─────────────────────────────────────────────────────────────
    # `top` is the first visible row and moves only far enough to keep the
    # selection on screen.
    let many = rows build (0..7 | each {|i| {id: $"id($i)", state: "idle", name: $"agent($i)"} }) {}
    let f = [
        (check "a selection below the window drags it down"
               (rows keep-in-view {sel: "id5", query: "", top: 0} $many 3 | get top) 3)
        (check "…and one above drags it back up"
               (rows keep-in-view {sel: "id1", query: "", top: 4} $many 3 | get top) 1)
        (check "a window already showing the selection does not move"
               (rows keep-in-view {sel: "id4", query: "", top: 3} $many 3 | get top) 3)
        (check "a window past the end of a shrunken list is pulled back"
               (rows keep-in-view {sel: "id0", query: "", top: 6} $many 3 | get top) 0)
        (check "a list shorter than the window starts at the top"
               (rows keep-in-view {sel: "id1", query: "", top: 0} ($many | first 2) 5 | get top) 0)
    ]

    # ── how the screen is divided ─────────────────────────────────────────────
    # The list takes what it needs up to half of what is left; the preview takes
    # the rest, because the rows say WHICH agents exist and the preview says what
    # the one under the cursor wants from you.
    let g = [
        (check "four agents in sixteen rows: four for the list, the rest to the preview"
               (layout measure {rows: 16, columns: 40} 4 | select list preview) {list: 4, preview: 7})
        (check "a crowd cannot take more than half"
               (layout measure {rows: 16, columns: 40} 20 | select list preview) {list: 5, preview: 6})
        (check "an empty list still gets a line to say so"
               (layout measure {rows: 16, columns: 40} 0 | select list preview) {list: 1, preview: 10})
        (check "a terminal with no room for a preview spends it all on the list"
               (layout measure {rows: 6, columns: 40} 4 | select list preview) {list: 1, preview: 0})
        (check "…and one with no room at all does not go negative"
               (layout measure {rows: 2, columns: 40} 4 | select list preview) {list: 1, preview: 0})
        (check "the width comes through for the rules and the clipping"
               (layout measure {rows: 16, columns: 40} 4 | get width) 40)
    ]

    # ── THE WHOLE FRAME, LINE FOR LINE ────────────────────────────────────────
    # The reason `render` returns strings and never prints (D34, after the bar's
    # `message` and zellij's `commands`): an entire picker screen is a value, so
    # it can simply be compared.
    let lay = layout measure {rows: 16, columns: 40} 4
    let narrow_lay = layout measure {rows: 16, columns: 12} 4
    let wide_lay = layout measure {rows: 16, columns: 120} 4
    let shot = bare (layout render (built) {sel: "bbb", query: "", top: 0} $lay (say ["screen line 1" "screen line 2"]))
    let h = [
        (check "the frame, exactly" $shot [
            "agents ❯"
            "────────────────────────────────────────"
            "  needs-attention  delta"
            "> awaiting         bravo    box/two"
            "  working          alpha    box/one"
            "  idle             charlie  box/one"
            "────────────────────────────────────────"
            "screen line 1"
            "screen line 2"
            "────────────────────────────────────────"
            "↑↓ move  ^j^k read  ^d^u page  enter jum"
        ])
        (check "the marker is on the selected row and nowhere else"
               ($shot | where {|l| $l | str starts-with "> " } | length) 1)
        (check "moving the selection moves the marker"
               (bare (layout render (built) {sel: "ccc", query: "", top: 0} $lay [])
                | where {|l| $l | str starts-with "> " } | get 0 | str contains "charlie") true)
        (check "what you type is the header, which is where the cursor sits"
               (bare (layout render (built) {sel: "bbb", query: "brav", top: 0} $lay []) | first) "agents ❯ brav")
        # ── the bars (§9b.2, D64) ─────────────────────────────────────────────
        # The chrome says two things the list cannot: what the whole fleet is
        # doing, and how far into a message you have read.
        (check "the top bar tallies the fleet, most urgent first and zeroes left out"
               (bare (layout render (built) {sel: "bbb", query: "", top: 0} $wide_lay []) | first
                | split row "\u{25cf}" | skip 1 | each {|p| $p | str trim } | str join " | ")
               "1 needs-attention | 1 awaiting | 1 working")
        (check "\u{2026}and idle is not one of them, because a zero is not news"
               (bare (layout render (built) {sel: "bbb", query: "", top: 0} $wide_lay []) | first
                | str contains "idle") false)
        (check "THE TALLY IS THE FIRST THING TO GO when a terminal cannot hold both halves"
               (bare (layout render (built) {sel: "bbb", query: "", top: 0} $narrow_lay []) | first) "agents \u{276f}")
        (check "how far down the message you have read, but only once you have"
               [ (bare (layout render (built) {sel: "bbb", query: "", top: 0, pv_top: 12} $wide_lay []) | last
                  | str ends-with "\u{25be} 12")
                 (bare (layout render (built) {sel: "bbb", query: "", top: 0, pv_top: 0} $wide_lay []) | last
                  | str contains "\u{25be}") ]
               [true false])
        (check "every binding is on the footer, so the only place to learn one is the screen"
               (bare (layout render (built) {sel: "bbb", query: "", top: 0} $wide_lay []) | last)
               "\u{2191}\u{2193} move  ^j^k read  ^d^u page  enter jump  esc cancel  ^w clear")
        (check "a state wears its own colour \u{2014} the three the bar and the pane titles use"
               (layout render (built) {sel: "zzz", query: "", top: 0} $lay [] | skip 2 | first 3
                | zip ["red" "magenta" "cyan"]
                | each {|p| ($p | first) | str starts-with $"  (ansi ($p | last))" })
               [true true true])
        (check "the caret lands just past what you typed" (layout caret {query: "brav"}) 14)
        (check "…and at the prompt when nothing is typed" (layout caret {}) 10)
    ]

    # ── the frame cannot be made to overflow ──────────────────────────────────
    # A line that wraps pushes every row below it down, and the next repaint
    # homes to the top and stays wrong. Autowrap is off (`tty.nu`) and these are
    # the belts.
    let nasty = bare (layout render (built) {sel: "bbb", query: "", top: 0} $narrow_lay (say [
        "a\u{7}b\u{1b}[31mc"          # a bell and an escape sequence
        "tab\there"
        "0123456789abcdefghij"
    ]))
    let short_lay = layout measure {rows: 8, columns: 40} 4
    let i = [
        (check "every line is clipped to the terminal's width"
               ($nasty | each {|l| $l | str length --grapheme-clusters } | math max) 12)
        (check "a bell and an escape sequence never reach the screen"
               ($nasty | where {|l| ($l | str contains "\u{7}") or ($l | str contains "\u{1b}") } | length) 0)
        (check "…and a tab, which one of would carry a line past the right edge"
               ($nasty | where {|l| $l | str contains "\t" } | length) 0)
        # ── colour (§9b.2, in part) ───────────────────────────────────────────
        # The preview's two kinds are painted and nothing else is. The order is
        # the assertion that matters: CLIPPED FIRST, COLOURED AFTER, so a line
        # is still cut by what a reader sees and an escape in an agent's own
        # text still cannot survive `clean`.
        (check "a heading in the preview is painted, and a paragraph is left to the terminal"
               (layout render (built) {sel: "bbb", query: "", top: 0} $lay
                    [{k: "head", t: "H"} {k: "text", t: "p"}]
                | skip 7 | first 2 | each {|l| $l | str contains "\u{1b}" })
               [true false])
        (check "…and the colour goes on AFTER the clip, so a painted row is still cut to the pane"
               (layout render (built) {sel: "bbb", query: "", top: 0} $narrow_lay
                    [{k: "head", t: "0123456789abcdefghij"}]
                | each {|l| $l | ansi strip | str length --grapheme-clusters } | math max)
               12)
        (check "the frame is never taller than the terminal"
               (layout render (built) {sel: "bbb", query: "", top: 0} $short_lay (say ["x" "y" "z"]) | length) 8)
        (check "a filter that matches nothing says THAT, so backspace is the obvious move"
               (bare (layout render [] {sel: "", query: "zz", top: 0} $lay []) | get 2) "  (nothing matches)")
        (check "…and an empty session-store says something else, because the fix is different"
               (bare (layout render [] {sel: "", query: "", top: 0} $lay []) | get 2) "  (no agents)")
    ]

    # ── the repaint ───────────────────────────────────────────────────────────
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

    # ── what a key means ──────────────────────────────────────────────────────
    let rs = built
    let at_b = {sel: "bbb", query: "", top: 0}
    # The PREVIEW's height, which is the only thing a half page can be half of.
    const PAGE = 8
    let k = [
        (check "down moves to the next agent" (keys step (key "down") $at_b $rs $PAGE | get view.sel) "aaa")
        (check "up moves to the previous one" (keys step (key "up") $at_b $rs $PAGE | get view.sel) "ddd")
        (check "ctrl-n is down" (keys step (key "n" --ctrl) $at_b $rs $PAGE | get view.sel) "aaa")
        (check "ctrl-p is up" (keys step (key "p" --ctrl) $at_b $rs $PAGE | get view.sel) "ddd")
        (check "the top of the list is the top of the list"
               (keys step (key "up") {sel: "ddd", query: "", top: 0} $rs $PAGE | get view.sel) "ddd")
        (check "…and so is the bottom"
               (keys step (key "down") {sel: "ccc", query: "", top: 0} $rs $PAGE | get view.sel) "ccc")
        # ── scrolling the message (D63) ───────────────────────────────────────
        # A terminal sends ctrl-j as LF and ENTER as CR, which is the whole
        # reason vim's pair is available here — probed on a real pty: 0x0a comes
        # back as char `j` with control held, 0x0d as `enter` with nothing.
        (check "ctrl-j reads one row further down the message"
               (keys step (key "j" --ctrl) $at_b $rs $PAGE | get view.pv_top) 1)
        (check "ctrl-k comes back up"
               (keys step (key "k" --ctrl) {sel: "bbb", query: "", top: 0, pv_top: 3} $rs $PAGE | get view.pv_top) 2)
        (check "…and stops at the top rather than going negative"
               (keys step (key "k" --ctrl) $at_b $rs $PAGE | get view.pv_top) 0)
        (check "ctrl-d is HALF the pane, so a taller terminal reads further per press"
               [ (keys step (key "d" --ctrl) $at_b $rs 8 | get view.pv_top)
                 (keys step (key "d" --ctrl) $at_b $rs 20 | get view.pv_top) ]
               [4 10])
        (check "ctrl-u is the same half, upwards"
               (keys step (key "u" --ctrl) {sel: "bbb", query: "", top: 0, pv_top: 9} $rs 8 | get view.pv_top) 5)
        (check "a pane too short to halve still moves a row, or the key would do nothing"
               (keys step (key "d" --ctrl) $at_b $rs 1 | get view.pv_top) 1)
        (check "SCROLLING MOVES NOTHING BUT THE MESSAGE — the list stays where it was"
               (keys step (key "d" --ctrl) $at_b $rs $PAGE | get view | select sel query top)
               {sel: "bbb", query: "", top: 0})
        (check "…and moving the cursor puts the next message back at ITS top"
               (keys step (key "down") {sel: "bbb", query: "", top: 0, pv_top: 12} $rs $PAGE | get view.pv_top) 0)
        (check "…as does typing, which changes the list underneath"
               (keys step (key "z" --char) {sel: "bbb", query: "", top: 0, pv_top: 12} $rs $PAGE | get view.pv_top) 0)
        (check "enter chooses" (keys step (key "enter") $at_b $rs $PAGE | get action) "jump")
        (check "…but not when there is nothing to choose"
               (keys step (key "enter") $at_b [] $PAGE | get action) "")
        (check "esc leaves" (keys step (key "esc") $at_b $rs $PAGE | get action) "cancel")
        (check "so does ctrl-c" (keys step (key "c" --ctrl) $at_b $rs $PAGE | get action) "cancel")
        (check "so does ctrl-g, for fingers that learned it in skim"
               (keys step (key "g" --ctrl) $at_b $rs $PAGE | get action) "cancel")
        (check "A CONTROL KEY IS A CONTROL KEY, whichever way nushell spells the modifier
           — matched wrong, ctrl-c types a 'c' instead of leaving"
               [ (keys step (key "c" --ctrl) $at_b $rs $PAGE | get action)
                 (keys step (key "c" --ctrl-plain) $at_b $rs $PAGE | get action) ]
               ["cancel" "cancel"])
        (check "…and neither spelling ever reaches the filter"
               [ (keys step (key "u" --ctrl) $at_b $rs $PAGE | get view.query)
                 (keys step (key "u" --ctrl-plain) $at_b $rs $PAGE | get view.query) ]
               ["" ""])
    ]

    let typing = keys step (key "z" --char) {sel: "bbb", query: "bra", top: 4} $rs $PAGE
    let l = [
        (check "a printable key types into the filter" $typing.view.query "braz")
        (check "…and returns to the top, because the list underneath just changed"
               ($typing.view | select sel top) {sel: "", top: 0})
        (check "backspace rubs one out"
               (keys step (key "backspace") {sel: "bbb", query: "brav", top: 0} $rs $PAGE | get view.query) "bra")
        (check "…and on an empty filter does nothing at all"
               (keys step (key "backspace") $at_b $rs $PAGE | get view) $at_b)
        (check "ctrl-w clears the filter — it was ctrl-u until the preview learned to scroll"
               (keys step (key "w" --ctrl) {sel: "bbb", query: "brav", top: 0} $rs $PAGE | get view.query) "")
        (check "A KEY WE DO NOT KNOW IS IGNORED, NOT TYPED — an f5 arriving as text
           would filter the list down to nothing and look like a broken picker"
               (keys step (key "f5") $at_b $rs $PAGE | get view) $at_b)
        (check "a ctrl combination we do not use is ignored too"
               (keys step (key "q" --ctrl --char) $at_b $rs $PAGE | get view) $at_b)
        (check "and an event that is not a key never reaches `$ev.code`"
               (keys step {type: "resize", width: 80, height: 24} $at_b $rs $PAGE | get view) $at_b)
    ]

    # ── the locator table ─────────────────────────────────────────────────────
    # One row per integration that can answer the three questions. The RECORD
    # picks its own — not the config file, which says what the store is pushed
    # to and nothing else (D47).
    let m = [
        (check "zellij ships as a locator" (locators integration-registry-names) ["zellij"])
        (check "a record naming a tool is claimed by it"
               (locators owner {fake: {where: "box/one"}} --table (fake locator) | is-not-empty) true)
        (check "…and one naming none is claimed by nobody"
               (locators owner {id: "x"} --table (fake locator)) null)
        (check "a real zellij record is claimed only when it says where it is, completely"
               [ (locators owner {zellij: {session: "home", pane_id: "3"}} | is-not-empty)
                 (locators owner {zellij: {session: "home"}}) ]
               [true null])
    ]

    summarise ($a ++ $b ++ $b2 ++ $b3 ++ $c ++ $d ++ $e ++ $f ++ $g ++ $h ++ $i ++ $j ++ $k ++ $l ++ $m) --title "picker"
}
