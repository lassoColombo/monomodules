# `core/markdown.nu` — a stored message, laid out for something that cannot
# render markdown.
#
# TWO READERS, WHICH IS WHY THIS SUITE IS ITS OWN. These assertions lived in
# `tests/sketchybar.nu` while the bar's drawer was the only caller; the picker's
# preview is the second (step 8, D58), and neither owns the flattener now.
#
# Nothing is installed and nothing runs: it is a leaf that imports nothing and
# takes a string, a width and a line budget.
#
# THE GLYPHS ARE ASSERTED ON PURPOSE. They are the whole of the vocabulary — one
# font, one colour, no ANSI — so a marker quietly changing is a display changing
# its mind about what a heading looks like, and that should not pass silently.

use ../core/markdown.nu
use assert.nu *

# `plain` returns ROWS — `{k, t}` — because what a row IS is what a display
# colours it by (D62). Most of what is asserted here is the text, so it is
# flattened at the call; the kinds get assertions of their own below.
def flat [md: string, width: int, budget: int]: nothing -> list<string> {
    markdown text (markdown plain-md $md $width $budget)
}

def rows [ls: list<string>]: nothing -> list<record> { $ls | each {|t| {k: "text", t: $t} } }

export def main [] {
    # ── what the markdown MEANT ───────────────────────────────────────────────
    # The parser knows a heading is a heading and how deep it is, that a list is
    # ordered, and which box is ticked. All of that used to be thrown away.
    let a = [
        (check "a heading is KNOWN to be one, and says so"
               (flat "## Done" 40 9) ["▊ Done"])
        (check "…and its DEPTH survives: one family, three weights"
               [(flat "# a" 40 9) (flat "## a" 40 9) (flat "### a" 40 9)]
               [["█ a"] ["▊ a"] ["▌ a"]])
        (check "…with anything deeper reading as the lightest, not as nothing"
               (flat "###### a" 40 9) ["▌ a"])
        (check "bold, code and links lose their syntax, not their words"
               (flat "a **b** `c` [d](http://e)" 40 9) ["a b c d"])
        (check "a bullet becomes a bullet, and the nested one CHANGES — indent alone is ambiguous once it wraps"
               (flat "- one\n  - two\n    - three" 40 9) ["• one" "  ◦ two" "    ▪ three"])
        (check "an ordered item keeps THE NUMBER THE AGENT TYPED, not its position"
               (flat "5. five\n6. six" 40 9) ["5. five" "6. six"])
        (check "a task list gets a box that is actually ticked"
               (flat "- [ ] a\n- [x] b" 40 9) ["☐ a" "☑ b"])
        (check "a quote is marked as one" (flat "> said" 40 9) ["│ said"])
        (check "a rule is a whole row spent on nothing, so it goes"
               (flat "a\n\n---\n\nb" 40 9) ["a" "" "b"])
    ]

    # ── code and tables: the two things that must not be reflowed ─────────────
    let b = [
        (check "a fence is a toggle, and what it wraps is INDENTED rather than guttered — a gutter would read as the quote's"
               (flat "```nu\nlet a = 1\n    deeper\n```" 40 9) ["  let a = 1" "      deeper"])
        (check "a table is padded into real columns, and the alignment row is obeyed, not shown"
               (flat "| a | bb |\n|---|---:|\n| c | d |" 40 9) ["a │ bb" "──┼───" "c │  d"])
        (check "…its header is RULED OFF, so it reads as a header rather than as data"
               (flat "| a | bb |\n|---|---:|\n| c | d |" 40 9 | get 1) "──┼───")
        (check "…and a header the agent left blank is a row of drawer spent on nothing, so it goes"
               (flat "| | |\n|---|---|\n| a | b |" 40 9) ["a │ b"])
    ]

    # ── the air between blocks ────────────────────────────────────────────────
    # Markdown needs a blank line between two blocks whether or not a reader
    # wants one there. On a drawer twelve rows tall that is a row of the message
    # lost, so the source's blanks are the default and typography overrules them.
    let c = [
        (check "a heading takes its air ABOVE and binds to the section under it"
               (flat "text\n\n## Head\n\nbody" 40 9) ["text" "" "▊ Head" "body"])
        (check "…and never above nothing" (flat "# Top\n\nbody" 40 9) ["█ Top" "body"])
        (check "a LOOSE list is a distinction HTML cares about; four things are four things"
               (flat "- one\n\n- two" 40 9) ["• one" "• two"])
        (check "a blank line the agent left between paragraphs is kept"
               (flat "a\n\nb" 40 9) ["a" "" "b"])
        (check "…and one it did not leave is not invented"
               (flat "lead in:\n- one" 40 9) ["lead in:" "• one"])
        (check "a blank INSIDE a list item stays empty rather than becoming a row of spaces"
               (flat "- said:\n\n  ```\n  x\n  ```" 40 9) ["• said:" "" "    x"])
    ]

    # ── reflowing and wrapping (D61) ──────────────────────────────────────────
    # A message's paragraphs are one source line each — 435 characters was the
    # longest measured — so one row per source line meant cutting every one of
    # them at the width and throwing the rest away.
    let d = [
        (check "a paragraph is REFLOWED — a source wrap is the editor's, not the agent's"
               (flat "one two\nthree four" 40 9) ["one two three four"])
        (check "…and then wrapped to the width it was given"
               (flat "one two three four" 9 9) ["one two" "three" "four"])
        (check "…with the continuation hung under the TEXT, not under the marker"
               (flat "- one two three four" 9 9) ["• one two" "  three" "  four"])
        (check "a word wider than the line is broken, because nothing else can be"
               (markdown wrap "supercalifragilistic" 8) ["supercal" "ifragili" "stic"])
        (check "a hard break is the agent's own line break and is kept"
               (flat "one  \ntwo" 40 9) ["one" "two"])
        (check "the budget is a HARD stop — a message is kilobytes and a drawer is twelve rows"
               (flat (1..60 | each {|i| $"para ($i)" } | str join "\n\n") 40 5 | length) 5)
        (check "a message that is only markup renders as nothing, not as an error"
               (flat "---" 40 9) [])
        (check "and an empty one is empty" (flat "" 40 9) [])
    ]

    # ── laid out to fit ───────────────────────────────────────────────────────
    # `plain` has already wrapped to this width, so the cut here is the belt
    # that catches a renderer which got the arithmetic wrong.
    let e = [
        (check "a line too wide for the rectangle is cut" (markdown text (markdown lay-out (rows ["one two three four"]) 9 5)) ["one two…"])
        (check "a block keeps its shape, indentation and all" (markdown text (markdown lay-out (rows ["    indented"]) 40 5)) ["    indented"])
        (check "two blank lines become one — an empty row is the scarcest thing here"
               (markdown text (markdown lay-out (rows ["a" "" "" "b"]) 40 5)) ["a" "" "b"])
        (check "a preview that was cut says so" (markdown lay-out (rows ["one" "two" "three"]) 40 2 | last | get t) "two…")
        (check "…even when the line it stopped on happened to fit" (markdown text (markdown lay-out (rows ["ab" "cd"]) 40 1)) ["ab…"])
        (check "cutting counts characters, not bytes" (markdown cut-to "é—ù" 2) "é…")
    ]

    summarise ($a ++ $b ++ $c ++ $d ++ $e) --title "markdown"
}
