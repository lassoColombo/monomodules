# State glyphs — the single source of truth for how agent states render in the
# zellij pane/tab titles AND on the SketchyBar counters. Nerd Font (Font Awesome
# BMP) icons, picked so the three states are told apart by SHAPE alone: zellij
# titles can't carry colour, so the shape has to do the whole job. On the bar
# the same glyphs get the state hue (render/theme.nu), matching the wifi /
# volume / battery widgets.
#
#   f021 ↻ circular arrows — turning, in progress
#   f075 speech bubble     — the agent is talking to you
#   f071 warning triangle  — blocked, needs a hand

export const S_WORK = ""   # f021 working — busy, nothing for you to do
export const S_WAIT = ""   # f075 your turn — agent returned control (a.k.a. "stale")
export const S_NEED = ""   # f071 needs attention — agent is blocked

# The markers, most-urgent first. Aggregates and title parsing fold in this order.
export const markers = [$S_NEED $S_WAIT $S_WORK]

# Glyphs this module used to write into titles. Never emitted any more — kept so
# parse-title can still strip them off panes/tabs tagged before the icon change.
export const legacy_markers = ["▴" "•" "◦"]

# Map a state name to its glyph, or "" for idle/unknown (no prefix in titles).
export def glyph-of [state: string] {
    if $state == "needs-attention" { $S_NEED } else if $state == "awaiting" { $S_WAIT } else if $state == "working" { $S_WORK } else { "" }
}
