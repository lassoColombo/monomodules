# State glyphs — the single source of truth for how agent states render, in
# both the zellij pane/tab titles and the SketchyBar notifier. Restyle here.
# Subtle monochrome shapes (distinct by shape): they inherit the theme fg in
# zellij (so they're always on-palette, never flashy) and get Rosé Pine accent
# colours in SketchyBar, where per-glyph colour is actually possible.

export const S_WORK = "◦"   # working — busy, nothing for you to do
export const S_WAIT = "•"   # your turn — agent returned control
export const S_NEED = "▴"   # needs attention — agent is blocked

# The markers, most-urgent first. Aggregates and title parsing fold in this order.
export const markers = [$S_NEED $S_WAIT $S_WORK]

# Map a state name to its glyph.
export def state-glyph [state: string] {
    if $state == "needs-attention" { $S_NEED } else if $state == "awaiting" { $S_WAIT } else if $state == "working" { $S_WORK } else { "·" }
}

# Map a glyph back to its state name (inverse of state-glyph, for parsed titles).
export def state-name [symbol: string] {
    if $symbol == $S_NEED { "needs-attention" } else if $symbol == $S_WAIT { "awaiting" } else if $symbol == $S_WORK { "working" } else { "idle" }
}
