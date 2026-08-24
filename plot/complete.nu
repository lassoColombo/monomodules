# Static completers for plot commands.
# Imported via `use ./complete.nu` (no glob) so they're addressable as
# @"complete xxx" — e.g. `complete smooth`, `complete legend-pos`.

# Line curve interpolation (Vega-Lite `interpolate`). "none"/"linear" draw
# straight segments between points; the rest smooth the curve through them.
export def smooth []: nothing -> list<string> {
    ["none" "linear" "monotone" "basis" "cardinal" "natural"]
}

export def bar-style []: nothing -> list<string> {
    ["clustered" "stacked" "normalized"]
}

export def step-where []: nothing -> list<string> {
    ["pre" "post" "mid"]
}

# Vega-Lite point-mark shapes (scatter).
# https://vega.github.io/vega-lite/docs/point.html#properties
export def point-shape []: nothing -> list<string> {
    [
        "circle" "square" "cross" "diamond"
        "triangle-up" "triangle-down" "triangle-right" "triangle-left"
        "arrow" "wedge" "stroke"
    ]
}

# Vega-Lite legend `orient` positions.
export def legend-pos []: nothing -> list<string> {
    [
        "top" "bottom" "left" "right"
        "top-left" "top-right" "bottom-left" "bottom-right"
        "none"
    ]
}
