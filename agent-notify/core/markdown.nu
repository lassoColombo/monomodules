# Markdown in, display rows out.
#
# A LEAF, AND SHARED. It was `integrations/sketchybar/text.nu` while the bar was
# the only thing that had to show an agent's message; the picker's preview is
# the second (step 8), and a flattener that two displays read is not the bar's.
# It imports nothing and touches nothing, so anything may take it — including
# the hot half, though nothing there needs it yet.
#
# WHAT IT IS FOR, in both callers: a stored message is markdown, and the places
# it has to appear are not. A SketchyBar label takes ONE font and ONE colour and
# holds ONE line; a picker preview is a fixed rectangle of a terminal with no
# renderer behind it. Neither can show a heading as a heading. So: parse, then
# lay the blocks out in characters, which is the only ink either display has.
#
# ── WHY IT IS A PARSER NOW, AND NOT SEVEN REGEXES (D60) ───────────────────────
# `from md --verbose` is a BUILT-IN — nushell 0.115 — so the "why not pandoc"
# argument that shaped the first version does not reach it: there is no
# subprocess and no ~30ms. It returns the real document, and three things fall
# out of that which regexes could not give:
#
#   A HEADING IS KNOWN TO BE ONE, AND KNOWS ITS DEPTH. `## Done` used to lose its
#   hashes and land in the drawer as prose.
#
#   A LIST KNOWS ITS DEPTH, ITS ORDER AND ITS CHECKBOX. `level`, `ordered` and
#   `checked` are attributes on the node; `- [x] done` is `☑ done`.
#
#   A TABLE HAS CELLS. Rows arrive as `table_cell` with `row`, `column` and an
#   alignment row, so a table is PADDED INTO COLUMNS instead of reaching the
#   screen as the pipes the agent typed.
#
# ── AND WHY IT WRAPS, WHICH REVERSES THE RULE ABOVE IT (D61) ──────────────────
# The first version said NOTHING IS WRAPPED: a drawer is 110 characters wide, a
# fold eats one of twelve slots, and two rows read as two thoughts. That was
# reasoned about markdown a person hard-wraps at 80. It is not what an agent
# writes. Measured on the real store, a message's paragraphs are ONE SOURCE LINE
# EACH — 435 characters was the longest — so "one row per source line" meant
# CUTTING EVERY PARAGRAPH AT 110 and throwing the other 325 away. A drawer full
# of amputated first-halves is not a preview of anything.
#
# So a paragraph is REFLOWED — the soft wraps an editor put in are not the
# agent's line breaks — and then wrapped to the width it is actually given. What
# must NOT be reflowed is anything whose columns mean something: a code block is
# cut, never folded, and a table is padded to fit. Fewer rows reach the screen
# and all of them are whole sentences.
#
# ── AND WHY IT TAKES A LINE BUDGET ────────────────────────────────────────────
# Parsing is cheap and WRAPPING KILOBYTES IS NOT, so the number of rows the
# caller can actually show is an argument. A drawer is twelve rows; a 3.5KB
# message is seventy blocks; sixty of them can never be seen. With the budget
# threaded through, the render stops when the rectangle is full — which is what
# keeps this the same ~1ms the line-based version cost, rather than ten times it.
#
# NOTHING HERE KNOWS ABOUT ITS CALLER. It is given a width and a line budget and
# returns rows — text, and what each row IS. Which colour that becomes, the item
# names, the shell and the escaping that shell needs all live next door, in
# `integrations/sketchybar/items.nu` and `picker/layout.nu`.

# ── measuring ─────────────────────────────────────────────────────────────────
# By CHARACTER, not by byte. Slicing a string at a byte offset can land inside a
# codepoint and turn an em dash into a replacement glyph — and a character is
# also what a label's width actually counts. `str length` and `str substring`
# both default to BYTES, so the flag is not optional anywhere in this file.

def width-of [s: string]: nothing -> int { $s | str length --grapheme-clusters }

export def cut-to [s: string, n: int]: nothing -> string {
    let cs = $s | split chars
    if ($cs | length) <= $n { return $s }
    (($cs | first ([0 ($n - 1)] | math max) | str join) | str trim --right) + "…"
}

# Same, but the ellipsis is a PROMISE rather than a consequence: a line that was
# dropped has to say so even when it happened to fit, or a truncated preview is
# indistinguishable from a complete one.
def mark [s: string, width: int]: nothing -> string {
    let cs = $s | split chars
    if ($cs | length) < $width { return ($s + "…") }
    (($cs | first ([0 ($width - 1)] | math max) | str join) | str trim --right) + "…"
}

def rep [s: string, n: int]: nothing -> string {
    if $n <= 0 { return "" }
    1..$n | each {|| $s } | str join
}

# ── the vocabulary a single font has ──────────────────────────────────────────
# Every one of these is a CHARACTER, because a character is all this file can
# spend: colour is per ROW and belongs to the display (D62), so anything finer
# than a row has to be said in the text itself. Emphasis and inline code are the
# two that cannot be — they are runs INSIDE a line — so they are not marked at
# all. Colour cannot rescue them either; they would need a font.
export const STYLE = {
    # ONE FAMILY, THREE WEIGHTS. A `#` and a `###` are different things, and a
    # single marker said so equally — which flattens a document into a run of
    # equally loud announcements. These are one block at full, three-quarter and
    # half width, so the hierarchy is legible before a word is read. All three
    # stay BARS: an eighth-width block was the obvious third step and it reads
    # as a thin rule, which is what `quote` already is.
    head: ["█ " "▊ " "▌ "]
    # By depth, and cycling. Indentation alone is ambiguous once a long item
    # wraps, because its continuation is indented too.
    bullet: ["• " "◦ " "▪ "]
    done: "☑ "
    todo: "☐ "
    quote: "│ "
    # CODE IS SET APART BY INDENT, NOT BY A GUTTER. A gutter would be a second
    # thin vertical beside the quote's and the two would read as one thing. An
    # indent says "set apart" on its own, and it shifts every line equally, so
    # the columns that make code readable survive it.
    code: "  "
    cell: " │ "   # between a table's columns
    rule: "─"     # and under its header, where that separator is crossed
    join: "┼"
}

# A hard break inside a paragraph, carried through the flattening as a character
# no agent can type. Both displays scrub control characters on the way out
# (`layout.nu` cleans them, `items.nu` quotes them), so a leak degrades to a
# space rather than to a broken line.
const BR = "\u{b}"

# Node types that OPEN A BLOCK. Everything else is inline and accumulates into a
# paragraph until a blank line or one of these ends it.
const BLOCKS = ["h1" "h2" "h3" "h4" "h5" "h6" "list" "blockquote" "code"
                "table_cell" "table_align" "Horizontal_rule" "html" "footnote"]

def strip-tags [s: string]: nothing -> string {
    $s | str replace --all --regex '<[^>]*>' '' | str trim
}

# A soft wrap in the SOURCE is not a line break in the MESSAGE — an editor put
# it there, not the agent — so it becomes a space and the display decides where
# the line ends.
def unfold [s: string]: nothing -> string { $s | str replace --all "\n" " " }

# ── inline: a run of nodes, flattened to one string ───────────────────────────
# Recursive, because `strong`, `emphasis`, `delete` and `link` wrap their text in
# children. Every one of them loses its syntax and keeps its words; a link keeps
# the words and drops the URL, which is never readable at this size.
def inline [nodes: list<any>]: nothing -> string {
    mut s = ""
    for n in $nodes {
        let a = $n.attrs? | default {}
        let v = $a | get -o value | default ""
        $s = $s + (match $n.type {
            "text" => (unfold $v)
            "code_inline" => (unfold $v)
            "math_inline" => (unfold $v)
            "break" => $BR
            "image" => ($a | get -o alt | default "")
            "footnoteref" => $"[($a | get -o label | default '')]"
            "html" => (strip-tags $v)
            _ => (inline ($n.children? | default []))
        })
    }
    $s
}

# ── grouping: a flat node list → blocks ───────────────────────────────────────
# THE PARSER EMITS NO PARAGRAPH NODE. A paragraph's inline nodes are siblings of
# every block around them, so what separates two paragraphs is a BLANK SOURCE
# LINE and the only evidence of one is the gap between a node's end line and the
# next node's start line. A gap of 1 is a soft wrap inside one sentence; 2 or
# more is a new thought.
#
# Each block keeps its own first and last source line for the same reason: it is
# what lets `stack` know where the agent left air.
#
# `budget` stops the walk. Every block is at least one row, so once there are
# more blocks than rows left there is nothing further to learn.
def group [nodes: list<any>, budget: int]: nothing -> list<record> {
    mut out = []
    mut para = []
    mut cells = []
    mut align = ""
    for n in $nodes {
        if ($out | length) > $budget { break }
        let is_block = $n.type in $BLOCKS
        # A table is a RUN of cells; anything that is not one ends it.
        if ($cells | is-not-empty) and ($n.type not-in ["table_cell" "table_align"]) {
            $out = $out ++ [(span {k: "table", cells: $cells, align: $align} $cells)]
            $cells = []
            $align = ""
        }
        if $is_block and ($para | is-not-empty) {
            $out = $out ++ [(span {k: "para", nodes: $para} $para)]
            $para = []
        }
        if $is_block {
            let a = $n.attrs? | default {}
            match $n.type {
                "table_cell" => { $cells = $cells ++ [$n] }
                "table_align" => { $align = ($a | get -o align | default "") }
                # A rule renders as a full-width run of dashes — a whole row
                # spent on nothing — and a blank line already separates what it
                # was separating.
                "Horizontal_rule" => { }
                "code" => { $out = $out ++ [(span {k: "code", text: ($a | get -o value | default "")} [$n])] }
                "html" => { $out = $out ++ [(span {k: "html", text: (unfold (strip-tags ($a | get -o value | default "")))} [$n])] }
                "list" => { $out = $out ++ [(span {k: "item", node: $n} [$n])] }
                "blockquote" => { $out = $out ++ [(span {k: "quote", node: $n} [$n])] }
                "footnote" => { $out = $out ++ [(span {k: "note", node: $n} [$n])] }
                _ => { $out = $out ++ [(span {k: "head", node: $n} [$n])] }
            }
        } else {
            if ($para | is-not-empty) and ((($n.position.start.line) - ($para | last | get position.end.line)) >= 2) {
                $out = $out ++ [(span {k: "para", nodes: $para} $para)]
                $para = []
            }
            $para = $para ++ [$n]
        }
    }
    if ($cells | is-not-empty) { $out = $out ++ [(span {k: "table", cells: $cells, align: $align} $cells)] }
    if ($para | is-not-empty) { $out = $out ++ [(span {k: "para", nodes: $para} $para)] }
    $out
}

# The source lines a block came from, stamped onto it.
def span [b: record, nodes: list<any>]: nothing -> record {
    $b | merge {s: ($nodes | first | get position.start.line)
                e: ($nodes | last | get position.end.line)}
}

# ── wrapping ──────────────────────────────────────────────────────────────────
# BY THE ROW, NOT BY THE WORD. The obvious greedy fill costs one loop turn per
# word and a message is hundreds of them; taking `width + 1` characters and
# cutting back to the last space costs one turn per ROW, which is the number the
# caller is actually going to show. Measured at 3× on a real paragraph, same
# output character for character.
export def wrap [s: string, width: int]: nothing -> list<string> {
    if $width < 2 { return [$s] }
    mut out = []
    mut rest = $s
    while (width-of $rest) > $width {
        let head = $rest | str substring --grapheme-clusters 0..<($width + 1)
        let at = $head | str index-of --grapheme-clusters --end " "
        if $at < 1 {
            # One word wider than the line. Nothing can be done but break it.
            $out = $out ++ [($rest | str substring --grapheme-clusters 0..<$width)]
            $rest = $rest | str substring --grapheme-clusters $width..
        } else {
            $out = $out ++ [($head | str substring --grapheme-clusters 0..<$at)]
            $rest = $rest | str substring --grapheme-clusters ($at + 1)..
        }
    }
    if ($rest | is-not-empty) { $out = $out ++ [$rest] }
    $out
}

# Prose, wrapped to what is left of the rectangle. The text is CUT BEFORE IT IS
# WRAPPED: a paragraph longer than the rows remaining cannot be seen, and
# wrapping what will not be shown is most of what this used to cost.
def flow [text: string, width: int, budget: int]: nothing -> list<string> {
    let room = ($width + 1) * ([$budget 1] | math max)
    let t = if (($text | str length) > $room) {
        $text | split chars | first $room | str join
    } else { $text }
    $t | split row $BR | each {|seg| wrap ($seg | str trim) $width } | flatten | first $budget
}

# ── rows, and what each one IS ────────────────────────────────────────────────
# A row is `{k, t}`: the text, and the kind of thing it is.
#
# WHY THE KIND LEAVES THIS FILE. Colour is the one piece of formatting neither
# display can take from a string. SketchyBar has no ANSI at all — a row is an
# item and an item has ONE `label.color`, set over the wire — and the picker
# strips escapes out of every frame on purpose, because the text in them is
# agent-authored. So the two displays cannot share a coloured string, and this
# file must not try to write one: it says WHAT the row is, and each display
# paints it with the mechanism it actually has (D62).
#
# THREE KINDS, WHICH IS ALL THAT EARNS ONE. `head` and `code` are the two things
# a marker alone leaves ambiguous at a glance; everything else is `text`. A
# quote has a gutter and a list has a bullet, and neither needs a colour to be
# read.
def tag [k: string, ls: list<string>]: nothing -> list<record> {
    $ls | each {|t| {k: $k, t: $t} }
}

# A block whose first row carries a marker and whose rest must line up under the
# TEXT, not under the marker. A blank row inside one is left EMPTY rather than
# indented: padding it would make a row of spaces, which is invisible on the
# screen and a lie in the suite.
def hang [rs: list<record>, pad: string]: nothing -> list<record> {
    $rs | enumerate | each {|e|
        if ($e.index == 0) or ($e.item.t | is-empty) { $e.item } else { $e.item | update t ($pad + $e.item.t) }
    }
}

# ── tables ────────────────────────────────────────────────────────────────────
# Real columns: every cell padded to the widest in its column and the alignment
# row obeyed, then squeezed proportionally if the whole row is wider than the
# rectangle. A cell is CUT rather than wrapped — a table whose rows are different
# heights has stopped being a table.
def render-table [b: record, width: int, style: record]: nothing -> list<string> {
    let cells = $b.cells | each {|c|
        {row: $c.attrs.row, col: $c.attrs.column, t: (inline ($c.children? | default []))}
    }
    if ($cells | is-empty) { return [] }
    let ncol = ($cells | get col | math max) + 1
    let aligns = $b.align | split row "," | each {|a|
        if ($a | str starts-with ":") and ($a | str ends-with ":") { "c"
        } else if ($a | str ends-with ":") { "r" } else { "l" }
    }
    let want = 0..<$ncol | each {|c|
        $cells | where col == $c | each {|x| width-of $x.t } | append 1 | math max
    }
    let gaps = (width-of $style.cell) * ($ncol - 1)
    let widths = if ((($want | math sum) + $gaps) <= $width) { $want } else {
        let room = [($width - $gaps) $ncol] | math max
        let total = $want | math sum
        $want | each {|w| [2 (($w * $room) // $total)] | math max }
    }
    # A row with nothing in any cell is a header the agent left blank — the
    # `| | |` that carries a table with no titles. It is a whole row of drawer
    # spent on nothing, so it goes the way the alignment line does.
    let kept = 0..(($cells | get row | math max))
        | where {|r| ($cells | where row == $r | any {|x| $x.t | is-not-empty }) }
    let rows = $kept | each {|r|
        0..<$ncol | each {|c|
            let w = $widths | get $c
            let t = $cells | where row == $r and col == $c | get -o 0.t | default ""
            let fit = if ((width-of $t) > $w) { cut-to $t $w } else { $t }
            $fit | fill --width $w --alignment ($aligns | get -o $c | default "l")
        } | str join $style.cell | str trim --right
    }
    # A table's first row is its HEADER — the alignment line beneath it in the
    # source is what makes it one — so it is ruled off rather than left to read
    # as one more row of data. The rule is DERIVED from the column separator
    # rather than written out, so its crossings stay lined up with it.
    if ($b.align | is-empty) or (($kept | first | default 1) != 0) { return $rows }
    let bar = $style.cell | str replace --all " " $style.rule | str replace --all "│" $style.join
    let across = $widths | each {|w| rep $style.rule $w } | str join $bar
    ([($rows | first)] ++ [$across] ++ ($rows | skip 1))
}

# ── blocks → rows ─────────────────────────────────────────────────────────────
def render-block [b: record, width: int, style: record, src: list<string>, budget: int]: nothing -> list<record> {
    match $b.k {
        "para" => (tag "text" (flow (inline $b.nodes) $width $budget))
        "html" => (tag "text" (flow $b.text $width $budget))
        "table" => (tag "text" (render-table $b $width $style | first $budget))
        # The one thing that must reach the screen untouched. Its indentation is
        # meaning, so it is cut at the edge rather than folded.
        "code" => {
            let room = $width - (width-of $style.code)
            tag "code" ($b.text | split row "\n" | first $budget | each {|l| ($style.code + (cut-to $l $room)) | str trim --right })
        }
        "head" => {
            let deep = ($b.node.attrs.level? | default 1) - 1
            let m = $style.head | get -o $deep | default ($style.head | last)
            # One line: a call does not continue across lines (plan.md §10).
            hang (tag "head" (flow ($m + (inline ($b.node.children? | default []))) $width $budget)) (rep " " (width-of $m))
        }
        # A marker goes on the first row and the kinds underneath are left
        # alone: a fenced block inside a list item is still code, and a quoted
        # heading is still a heading.
        "item" => {
            let lead = (rep "  " ($b.node.attrs | get -o level | default 0)) + (marker $b.node.attrs $b.s $src $style)
            let body = stack (group ($b.node.children? | default []) $budget) ($width - (width-of $lead)) $style $src $budget
            if ($body | is-empty) { return [] }
            hang (led $body $lead) (rep " " (width-of $lead))
        }
        "quote" => {
            stack (group ($b.node.children? | default []) $budget) ($width - (width-of $style.quote)) $style $src $budget
            | each {|r| $r | update t (($style.quote + $r.t) | str trim --right) }
        }
        "note" => {
            let lead = $"[($b.node.attrs.ident? | default '')] "
            let body = stack (group ($b.node.children? | default []) $budget) ($width - (width-of $lead)) $style $src $budget
            if ($body | is-empty) { return [] }
            hang (led $body $lead) (rep " " (width-of $lead))
        }
        _ => []
    }
}

# The marker, onto the first row of a block that has one.
def led [rs: list<record>, lead: string]: nothing -> list<record> {
    [($rs | first | update t ($lead + ($rs | first | get t)))] ++ ($rs | skip 1)
}

# What goes in front of a list item. A task list is the interesting one — the
# parser reports `checked`, so `- [x] done` can be a box that is actually
# ticked.
#
# AN ORDERED ITEM'S NUMBER IS READ BACK OUT OF THE SOURCE. The parser reports
# POSITION, not the number typed: a list written `5. 6. 7.` arrives as index 0,
# 1, 2 and would be renumbered from one. That is what a browser does and it is
# not what this module does anywhere else — the session-store keeps what the
# agent wrote (D14) — so the marker line is re-read and the digits taken off it.
def marker [a: record, line: int, src: list<string>, style: record]: nothing -> string {
    let checked = $a | get -o checked
    if $checked != null { return (if $checked { $style.done } else { $style.todo }) }
    let deep = $a | get -o level | default 0
    if not ($a | get -o ordered | default false) {
        return ($style.bullet | get ($deep mod ($style.bullet | length)))
    }
    let typed = $src | get -o ($line - 1) | default "" | parse --regex '^[\s>]*(?<n>\d+)[.)]' | get -o 0.n
    $"($typed | default (($a | get -o index | default 0) + 1 | into string)). "
}

# ── blocks → a page ───────────────────────────────────────────────────────────
# Blocks, in order, and the air between them.
#
# THE SOURCE'S BLANK LINES ARE THE DEFAULT, NOT THE RULE. Markdown needs a blank
# line between two blocks whether or not a reader wants one there, and on a
# drawer twelve rows tall an unearned blank is a row of the message lost. Two
# things overrule it, and both are typography rather than syntax:
#
#   A HEADING TAKES ITS AIR ABOVE. It belongs to the section beneath it, so the
#   blank goes before it and never after. That is what makes it read as a
#   heading rather than as a line floating between two paragraphs — and it hands
#   the row back, which on this display is the same argument twice.
#
#   SIBLING LIST ITEMS ARE NEVER SEPARATED. Whether a list is "loose" is a
#   distinction HTML cares about; a list of four things is a list of four things.
def stack [blocks: list<record>, width: int, style: record, src: list<string>, budget: int]: nothing -> list<record> {
    mut out = []
    mut prev = -1
    mut last = ""
    for b in $blocks {
        let left = $budget - ($out | length)
        if $left <= 0 { break }
        let ls = render-block $b $width $style $src $left
        if ($ls | is-empty) { continue }
        if ($out | is-not-empty) and (spaced $b.k $b.s $last $prev) { $out = $out ++ [{k: "text", t: ""}] }
        $out = $out ++ $ls
        $prev = $b.e
        $last = $b.k
    }
    $out | first $budget
}

def spaced [kind: string, start: int, last: string, prev: int]: nothing -> bool {
    if $kind == "head" { return true }
    if $last == "head" { return false }
    if ($kind == "item") and ($last == "item") { return false }
    ($start - $prev) >= 2
}

# ── the whole of it ───────────────────────────────────────────────────────────

# Markdown in, display rows out: already reflowed, already wrapped to `width`,
# and never more than `budget` of them. Ask for one row MORE than the rectangle
# holds and `lay-out` can tell that something was left over.
#
# A LONG MESSAGE IS READ IN A PREFIX FIRST. Parsing is the one cost that does
# not care about the budget — 31KB took 4ms of a 5ms render — and a drawer
# twelve rows tall cannot be showing more than the first hundred-odd lines of
# anything. So a generous prefix is tried, and the whole text only if the prefix
# did not fill the rectangle. That second pass is what makes it a shortcut
# rather than a guess: no ratio of source lines to rows is safe in general — a
# screenful of `---` is a hundred lines and no rows at all — so the cheap answer
# is checked rather than trusted.
export def plain-md [md: string, width: int, budget: int]: nothing -> list<record> {
    let src = $md | default "" | str replace --all "\t" "    " | str replace --all "\r" "" | lines
    let head = ($budget * 8) + 16
    if ($src | length) > $head {
        let quick = render ($src | first $head) $width $budget
        if ($quick | length) >= $budget { return $quick }
    }
    render $src $width $budget
}

def render [src: list<string>, width: int, budget: int]: nothing -> list<record> {
    let text = $src | str join "\n"
    # A message that will not parse must still be shown. There is no input that
    # does this today — an unclosed fence, a stray backtick and raw HTML all
    # parse — but a display that paints nothing is the worst failure here.
    let nodes = try { $text | from md --verbose } catch { [] }
    if ($nodes | is-empty) { return (tag "text" (flow (unfold $text) $width $budget)) }
    stack (group $nodes $budget) $width $STYLE $src $budget
}

# The text of a set of rows, for a caller that has no way to colour them.
export def text [rows: list<record>]: nothing -> list<string> { $rows | get t }

# ── laying out ────────────────────────────────────────────────────────────────

# Rows in, rows out: blanks collapsed to one, the whole thing capped, and the
# last line told to say so if anything was dropped. `plain` has already wrapped
# to this width, so the cut here is a belt — it is what catches a renderer that
# got the arithmetic wrong rather than something that happens in normal use.
export def lay-out [source: list<record>, width: int, max: int]: nothing -> list<record> {
    mut out = []
    mut cut = false
    for r in $source {
        if ($out | length) >= $max {
            $cut = true
            break
        }
        # Never open on a blank, and never stack two: an empty row is the
        # scarcest thing on a drawer twelve rows tall.
        if ($r.t | str trim | is-empty) {
            let room = ($out | is-not-empty) and ((($out | last).t) != "")
            if $room { $out = $out ++ [{k: "text", t: ""}] }
            continue
        }
        $out = $out ++ [($r | update t (cut-to $r.t $width))]
    }
    let trimmed = $out | reverse | skip while {|r| $r.t == "" } | reverse
    if (not $cut) or ($trimmed | is-empty) { return $trimmed }
    let last = $trimmed | last
    # A line that was itself cut already ends in an ellipsis — do not stack a
    # second one on it.
    if ($last.t | str ends-with "…") { return $trimmed }
    ($trimmed | drop 1) ++ [($last | update t (mark $last.t $width))]
}
