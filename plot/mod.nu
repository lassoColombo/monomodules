# Plot — a Nushell wrapper around a Vega-Lite renderer (via the `vl-convert` CLI).
#
# Each data subcommand consumes a table (`list<record>`) on stdin, builds a
# Vega-Lite spec, and renders it to an image via the native `vl-convert` CLI
# (see `vega.nu`). There is no interactive window: output is always written to a
# file (a temp PNG by default, or `--out <path>` whose format follows the
# extension) and opened with `start`.
#
# Public surface:
#   plot line       — one or more y-series vs x, with optional curve smoothing
#   plot scatter    — points
#   plot bar        — categorical x, clustered / stacked / normalized y
#   plot histogram  — distribution of a single numeric column
#   plot step       — step function (pre/post/mid)
#   plot impulses   — vertical sticks
#
# Common conventions:
#   • `--x-axis`/`-x` selects the x column; `--y` is a list of y columns.
#   • Output format follows the `--out` extension (png, jpg, svg, pdf, html);
#     with no `--out` a temp PNG is written. `--no-open` skips the viewer.
#   • `--xformat`/`--yformat` take d3-format specs (e.g. ".2f", "$,.0f", "%").
#   • Set `$env.PLOT_DEBUG = "/tmp/plot.vl.json"` to dump the generated
#     Vega-Lite spec for inspection.
#
# Requires the `vl-convert` CLI on PATH (https://github.com/vega/vl-convert).

use ./complete.nu
use ./validate.nu
use ./vega.nu

# Line plot of one or more y-series against x.
#
# The x column may be numeric, datetime, or categorical (string). Multiple y
# columns are drawn as overlaid series sharing the same x axis. `--smooth`
# interpolates the curve through the points (e.g. monotone, basis, cardinal).
@category plot
@search-terms plot line chart timeseries
@example "Sine wave to a temp PNG" {
    seq 0 60 | each {|i| {x: $i, y: ($i * 0.1 | math sin)}} | plot line -x x --y [y]
}
@example "Two series, headless to a temp PNG" {
    seq 1 20
    | each {|i| {t: $i, a: ($i * $i), b: ($i * 3)}}
    | plot line -x t --y [a b] --title "quadratic vs linear" --grid --out /tmp/plot-line.png --no-open
}
@example "Smoothed line with custom labels" {
    seq 1 30
    | each {|i| {x: $i, y: ($i + (random float (-3)..3))}}
    | plot line -x x --y [y] --smooth monotone --xlabel step --ylabel value --out /tmp/plot-smooth.png --no-open
}
export def line [
    --x-axis (-x): string,                          # x column (required)
    --y: list<string>,                              # y columns (required, one or more)
    --smooth: string@"complete smooth" = "none",    # curve interpolation (see `complete smooth`)
    --title (-t): string,                           # plot title
    --xlabel: string,                               # x-axis label
    --ylabel: string,                               # y-axis label
    --xrange: list<any>,                            # [min max] for x axis
    --yrange: list<any>,                            # [min max] for y axis
    --width: int = 800,                             # plotting-area width in px
    --height: int = 600,                            # plotting-area height in px
    --grid,                                         # draw a background grid
    --no-legend,                                    # hide the series legend
    --logx,                                         # log scale on x axis
    --logy,                                         # log scale on y axis
    --legend-pos: string@"complete legend-pos",     # legend position, e.g. "top-right"
    --xformat: string,                              # d3-format spec for x tics (e.g. ".2f")
    --yformat: string,                              # d3-format spec for y tics
    --out (-o): path,                               # output file (format from extension)
    --no-open,                                       # don't auto-open the output file
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot line" "--x-axis" $x_axis
    require-non-empty "plot line" "--y" $y
    $data | validate assert columns ([$x_axis] | append $y) | ignore
    for col in $y { $data | validate assert numeric $col | ignore }

    let interp = smooth-interp $smooth
    let mark = if ($interp == null) { "line" } else { {type: "line", interpolate: $interp} }

    vega {
        data: $data
        mark: $mark
        transform: [{fold: $y, as: ["series" "value"]}]
        encoding: {
            x: {field: $x_axis, type: (x-type $data $x_axis)}
            y: {field: "value", type: "quantitative"}
            color: {field: "series", type: "nominal", title: null}
        }
        x_channel: "x"
        y_channel: "y"
        appearance: (appearance $title $xlabel ($ylabel | default-ylabel $y) $xrange $yrange $width $height $grid $no_legend $logx $logy $legend_pos $xformat $yformat ($y | length))
        out: $out
        open: (not $no_open)
    }
}

# Scatter plot of one or more y-series against x.
#
# `--shape` picks the marker (see `complete point-shape`) and `--point-size`
# scales it.
@category plot
@search-terms plot scatter points marker
@example "Random cloud to a temp PNG" {
    seq 1 200 | each {|_| {x: (random float (-5)..5), y: (random float (-5)..5)}} | plot scatter -x x --y [y]
}
@example "Two series with grid, headless to PNG" {
    seq 1 50
    | each {|i| {i: $i, a: (random float 0..10), b: (random float 5..15)}}
    | plot scatter -x i --y [a b] --grid --shape diamond --point-size 1.4 --out /tmp/plot-scatter.png --no-open
}
export def scatter [
    --x-axis (-x): string,                          # x column (required)
    --y: list<string>,                              # y columns (required, one or more)
    --shape: string@"complete point-shape" = "circle",  # marker shape
    --point-size: float = 1.0,                      # point size multiplier
    --title (-t): string,                           # plot title
    --xlabel: string,                               # x-axis label
    --ylabel: string,                               # y-axis label
    --xrange: list<any>,                            # [min max] for x axis
    --yrange: list<any>,                            # [min max] for y axis
    --width: int = 800,                             # plotting-area width in px
    --height: int = 600,                            # plotting-area height in px
    --grid,                                         # draw a background grid
    --no-legend,                                    # hide the series legend
    --logx,                                         # log scale on x axis
    --logy,                                         # log scale on y axis
    --legend-pos: string@"complete legend-pos",     # legend position, e.g. "top-right"
    --xformat: string,                              # d3-format spec for x tics
    --yformat: string,                              # d3-format spec for y tics
    --out (-o): path,                               # output file (format from extension)
    --no-open,                                       # don't auto-open the output file
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot scatter" "--x-axis" $x_axis
    require-non-empty "plot scatter" "--y" $y
    $data | validate assert columns ([$x_axis] | append $y) | ignore
    for col in $y { $data | validate assert numeric $col | ignore }

    vega {
        data: $data
        mark: {type: "point", shape: $shape, size: ($point_size * 40 | math round), filled: true}
        transform: [{fold: $y, as: ["series" "value"]}]
        encoding: {
            x: {field: $x_axis, type: (x-type $data $x_axis)}
            y: {field: "value", type: "quantitative"}
            color: {field: "series", type: "nominal", title: null}
        }
        x_channel: "x"
        y_channel: "y"
        appearance: (appearance $title $xlabel ($ylabel | default-ylabel $y) $xrange $yrange $width $height $grid $no_legend $logx $logy $legend_pos $xformat $yformat ($y | length))
        out: $out
        open: (not $no_open)
    }
}

# Bar plot of one or more y-series against x.
#
# The x column is treated as categorical. `--style` chooses the layout:
#   clustered  → side-by-side bars per category (default)
#   stacked    → bars stacked by series
#   normalized → stacked to 100% (relative share)
@category plot
@search-terms plot bar column clustered stacked normalized
@example "Clustered bars from a small categorical table" {
    [
        {fruit: apple,  q1: 12, q2: 18}
        {fruit: pear,   q1: 7,  q2: 9}
        {fruit: banana, q1: 20, q2: 15}
    ] | plot bar -x fruit --y [q1 q2] --title "fruit sales" --grid
}
@example "Stacked bars, headless to PNG" {
    seq 1 6
    | each {|i| {label: $"day-($i)", reads: ($i * 10), writes: ($i * 4)}}
    | plot bar -x label --y [reads writes] --style stacked --out /tmp/plot-bar.png --no-open
}
export def bar [
    --x-axis (-x): string,                          # x column (required) — used as bar label
    --y: list<string>,                              # y columns (required, one or more)
    --style: string@"complete bar-style" = "clustered",  # clustered, stacked, or normalized
    --title (-t): string,                           # plot title
    --xlabel: string,                               # x-axis label
    --ylabel: string,                               # y-axis label
    --xrange: list<any>,                            # [min max] for x axis
    --yrange: list<any>,                            # [min max] for y axis
    --width: int = 800,                             # plotting-area width in px
    --height: int = 600,                            # plotting-area height in px
    --grid,                                         # draw a background grid
    --no-legend,                                    # hide the series legend
    --logx,                                         # log scale on x axis (ignored for categorical x)
    --logy,                                         # log scale on y axis
    --legend-pos: string@"complete legend-pos",     # legend position, e.g. "top-right"
    --xformat: string,                              # d3-format spec for x tics
    --yformat: string,                              # d3-format spec for y tics
    --out (-o): path,                               # output file (format from extension)
    --no-open,                                       # don't auto-open the output file
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot bar" "--x-axis" $x_axis
    require-non-empty "plot bar" "--y" $y
    $data | validate assert columns ([$x_axis] | append $y) | ignore
    for col in $y { $data | validate assert numeric $col | ignore }

    let y_ch = match $style {
        "clustered" => {field: "value", type: "quantitative", stack: null}
        "stacked" => {field: "value", type: "quantitative", stack: true}
        "normalized" => {field: "value", type: "quantitative", stack: "normalize"}
        _ => { error make {msg: $"plot bar: unknown --style '($style)'; use one of: (complete bar-style | str join ', ')"} }
    }
    let enc_base = {
        x: {field: $x_axis, type: "nominal"}
        y: $y_ch
        color: {field: "series", type: "nominal", title: null}
    }
    let enc = if $style == "clustered" {
        $enc_base | insert xOffset {field: "series", type: "nominal"}
    } else { $enc_base }

    # Normalized bars read as percentages unless the user forces a y format.
    let yfmt = if ($yformat == null) and ($style == "normalized") { "%" } else { $yformat }

    vega {
        data: $data
        mark: "bar"
        transform: [{fold: $y, as: ["series" "value"]}]
        encoding: $enc
        x_channel: "x"
        y_channel: "y"
        appearance: (appearance $title $xlabel ($ylabel | default-ylabel $y) $xrange $yrange $width $height $grid $no_legend $logx $logy $legend_pos $xformat $yfmt ($y | length))
        out: $out
        open: (not $no_open)
    }
}

# Histogram of a single numeric column's distribution.
#
# Values are binned into ~`--bins` equal-width buckets. With `--normalize` the
# y axis shows relative frequency (bucket count / N) instead of raw counts.
@category plot
@search-terms plot histogram distribution density
@example "Normal-ish distribution to a temp PNG" {
    seq 1 500
    | each {|_| {v: ((random float (-1)..1) + (random float (-1)..1) + (random float (-1)..1))}}
    | plot histogram --col v --bins 40
}
@example "Normalized histogram, headless to PNG" {
    seq 1 1000
    | each {|_| {x: (random float 0..10)}}
    | plot histogram --col x --bins 25 --normalize --title "uniform[0,10]" --out /tmp/plot-hist.png --no-open
}
export def histogram [
    --col (-c): string,                             # numeric column to histogram (required)
    --bins: int = 30,                               # approximate number of bins
    --normalize,                                    # plot relative frequency instead of counts
    --title (-t): string,                           # plot title
    --xlabel: string,                               # x-axis label (default: column name)
    --ylabel: string,                               # y-axis label (default: count/frequency)
    --xrange: list<any>,                            # [min max] for x axis
    --yrange: list<any>,                            # [min max] for y axis
    --width: int = 800,                             # plotting-area width in px
    --height: int = 600,                            # plotting-area height in px
    --grid,                                         # draw a background grid
    --logx,                                         # log scale on x axis
    --logy,                                         # log scale on y axis
    --xformat: string,                              # d3-format spec for x tics
    --yformat: string,                              # d3-format spec for y tics
    --out (-o): path,                               # output file (format from extension)
    --no-open,                                       # don't auto-open the output file
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot histogram" "--col" $col
    $data | validate assert columns [$col] | ignore
    $data | validate assert numeric $col | ignore

    let base_tf = [
        {bin: {maxbins: $bins}, field: $col, as: ["__b0" "__b1"]}
        {aggregate: [{op: "count", as: "__count"}], groupby: ["__b0" "__b1"]}
    ]
    let tf = if $normalize {
        $base_tf | append [
            {joinaggregate: [{op: "sum", field: "__count", as: "__total"}]}
            {calculate: "datum.__count / datum.__total", as: "__freq"}
        ]
    } else { $base_tf }
    let yfield = if $normalize { "__freq" } else { "__count" }
    let yl = if ($ylabel != null) { $ylabel } else if $normalize { "frequency" } else { "count" }

    vega {
        data: ($data | select $col)
        mark: "bar"
        transform: $tf
        encoding: {
            x: {field: "__b0", type: "quantitative", bin: "binned"}
            x2: {field: "__b1"}
            y: {field: $yfield, type: "quantitative"}
        }
        x_channel: "x"
        y_channel: "y"
        appearance: (appearance $title ($xlabel | default $col) $yl $xrange $yrange $width $height $grid true $logx $logy null $xformat $yformat 1)
        out: $out
        open: (not $no_open)
    }
}

# Step plot of one or more y-series against x.
#
# `--where` controls where the step happens between two samples:
#   pre  → step before the point  (Vega "step-before"; default)
#   post → step after the point   (Vega "step-after")
#   mid  → step at the midpoint    (Vega "step")
@category plot
@search-terms plot step staircase piecewise
@example "Staircase signal to a temp PNG" {
    [
        {t: 0, level: 0}
        {t: 1, level: 1}
        {t: 2, level: 1}
        {t: 3, level: 3}
        {t: 4, level: 2}
        {t: 5, level: 2}
    ] | plot step -x t --y [level] --grid
}
@example "Mid-step variant, headless to PNG" {
    seq 1 12
    | each {|i| {x: $i, y: (($i mod 3) + 1)}}
    | plot step -x x --y [y] --where mid --out /tmp/plot-step.png --no-open
}
export def step [
    --x-axis (-x): string,                          # x column (required)
    --y: list<string>,                              # y columns (required, one or more)
    --where: string@"complete step-where" = "pre",  # step placement: pre, post, or mid
    --title (-t): string,                           # plot title
    --xlabel: string,                               # x-axis label
    --ylabel: string,                               # y-axis label
    --xrange: list<any>,                            # [min max] for x axis
    --yrange: list<any>,                            # [min max] for y axis
    --width: int = 800,                             # plotting-area width in px
    --height: int = 600,                            # plotting-area height in px
    --grid,                                         # draw a background grid
    --no-legend,                                    # hide the series legend
    --logx,                                         # log scale on x axis
    --logy,                                         # log scale on y axis
    --legend-pos: string@"complete legend-pos",     # legend position, e.g. "top-right"
    --xformat: string,                              # d3-format spec for x tics
    --yformat: string,                              # d3-format spec for y tics
    --out (-o): path,                               # output file (format from extension)
    --no-open,                                       # don't auto-open the output file
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot step" "--x-axis" $x_axis
    require-non-empty "plot step" "--y" $y
    $data | validate assert columns ([$x_axis] | append $y) | ignore
    for col in $y { $data | validate assert numeric $col | ignore }

    vega {
        data: $data
        mark: {type: "line", interpolate: (step-interp $where)}
        transform: [{fold: $y, as: ["series" "value"]}]
        encoding: {
            x: {field: $x_axis, type: (x-type $data $x_axis)}
            y: {field: "value", type: "quantitative"}
            color: {field: "series", type: "nominal", title: null}
        }
        x_channel: "x"
        y_channel: "y"
        appearance: (appearance $title $xlabel ($ylabel | default-ylabel $y) $xrange $yrange $width $height $grid $no_legend $logx $logy $legend_pos $xformat $yformat ($y | length))
        out: $out
        open: (not $no_open)
    }
}

# Impulse plot: vertical sticks from y=0 to each y value.
#
# Good for sparse spikes (counts, deltas) where lines or bars would be noisy.
# `--linewidth` controls stick thickness.
@category plot
@search-terms plot impulses sticks spikes lollipop
@example "Sparse spikes to a temp PNG" {
    seq 1 25
    | each {|i| {x: $i, hits: (if (random int 0..4) == 0 { random int 1..10 } else { 0 })}}
    | plot impulses -x x --y [hits] --grid
}
@example "Thicker sticks, headless to PNG" {
    seq 1 15
    | each {|i| {i: $i, v: ($i mod 5)}}
    | plot impulses -x i --y [v] --linewidth 4 --out /tmp/plot-impulses.png --no-open
}
export def impulses [
    --x-axis (-x): string,                          # x column (required)
    --y: list<string>,                              # y columns (required, one or more)
    --linewidth (-w): float = 2.0,                  # stick thickness
    --title (-t): string,                           # plot title
    --xlabel: string,                               # x-axis label
    --ylabel: string,                               # y-axis label
    --xrange: list<any>,                            # [min max] for x axis
    --yrange: list<any>,                            # [min max] for y axis
    --width: int = 800,                             # plotting-area width in px
    --height: int = 600,                            # plotting-area height in px
    --grid,                                         # draw a background grid
    --no-legend,                                    # hide the series legend
    --logx,                                         # log scale on x axis
    --logy,                                         # log scale on y axis
    --legend-pos: string@"complete legend-pos",     # legend position, e.g. "top-right"
    --xformat: string,                              # d3-format spec for x tics
    --yformat: string,                              # d3-format spec for y tics
    --out (-o): path,                               # output file (format from extension)
    --no-open,                                       # don't auto-open the output file
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot impulses" "--x-axis" $x_axis
    require-non-empty "plot impulses" "--y" $y
    $data | validate assert columns ([$x_axis] | append $y) | ignore
    for col in $y { $data | validate assert numeric $col | ignore }

    vega {
        data: $data
        mark: {type: "rule", size: $linewidth}
        transform: [{fold: $y, as: ["series" "value"]}]
        encoding: {
            x: {field: $x_axis, type: (x-type $data $x_axis)}
            y: {field: "value", type: "quantitative"}
            y2: {datum: 0}
            color: {field: "series", type: "nominal", title: null}
        }
        x_channel: "x"
        y_channel: "y"
        appearance: (appearance $title $xlabel ($ylabel | default-ylabel $y) $xrange $yrange $width $height $grid $no_legend $logx $logy $legend_pos $xformat $yformat ($y | length))
        out: $out
        open: (not $no_open)
    }
}

# ---- helpers ----

def require-flag [cmd: string, flag: string, value: any] {
    let kind = $value | describe
    let missing = ($value == null) or ($kind == "string" and ($value | is-empty))
    if $missing {
        error make {msg: $"($cmd): ($flag) is required"}
    }
}

def require-non-empty [cmd: string, flag: string, value: any] {
    if ($value == null) or ($value | is-empty) {
        error make {msg: $"($cmd): ($flag) is required and must be non-empty"}
    }
}

# Map a column's detected kind to a Vega-Lite encoding type.
def x-type [data: list, col: string]: nothing -> string {
    match ($data | validate detect axis type $col) {
        "numeric" => "quantitative"
        "datetime" => "temporal"
        "categorical" => "nominal"
        $other => { error make {msg: $"plot: unsupported x-axis type '($other)'"} }
    }
}

# Map `--smooth` to a Vega-Lite line `interpolate` (null = straight segments).
def smooth-interp [s: string]: nothing -> any {
    match $s {
        "none" | "linear" => null
        _ => $s
    }
}

# Map `--where` to a Vega-Lite step `interpolate`.
def step-interp [w: string]: nothing -> string {
    match $w {
        "pre" => "step-before"
        "post" => "step-after"
        "mid" => "step"
        _ => { error make {msg: $"plot step: unknown --where '($w)'; use one of: (complete step-where | str join ', ')"} }
    }
}

# Default the y-axis label to the column name when there's a single series.
def default-ylabel [y: list<string>]: any -> any {
    let yl = $in
    if ($yl != null) { $yl } else if (($y | length) == 1) { $y | first } else { null }
}

def appearance [
    title: any, xlabel: any, ylabel: any,
    xrange: any, yrange: any,
    width: int, height: int,
    grid: bool, no_legend: bool,
    logx: bool, logy: bool,
    legend_pos: any,
    xformat: any, yformat: any,
    n_series: int,
]: nothing -> record {
    {
        title: $title
        xlabel: $xlabel
        ylabel: $ylabel
        xrange: $xrange
        yrange: $yrange
        width: $width
        height: $height
        grid: $grid
        # A one-series legend is just noise, so only show it for 2+ series.
        legend: ((not $no_legend) and ($n_series > 1))
        legend_pos: $legend_pos
        logx: $logx
        logy: $logy
        xformat: $xformat
        yformat: $yformat
    }
}
