# State glyphs — the single source of truth for how agent states render, in
# both the zellij pane/tab titles and the SketchyBar notifier. Restyle here.
# Monochrome text glyphs (inherit the theme fg), not color emoji.

export const S_WORK = "○"   # working — busy, nothing for you to do
export const S_WAIT = "●"   # your turn — agent returned control
export const S_NEED = "▲"   # needs attention — agent is blocked

# Map a store state name to its glyph.
export def state-glyph [state: string] {
    if $state == "needs-attention" { $S_NEED } else if $state == "awaiting" { $S_WAIT } else if $state == "working" { $S_WORK } else { "·" }
}
