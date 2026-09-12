# Markdown in, SketchyBar labels out.
#
# A label takes ONE font and ONE colour and holds ONE line, so everything that
# makes a message readable in a terminal — the bold, the headings, the fences —
# is noise here, and a paragraph has to be cut into rows before it can be shown
# at all. That is this file: strip, then lay out.
#
# WHY NOT PANDOC, which is what v1 used. v1 converted where the preview was
# STORED, once per message, so the ~30ms was paid on a path that was already
# spawning processes. v2 has no such path — the surface runs inside the agent's
# own hook and the whole paint is one ~7ms message — so a subprocess here would
# be four times the cost of everything else put together. Doing it in nushell
# also keeps the markdown itself in the store, where the picker still wants it.
#
# NOTHING HERE KNOWS ABOUT THE BAR. It is given a width and a line budget and
# returns strings; the item names, the colours and the shell live next door.

# ── measuring ────────────────────────────────────────────────────────────────
# By CHARACTER, not by byte. Slicing a string at a byte offset can land inside a
# codepoint and turn an em dash into a replacement glyph — and a character is
# also what a label's width actually counts.

def chars [s: string]: nothing -> int { $s | split chars | length }

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

# Safe to wrap in SINGLE QUOTES inside a generated shell command, which is how a
# preview reaches the bar (see items.nu). Probed on the real daemon: inside single
# quotes `$HOME` and backticks stay literal and only `'` can break out, so one
# substitution is the whole of the escaping — and a typographic apostrophe is what
# the text wanted anyway. Control characters go too: a stray \r would end the
# command line early.
export def quotable [s: string]: nothing -> string {
    $s | str replace --all "'" "’" | str replace --all --regex '[\x00-\x1f]' " "
}

# ── markdown → plain lines ───────────────────────────────────────────────────
# Line-based on purpose. The block structure is the only formatting that survives
# to a stack of labels, so a list stays a list and a fenced block stays a block;
# everything inside a line is flattened.

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

# Greedy word wrap into at most `max` lines of at most `width` characters; the
# last one is ellipsised when there was more. `max = 1` is therefore also the
# single-line truncator.
def fold [text: string, width: int, max: int]: nothing -> list<string> {
    mut lines = []
    mut cur = ""
    for w0 in ($text | split row " " | where {|w| $w != "" }) {
        mut word = $w0
        # A word longer than the whole width has to be cut, not wrapped.
        while (chars $word) > $width {
            if ($cur | is-not-empty) {
                $lines = $lines ++ [$cur]
                $cur = ""
            }
            $lines = $lines ++ [($word | split chars | first $width | str join)]
            $word = ($word | split chars | skip $width | str join)
        }
        if ($cur | is-empty) {
            $cur = $word
        } else {
            let fits = ((chars $cur) + 1 + (chars $word)) <= $width
            if $fits {
                $cur = $"($cur) ($word)"
            } else {
                $lines = $lines ++ [$cur]
                $cur = $word
            }
        }
    }
    if ($cur | is-not-empty) { $lines = $lines ++ [$cur] }
    if ($lines | length) <= $max { return $lines }
    ($lines | first ($max - 1)) ++ [(mark ($lines | get ($max - 1)) $width)]
}

# Plain lines in, display rows out: each source line wrapped on its OWN so the
# block structure survives, blanks collapsed to one, the whole thing capped.
#
# INDENTATION IS KEPT by passing a line that already fits straight through —
# `fold` splits on spaces and so cannot preserve it. That is what keeps a code
# block looking like one.
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
        let room = $max - ($out | length)
        let wrapped = if (chars $line) <= $width { [$line] } else { fold $line $width $room }
        $out = $out ++ $wrapped
    }
    let trimmed = $out | reverse | skip while {|l| $l == "" } | reverse
    if not $cut { return $trimmed }
    let last = $trimmed | last | default ""
    # `fold` marks its own overflow, so a line that ran out of budget inside a
    # block already ends in an ellipsis — do not stack a second one on it.
    if ($last | str ends-with "…") { return $trimmed }
    ($trimmed | drop 1) ++ [(mark $last $width)]
}
