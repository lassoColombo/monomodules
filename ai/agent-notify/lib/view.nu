# Presentation-neutral derivation of agent records into display text: the row
# label, one-line/wrapped previews, and the urgency ordering. Shared by every
# surface that renders the store — the terminal picker (lib/picker.nu) and the
# SketchyBar plugin — so both show the same rows in the same order and neither
# grows its own copy. Colours, fonts and glyph *choice* stay with the surface;
# only the shapes (lib/state.nu) are common, and re-exported here so one import
# is enough.

export use state.nu *

# One agent's row label: "<session>/<tab>  ·  <pane>", with the pane dropped
# when it adds nothing over the tab name.
export def label [it: record] {
    let tab = $it.tab_name? | default ""
    let pane = $it.pane_name? | default ""
    if ($pane == $tab) or ($pane == "") { $"($it.session)/($tab)" } else { $"($it.session)/($tab)  ·  ($pane)" }
}

# Preview text flattened onto a single line (labels are single-line everywhere).
export def one-line [text?: string] {
    $text | default "" | str replace --all "\n" " " | str replace --all "\t" " " | str trim
}

# `str substring` and `str length` both count BYTES, so slicing a string at a
# width can land in the middle of a codepoint and turn an em dash into a
# replacement glyph. These two cut and measure by CHARACTER instead — which is
# also what a terminal column and a bar label actually count.
def take-chars [text: string, n: int] {
    let cs = $text | split chars
    if ($cs | length) <= $n { $text } else { $cs | first ([0 $n] | math max) | str join }
}
def char-len [text: string] { $text | split chars | length }

# Greedy word-wrap `text` into ≤ max_lines lines of ≤ width chars; the last line
# gets an ellipsis when there was more. max_lines = 1 is therefore also the
# single-line truncator. Empty in → empty list out.
export def wrap-text [text: string, width: int, max_lines: int] {
    mut lines = []
    mut cur = ""
    for w0 in ($text | split row " " | where {|w| $w != "" }) {
        mut word = $w0
        # hard-split a word longer than the whole width
        while (char-len $word) > $width {
            if ($cur | is-not-empty) { $lines = $lines ++ [$cur]; $cur = "" }
            $lines = $lines ++ [(take-chars $word $width)]
            $word = ($word | split chars | skip $width | str join)
        }
        if ($cur | is-empty) {
            $cur = $word
        } else if (((char-len $cur) + 1 + (char-len $word)) <= $width) {
            $cur = $"($cur) ($word)"
        } else {
            $lines = $lines ++ [$cur]; $cur = $word
        }
    }
    if ($cur | is-not-empty) { $lines = $lines ++ [$cur] }
    if ($lines | length) > $max_lines {
        ($lines | first ($max_lines - 1)) ++ [ ((take-chars ($lines | get ($max_lines - 1)) ($width - 1)) + "…") ]
    } else { $lines }
}

# A whole preview as display lines — the BAR's layout: SketchyBar stacks one
# label per line, so the wrapping has to be done here. The terminal picker hands
# its text to skim's preview window instead, which wraps and scrolls it itself.
#
# Every source line is wrapped on its OWN, so the block structure a stored
# preview still carries (see markdown.nu) survives to the screen — a code block
# stays a stack of lines, a list stays a list, blank lines keep paragraphs apart. Capped at `max_lines`, ellipsised when there was
# more. A line that already fits is passed through untouched, which is what
# keeps indentation: `wrap-text` splits on spaces and so cannot preserve it.
export def preview-lines [text: string, width: int, max_lines: int] {
    mut out = []
    mut cut = false
    for src0 in ($text | str replace --all "\t" "    " | lines) {
        let src = $src0 | str trim --right
        if ($out | length) >= $max_lines { $cut = true; break }
        # Never open on a blank, and never stack two: pandoc separates every
        # block with one, and empty rows are the scarcest thing on a 12-row chip.
        if ($src | is-empty) {
            if ($out | is-not-empty) and (($out | last) != "") { $out = $out ++ [""] }
            continue
        }
        $out = $out ++ (if (char-len $src) <= $width { [$src] } else {
            wrap-text $src $width ($max_lines - ($out | length))
        })
    }
    let trimmed = $out | reverse | skip while {|l| $l == "" } | reverse
    if not $cut { return $trimmed }
    # Mark the truncation on the last line we kept, in the space it already has.
    let last = $trimmed | last | default ""
    # `wrap-text` marks its own overflow, so a line that ran out of budget inside
    # a block already ends in an ellipsis — don't stack a second one on it.
    if ($last | str ends-with "…") { return $trimmed }
    ($trimmed | drop 1) ++ [ $"(take-chars $last ($width - 2) | str trim --right) …" ]
}

# Urgency of a state, most urgent first — read off `markers` (state.nu already
# orders the glyphs that way), so there is no second list of state names.
# Idle/unknown sorts last.
export def rank [state: string] {
    let g = glyph-of $state
    $markers | enumerate | where item == $g | get -o 0.index | default ($markers | length)
}

# The canonical order of agent rows: most urgent first, then by tab, then pane.
export def sort-agents [recs: list<any>] {
    $recs | sort-by {|r| rank ($r.state? | default "idle") } {|r| $r.tab_position? | default 0 } {|r| $r.pane_id? | default 0 }
}
