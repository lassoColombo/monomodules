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

# Area band layout.
export def area-style []: nothing -> list<string> {
    ["stacked" "overlay" "normalized" "stream"]
}

# Box-plot whisker reach: multiples of the IQR, or the data extremes.
export def box-extent []: nothing -> list<string> {
    ["1.5" "3" "min-max"]
}

# What an error bar's interval measures.
export def error-extent []: nothing -> list<string> {
    ["ci" "stderr" "stdev" "iqr"]
}

export def error-style []: nothing -> list<string> {
    ["bar" "band"]
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

# Vega-Lite aggregate operations usable for combining rows into one cell/bar.
export def agg []: nothing -> list<string> {
    [
        "sum" "mean" "median" "min" "max" "count" "distinct"
        "stdev" "stderr" "variance" "q1" "q3"
    ]
}

# Vega color schemes for continuous scales. Sequential first, then diverging.
# https://vega.github.io/vega/docs/schemes/
export def color-scheme []: nothing -> list<string> {
    [
        "viridis" "magma" "inferno" "plasma" "turbo" "cividis"
        "blues" "greens" "greys" "oranges" "purples" "reds"
        "bluepurple" "purplered" "yellowgreenblue" "warmgreys" "browns"
        "blueorange" "redblue" "redyellowblue" "spectral" "pinkyellowgreen"
    ]
}
