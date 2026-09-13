# `core/markdown.nu` — a stored message, flattened into lines something can show.
#
# TWO READERS, WHICH IS WHY THIS SUITE IS ITS OWN. These assertions lived in
# `tests/sketchybar.nu` while the bar's drawer was the only caller; the picker's
# preview is the second (step 8, D58), and neither owns the flattener now.
#
# Nothing is installed and nothing runs: it is a leaf that imports nothing and
# takes a string, a width and a line budget.

use ../core/markdown.nu
use assert.nu *

export def main [] {
    # ── markdown in, plain lines out ─────────────────────────────────────────
    # The BLOCK structure is the only formatting that survives to a stack of
    # labels or a rectangle of terminal; everything inside a line is flattened.
    let a = [
        (check "a heading loses its hashes" (markdown plain "## Done") ["Done"])
        (check "bold, code and links lose their syntax, not their words"
               (markdown plain "a **b** `c` [d](http://e)") ["a b c d"])
        (check "a bullet becomes a bullet" (markdown plain "- one") ["• one"])
        (check "a rule is a whole row spent on nothing, so it goes" (markdown plain "a\n---\nb") ["a" "b"])
        (check "a fence is a toggle; what it wraps is code and is left alone"
               (markdown plain "```nu\nlet a = 1\n```") ["let a = 1"])
    ]

    # ── laid out to fit ──────────────────────────────────────────────────────
    # A drawer is 110 characters wide and a preview pane is whatever the
    # terminal gives it; folding a sentence onto a second row would spend a slot
    # saying nothing new.
    let b = [
        (check "a long line is CUT, never wrapped — one row per source line"
               (markdown lay-out ["one two three four"] 9 5) ["one two…"])
        (check "…so a block keeps its shape, indentation and all"
               (markdown lay-out ["    indented"] 40 5) ["    indented"])
        (check "two blank lines become one — an empty row is the scarcest thing here"
               (markdown lay-out ["a" "" "" "b"] 40 5) ["a" "" "b"])
        (check "a preview that was cut says so" (markdown lay-out ["one" "two" "three"] 40 2 | last) "two…")
        (check "…even when the line it stopped on happened to fit" (markdown lay-out ["ab" "cd"] 40 1) ["ab…"])
        (check "cutting counts characters, not bytes" (markdown cut-to "é—ù" 2) "é…")
    ]

    summarise ($a ++ $b) --title "markdown"
}
