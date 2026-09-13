# Markdown in, plain display lines out.
#
# A LEAF, AND SHARED. It was `integrations/sketchybar/text.nu` while the bar was
# the only thing that had to show an agent's message; the picker's preview is the
# second (step 8), and a flattener that two surfaces read is not the bar's. It
# imports nothing and touches nothing, so anything may take it — including the
# hot half, though nothing there needs it yet.
#
# WHAT IT IS FOR, in both callers: a stored message is markdown, and the places
# it has to appear are not. A SketchyBar label takes ONE font and ONE colour and
# holds ONE line; a picker preview is a fixed rectangle of a terminal with no
# renderer behind it. The bold, the headings and the fences are noise in both.
# So: strip, then lay out.
#
# NOTHING IS WRAPPED. An earlier version folded a long line onto a second row,
# which is what a 62-character drawer forced. A drawer is 110 characters wide
# now, and at that width a fold is pure loss: the continuation eats one of the
# twelve slots, and two rows read as two thoughts when they are one sentence. A
# line that does not fit is CUT and says so.
#
# WHY NOT PANDOC, which is what v1 used. v1 converted where the preview was
# STORED, once per message, so the ~30ms was paid on a path that was already
# spawning processes. v2 has no such path — the surface runs inside the agent's
# own hook and the whole paint is one ~7ms message — so a subprocess here would
# be four times the cost of everything else put together. Doing it in nushell
# also keeps the markdown itself in the store, where both readers want it.
#
# NOTHING HERE KNOWS ABOUT ITS CALLER. It is given a width and a line budget and
# returns strings; the item names, the colours, the shell and the escaping that
# shell needs all live next door, in `integrations/sketchybar/items.nu`.

# ── measuring ────────────────────────────────────────────────────────────────
# By CHARACTER, not by byte. Slicing a string at a byte offset can land inside a
# codepoint and turn an em dash into a replacement glyph — and a character is
# also what a label's width actually counts.

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

# ── markdown → plain lines ───────────────────────────────────────────────────
# Line-based on purpose. The block structure is the only formatting that survives
# to a stack of labels or a preview pane, so a list stays a list and a fenced
# block stays a block; everything inside a line is flattened.

def strip-inline [line: string]: nothing -> string {
    $line
    | str replace --all --regex '!\[([^\]]*)\]\([^)]*\)' '${1}'
    | str replace --all --regex '\[([^\]]*)\]\([^)]*\)' '${1}'
    | str replace --all '`' ''
    | str replace --all '**' ''
    | str replace --all '~~' ''
    | str replace --all --regex '\*([^*]+)\*' '${1}'
}

export def plain [md: string]: nothing -> list<string> {
    mut out = []
    mut fenced = false
    for raw in ($md | default "" | str replace --all "\t" "    " | lines) {
        let line = $raw | str trim --right
        # A fence is a toggle and is never itself shown; what it wraps is code,
        # and code is the one thing that must reach the screen untouched.
        if ($line =~ '^\s*```') {
            $fenced = (not $fenced)
            continue
        }
        if $fenced {
            $out = $out ++ [$line]
            continue
        }
        # A thematic break renders as a full-width run of dashes — a whole
        # preview row spent on nothing — and a table's rule is the same thing.
        if ($line =~ '^\s*(-{3,}|\*{3,}|_{3,})\s*$') { continue }
        if ($line =~ '^[\s|:-]*\|[\s|:-]*$') { continue }
        let bare = $line
            | str replace --regex '^\s*>\s?' ''
            | str replace --regex '^#{1,6}\s+' ''
            | str replace --regex '^(\s*)[-*+]\s+' '${1}• '
        $out = $out ++ [(strip-inline $bare)]
    }
    $out
}

# ── laying out ───────────────────────────────────────────────────────────────

# Plain lines in, display rows out: ONE ROW PER SOURCE LINE, blanks collapsed to
# one, the whole thing capped. The block structure survives because nothing is
# ever merged or split — a list stays a list, a table's rows stay aligned, and a
# code block keeps its indentation, which a word wrap could never preserve.
export def lay-out [source: list<string>, width: int, max: int]: nothing -> list<string> {
    mut out = []
    mut cut = false
    for line in $source {
        if ($out | length) >= $max {
            $cut = true
            break
        }
        # Never open on a blank, and never stack two: an empty row is the
        # scarcest thing on a drawer twelve rows tall.
        if ($line | str trim | is-empty) {
            let room = ($out | is-not-empty) and (($out | last) != "")
            if $room { $out = $out ++ [""] }
            continue
        }
        $out = $out ++ [(cut-to $line $width)]
    }
    let trimmed = $out | reverse | skip while {|l| $l == "" } | reverse
    if not $cut { return $trimmed }
    let last = $trimmed | last | default ""
    # A line that was itself cut already ends in an ellipsis — do not stack a
    # second one on it.
    if ($last | str ends-with "…") { return $trimmed }
    ($trimmed | drop 1) ++ [(mark $last $width)]
}
