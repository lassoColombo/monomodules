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

# Greedy word-wrap `text` into ≤ max_lines lines of ≤ width chars; the last line
# gets an ellipsis when there was more. max_lines = 1 is therefore also the
# single-line truncator. Empty in → empty list out.
export def wrap-text [text: string, width: int, max_lines: int] {
    mut lines = []
    mut cur = ""
    for w0 in ($text | split row " " | where {|w| $w != "" }) {
        mut word = $w0
        # hard-split a word longer than the whole width
        while ($word | str length) > $width {
            if ($cur | is-not-empty) { $lines = $lines ++ [$cur]; $cur = "" }
            $lines = $lines ++ [($word | str substring 0..<$width)]
            $word = ($word | str substring $width..)
        }
        if ($cur | is-empty) {
            $cur = $word
        } else if ((($cur | str length) + 1 + ($word | str length)) <= $width) {
            $cur = $"($cur) ($word)"
        } else {
            $lines = $lines ++ [$cur]; $cur = $word
        }
    }
    if ($cur | is-not-empty) { $lines = $lines ++ [$cur] }
    if ($lines | length) > $max_lines {
        ($lines | first ($max_lines - 1)) ++ [ (($lines | get ($max_lines - 1) | str substring 0..<($width - 1)) + "…") ]
    } else { $lines }
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
