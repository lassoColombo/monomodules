# Completers for every plot flag that has a knowable value set.
#
# Imported without a glob (`use ./complete.nu`) so completers are addressable as
# @"complete <name>" — e.g. `complete smooth`, `complete legend-pos`.
#
# Column completers read the shape of the LAST plotted table (see state.nu): a
# nushell completer cannot see pipeline input, so the previous run is the only
# thing we can offer. Empty until you have plotted once.

use ./state.nu

# ---- column completers (data-driven) ----

# Any column of the last plotted table — for -x.
export def columns []: nothing -> list<string> { state recall columns "all" }

# Numeric columns only — for --y, which must be measurable.
export def "numeric-columns" []: nothing -> list<string> { state recall columns "numeric" }

# Non-numeric columns — for --series, whose VALUES name each series.
export def "label-columns" []: nothing -> list<string> { state recall columns "other" }

# ---- static completers ----

# Line curve interpolation (Vega-Lite `interpolate`). "none"/"linear" draw
# straight segments between points; the rest smooth the curve through them.
export def smooth []: nothing -> list<string> {
    ["none" "linear" "monotone" "basis" "cardinal" "natural"]
}

export def "bar-style" []: nothing -> list<record<value: string, description: string>> {
    [
        {value: "clustered",  description: "side-by-side bars per category"}
        {value: "stacked",    description: "bars stacked by series"}
        {value: "normalized", description: "stacked to 100% (relative share)"}
    ]
}

export def "step-where" []: nothing -> list<record<value: string, description: string>> {
    [
        {value: "pre",  description: "rise before the point"}
        {value: "post", description: "rise after the point"}
        {value: "mid",  description: "rise halfway between points"}
    ]
}

# Vega-Lite point-mark shapes (scatter).
export def "point-shape" []: nothing -> list<string> {
    [
        "circle" "square" "cross" "diamond"
        "triangle-up" "triangle-down" "triangle-right" "triangle-left"
        "arrow" "wedge" "stroke"
    ]
}

# Vega-Lite legend `orient` positions.
export def "legend-pos" []: nothing -> list<string> {
    [
        "top" "bottom" "left" "right"
        "top-left" "top-right" "bottom-left" "bottom-right"
        "none"
    ]
}

# d3-format specs for --xformat / --yformat.
export def format []: nothing -> list<record<value: string, description: string>> {
    [
        {value: ".0f",   description: "integer"}
        {value: ".1f",   description: "1 decimal"}
        {value: ".2f",   description: "2 decimals"}
        {value: ",",     description: "thousands separator"}
        {value: "$,.0f", description: "currency"}
        {value: ".1%",   description: "percentage"}
        {value: ".2s",   description: "SI prefix (1.2k)"}
        {value: ".2e",   description: "scientific"}
    ]
}

# Pixel sizes for --width / --height (file output only; the terminal auto-fits).
export def size []: nothing -> list<record<value: string, description: string>> {
    [
        {value: "600",  description: "small"}
        {value: "800",  description: "default width"}
        {value: "1000", description: "large"}
        {value: "1400", description: "presentation"}
    ]
}

# Bucket counts for histogram --bins.
export def bins []: nothing -> list<string> { ["10" "20" "30" "50" "100"] }

# Multipliers for --point-size / --linewidth.
export def scale []: nothing -> list<record<value: string, description: string>> {
    [
        {value: "0.5", description: "half"}
        {value: "1.0", description: "default"}
        {value: "1.5", description: "large"}
        {value: "2.0", description: "double"}
    ]
}

# Output formats vl-convert can emit, as extensions for --out.
export def "out-format" []: nothing -> list<record<value: string, description: string>> {
    [
        {value: "png",  description: "raster"}
        {value: "svg",  description: "vector"}
        {value: "pdf",  description: "vector, print"}
        {value: "jpg",  description: "raster, lossy"}
        {value: "html", description: "interactive vega embed"}
    ]
}
