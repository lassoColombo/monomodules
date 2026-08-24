# State glyphs — the single source of truth for how agent states render in the
# zellij pane/tab titles. Subtle monochrome shapes (distinct by shape): they
# inherit the theme fg in zellij (always on-palette). The SketchyBar plugin owns
# its own colour mapping (presentation lives on the bar side).

export const S_WORK = "◦"   # working — busy, nothing for you to do
export const S_WAIT = "•"   # your turn — agent returned control (a.k.a. "stale")
export const S_NEED = "▴"   # needs attention — agent is blocked

# The markers, most-urgent first. Aggregates and title parsing fold in this order.
export const markers = [$S_NEED $S_WAIT $S_WORK]

# Map a state name to its glyph, or "" for idle/unknown (no prefix in titles).
export def glyph-of [state: string] {
    if $state == "needs-attention" { $S_NEED } else if $state == "awaiting" { $S_WAIT } else if $state == "working" { $S_WORK } else { "" }
}
