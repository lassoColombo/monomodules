# Plot — a Nushell wrapper around a Vega-Lite renderer (via the `vl-convert` CLI).
#
# Each data subcommand consumes a table (`list<record>`) on stdin, builds a
# Vega-Lite spec, and renders it to an image via the native `vl-convert` CLI
# (see `vega.nu`). The image is then drawn directly in this terminal using the
# kitty graphics protocol (see `term.nu`) — no external viewer, no window.
#
# Public surface:
#   plot line       — one or more y-series vs x, with optional curve smoothing
#   plot area       — filled bands: stacked, overlaid, normalized or streamgraph
#   plot step       — step function (pre/post/mid)
#   plot impulses   — vertical sticks
#   plot trail      — a line whose width varies along its length
#   plot scatter    — points
#   plot bubble     — points with a third value in the marker area
#   plot text       — labels at x/y; with --points, an annotated scatter
#   plot bar        — categorical x, clustered / stacked / normalized y
#   plot pie        — one slice per category, optionally a donut
#   plot heatmap    — a grid of cells coloured by a value
#   plot histogram  — distribution of a single numeric column
#   plot boxplot    — quartile box, whiskers and outliers per category
#   plot strip      — every observation as a tick, optionally jittered
#   plot errorbar   — a central value with error bars or a shaded band
#
# Common conventions:
#   • `--x-axis`/`-x` selects the x column; `--y` is a list of y columns.
#   • Wide input by default (each `--y` column is a series). Pass `--series <col>`
#     for long/tidy input instead: one `--y` value column plus a column whose values
#     name the series — so grouped data pipes in without a manual pivot. The
#     folded-series marks are line, area, step, impulses, trail, scatter and bar;
#     the rest take one column per role instead (`--col`, `--value`, `--label`).
#   • The distribution and grid commands (histogram, boxplot, strip, heatmap, pie)
#     aggregate for you — raw rows in, no pre-grouping step.
#   • With no flags the chart is drawn in the terminal, sized to the pane.
#     `--out <path>` writes an image file instead (png, jpg, svg, pdf, html by
#     extension) and never opens it.
#   • `--xformat`/`--yformat` take d3-format specs (e.g. ".2f", "$,.0f", "%").
#   • Set `$env.PLOT_DEBUG = "/tmp/plot.vl.json"` to dump the generated
#     Vega-Lite spec for inspection.
#
#   • $env.PLOT_SIZE ("100x24") overrides the inline size, in terminal cells;
#     $env.PLOT_CELL_PX ("20x53") overrides the measured cell size in pixels;
#     $env.PLOT_FONT_SCALE ("2.5") overrides how much text is enlarged. Text is
#     sized in the device pixels a chart is rendered at, so inline charts scale
#     it from the measured cell — a HiDPI pane would otherwise show ~5pt labels.
#
# Requires the `vl-convert` CLI on PATH (https://github.com/vega/vl-convert) and
# a terminal that speaks the kitty graphics protocol (Ghostty, kitty, or
# zellij 0.45+ running on one).

use ./complete.nu
use ./theme.nu
use ./validate.nu
use ./vega.nu

# Line plot of one or more y-series against x.
#
# The x column may be numeric, datetime, or categorical (string). Multiple y
# columns are drawn as overlaid series sharing the same x axis. `--smooth`
# interpolates the curve through the points (e.g. monotone, basis, cardinal).
#
# `--series <col>` takes LONG/tidy input instead of wide: each distinct value of
# that column is drawn as its own line, with the single `--y` column as the value —
# no manual pivot. So `hits --field level` (rows of {time, level, hits}) plots as
# `plot line -x time --series level --y [hits]`.
@category plot
@search-terms plot line chart timeseries series long tidy
@example "Sine wave, drawn in the terminal" {
    seq 0 60 | each {|i| {x: $i, y: ($i * 0.1 | math sin)}} | plot line -x x --y [y]
}
@example "Long/tidy input: one line per series value, no pivot" {
    [[t, sensor, v]; [0, a, 1], [0, b, 4], [1, a, 2], [1, b, 3], [2, a, 5], [2, b, 2]]
    | plot line -x t --series sensor --y [v] --title "two sensors" --grid --out /tmp/plot-series.png
}
@example "Two series, written to a file instead" {
    seq 1 20
    | each {|i| {t: $i, a: ($i * $i), b: ($i * 3)}}
    | plot line -x t --y [a b] --title "quadratic vs linear" --grid --out /tmp/plot-line.png
}
@example "Smoothed line with custom labels" {
    seq 1 30
    | each {|i| {x: $i, y: ($i + (random float (-3)..3))}}
    | plot line -x x --y [y] --smooth monotone --xlabel step --ylabel value --out /tmp/plot-smooth.png
}
export def line [
    --x-axis (-x): string,                          # x column (required)
    --y: list<string>,                              # y columns (wide); with --series, the single value column
    --series: string,                               # long input: column whose values name each series
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
    --out (-o): path,                               # write an image file instead of drawing (format from extension)
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot line" "--x-axis" $x_axis
    let s = (series-shape "plot line" $data $x_axis $y $series)

    let interp = smooth-interp $smooth
    let mark = if ($interp == null) { "line" } else { {type: "line", interpolate: $interp} }

    vega {
        data: $data
        mark: $mark
        transform: $s.transform
        encoding: {
            x: {field: $x_axis, type: (col-type $data $x_axis)}
            y: {field: $s.value_field, type: "quantitative"}
            color: {field: $s.series_field, type: "nominal", title: null}
        }
        x_channel: "x"
        y_channel: "y"
        appearance: (appearance $title $xlabel ($ylabel | default-ylabel $y) $xrange $yrange $width $height $grid $no_legend $logx $logy $legend_pos $xformat $yformat $s.n_series)
        out: $out
    }
}

# Scatter plot of one or more y-series against x.
#
# `--shape` picks the marker (see `complete point-shape`) and `--point-size`
# scales it. `--series <col>` takes long/tidy input (one point-series per distinct
# value of that column, the single `--y` as the value) instead of wide `--y` columns.
@category plot
@search-terms plot scatter points marker series long tidy
@example "Random cloud, drawn in the terminal" {
    seq 1 200 | each {|_| {x: (random float (-5)..5), y: (random float (-5)..5)}} | plot scatter -x x --y [y]
}
@example "Two series with grid, written to a file" {
    seq 1 50
    | each {|i| {i: $i, a: (random float 0..10), b: (random float 5..15)}}
    | plot scatter -x i --y [a b] --grid --shape diamond --point-size 1.4 --out /tmp/plot-scatter.png
}
export def scatter [
    --x-axis (-x): string,                          # x column (required)
    --y: list<string>,                              # y columns (wide); with --series, the single value column
    --series: string,                               # long input: column whose values name each series
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
    --out (-o): path,                               # write an image file instead of drawing (format from extension)
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot scatter" "--x-axis" $x_axis
    let s = (series-shape "plot scatter" $data $x_axis $y $series)

    vega {
        data: $data
        mark: {type: "point", shape: $shape, size: ($point_size * 40 | math round), filled: true}
        transform: $s.transform
        encoding: {
            x: {field: $x_axis, type: (col-type $data $x_axis)}
            y: {field: $s.value_field, type: "quantitative"}
            color: {field: $s.series_field, type: "nominal", title: null}
        }
        x_channel: "x"
        y_channel: "y"
        appearance: (appearance $title $xlabel ($ylabel | default-ylabel $y) $xrange $yrange $width $height $grid $no_legend $logx $logy $legend_pos $xformat $yformat $s.n_series)
        out: $out
    }
}

# Bar plot of one or more y-series against x.
#
# The x column is treated as categorical. `--style` chooses the layout:
#   clustered  → side-by-side bars per category (default)
#   stacked    → bars stacked by series
#   normalized → stacked to 100% (relative share)
#
# `--series <col>` takes long/tidy input (one series per distinct value of that
# column, the single `--y` as the value) instead of wide `--y` columns — so a
# grouped `stats --long` result stacks without a manual pivot.
@category plot
@search-terms plot bar column clustered stacked normalized series long tidy
@example "Clustered bars from a small categorical table" {
    [
        {fruit: apple,  q1: 12, q2: 18}
        {fruit: pear,   q1: 7,  q2: 9}
        {fruit: banana, q1: 20, q2: 15}
    ] | plot bar -x fruit --y [q1 q2] --title "fruit sales" --grid
}
@example "Stacked bars, written to a file" {
    seq 1 6
    | each {|i| {label: $"day-($i)", reads: ($i * 10), writes: ($i * 4)}}
    | plot bar -x label --y [reads writes] --style stacked --out /tmp/plot-bar.png
}
export def bar [
    --x-axis (-x): string,                          # x column (required) — used as bar label
    --y: list<string>,                              # y columns (wide); with --series, the single value column
    --series: string,                               # long input: column whose values name each series
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
    --out (-o): path,                               # write an image file instead of drawing (format from extension)
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot bar" "--x-axis" $x_axis
    let s = (series-shape "plot bar" $data $x_axis $y $series)

    let y_ch = match $style {
        "clustered" => {field: $s.value_field, type: "quantitative", stack: null}
        "stacked" => {field: $s.value_field, type: "quantitative", stack: true}
        "normalized" => {field: $s.value_field, type: "quantitative", stack: "normalize"}
        _ => { error make {msg: $"plot bar: unknown --style '($style)'; use one of: (complete bar-style | str join ', ')"} }
    }
    let enc_base = {
        x: {field: $x_axis, type: "nominal"}
        y: $y_ch
        color: {field: $s.series_field, type: "nominal", title: null}
    }
    let enc = if $style == "clustered" {
        $enc_base | insert xOffset {field: $s.series_field, type: "nominal"}
    } else { $enc_base }

    # Normalized bars read as percentages unless the user forces a y format.
    let yfmt = if ($yformat == null) and ($style == "normalized") { "%" } else { $yformat }

    vega {
        data: $data
        mark: "bar"
        transform: $s.transform
        encoding: $enc
        x_channel: "x"
        y_channel: "y"
        appearance: (appearance $title $xlabel ($ylabel | default-ylabel $y) $xrange $yrange $width $height $grid $no_legend $logx $logy $legend_pos $xformat $yfmt $s.n_series)
        out: $out
    }
}

# Histogram of a single numeric column's distribution.
#
# Values are binned into ~`--bins` equal-width buckets. With `--normalize` the
# y axis shows relative frequency (bucket count / N) instead of raw counts.
@category plot
@search-terms plot histogram distribution density
@example "Normal-ish distribution, drawn in the terminal" {
    seq 1 500
    | each {|_| {v: ((random float (-1)..1) + (random float (-1)..1) + (random float (-1)..1))}}
    | plot histogram --col v --bins 40
}
@example "Normalized histogram, written to a file" {
    seq 1 1000
    | each {|_| {x: (random float 0..10)}}
    | plot histogram --col x --bins 25 --normalize --title "uniform[0,10]" --out /tmp/plot-hist.png
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
    --out (-o): path,                               # write an image file instead of drawing (format from extension)
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
    }
}

# Step plot of one or more y-series against x.
#
# `--where` controls where the step happens between two samples:
#   pre  → step before the point  (Vega "step-before"; default)
#   post → step after the point   (Vega "step-after")
#   mid  → step at the midpoint    (Vega "step")
#
# `--series <col>` takes long/tidy input (one step per distinct value of that
# column, the single `--y` as the value) instead of wide `--y` columns.
@category plot
@search-terms plot step staircase piecewise series long tidy
@example "Staircase signal, drawn in the terminal" {
    [
        {t: 0, level: 0}
        {t: 1, level: 1}
        {t: 2, level: 1}
        {t: 3, level: 3}
        {t: 4, level: 2}
        {t: 5, level: 2}
    ] | plot step -x t --y [level] --grid
}
@example "Mid-step variant, written to a file" {
    seq 1 12
    | each {|i| {x: $i, y: (($i mod 3) + 1)}}
    | plot step -x x --y [y] --where mid --out /tmp/plot-step.png
}
export def step [
    --x-axis (-x): string,                          # x column (required)
    --y: list<string>,                              # y columns (wide); with --series, the single value column
    --series: string,                               # long input: column whose values name each series
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
    --out (-o): path,                               # write an image file instead of drawing (format from extension)
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot step" "--x-axis" $x_axis
    let s = (series-shape "plot step" $data $x_axis $y $series)

    vega {
        data: $data
        mark: {type: "line", interpolate: (step-interp $where)}
        transform: $s.transform
        encoding: {
            x: {field: $x_axis, type: (col-type $data $x_axis)}
            y: {field: $s.value_field, type: "quantitative"}
            color: {field: $s.series_field, type: "nominal", title: null}
        }
        x_channel: "x"
        y_channel: "y"
        appearance: (appearance $title $xlabel ($ylabel | default-ylabel $y) $xrange $yrange $width $height $grid $no_legend $logx $logy $legend_pos $xformat $yformat $s.n_series)
        out: $out
    }
}

# Impulse plot: vertical sticks from y=0 to each y value.
#
# Good for sparse spikes (counts, deltas) where lines or bars would be noisy.
# `--linewidth` controls stick thickness. `--series <col>` takes long/tidy input
# (one stick-series per distinct value of that column, the single `--y` as the
# value) instead of wide `--y` columns.
@category plot
@search-terms plot impulses sticks spikes lollipop series long tidy
@example "Sparse spikes, drawn in the terminal" {
    seq 1 25
    | each {|i| {x: $i, hits: (if (random int 0..4) == 0 { random int 1..10 } else { 0 })}}
    | plot impulses -x x --y [hits] --grid
}
@example "Thicker sticks, written to a file" {
    seq 1 15
    | each {|i| {i: $i, v: ($i mod 5)}}
    | plot impulses -x i --y [v] --linewidth 4 --out /tmp/plot-impulses.png
}
export def impulses [
    --x-axis (-x): string,                          # x column (required)
    --y: list<string>,                              # y columns (wide); with --series, the single value column
    --series: string,                               # long input: column whose values name each series
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
    --out (-o): path,                               # write an image file instead of drawing (format from extension)
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot impulses" "--x-axis" $x_axis
    let s = (series-shape "plot impulses" $data $x_axis $y $series)

    vega {
        data: $data
        mark: {type: "rule", size: $linewidth}
        transform: $s.transform
        encoding: {
            x: {field: $x_axis, type: (col-type $data $x_axis)}
            y: {field: $s.value_field, type: "quantitative"}
            y2: {datum: 0}
            color: {field: $s.series_field, type: "nominal", title: null}
        }
        x_channel: "x"
        y_channel: "y"
        appearance: (appearance $title $xlabel ($ylabel | default-ylabel $y) $xrange $yrange $width $height $grid $no_legend $logx $logy $legend_pos $xformat $yformat $s.n_series)
        out: $out
    }
}

# Area plot of one or more y-series against x.
#
# `--style` picks how the bands relate to each other:
#   stacked    → bands sum on top of one another (default)
#   overlay    → every band sits on the same baseline, drawn semi-transparent
#   normalized → stacked to 100% (relative share)
#   stream     → stacked and centred on the baseline (streamgraph)
#
# `--outline` traces the top edge of each band and `--smooth` interpolates it.
# `--series <col>` takes long/tidy input (one band per distinct value of that
# column, the single `--y` as the value) instead of wide `--y` columns.
@category plot
@search-terms plot area stacked streamgraph filled band series long tidy
@example "Stacked area, drawn in the terminal" {
    seq 1 24
    | each {|i| {h: $i, cpu: (random int 10..40), io: (random int 5..20)}}
    | plot area -x h --y [cpu io] --title "load by hour" --grid
}
@example "Overlaid semi-transparent bands, written to a file" {
    seq 1 30
    | each {|i| {t: $i, a: ($i * 2), b: (60 - $i)}}
    | plot area -x t --y [a b] --style overlay --smooth monotone --out /tmp/plot-area.png
}
@example "Streamgraph from long/tidy input" {
    seq 0 20
    | each {|i| [{t: $i, k: read, v: (random int 1..9)}, {t: $i, k: write, v: (random int 1..9)}]}
    | flatten
    | plot area -x t --series k --y [v] --style stream --out /tmp/plot-stream.png
}
export def area [
    --x-axis (-x): string,                          # x column (required)
    --y: list<string>,                              # y columns (wide); with --series, the single value column
    --series: string,                               # long input: column whose values name each series
    --style: string@"complete area-style" = "stacked",  # stacked, overlay, normalized, or stream
    --smooth: string@"complete smooth" = "none",    # curve interpolation (see `complete smooth`)
    --opacity: float,                               # band opacity (default 1, or 0.55 for --style overlay)
    --outline,                                      # trace the top edge of each band
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
    --out (-o): path,                               # write an image file instead of drawing (format from extension)
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot area" "--x-axis" $x_axis
    let s = (series-shape "plot area" $data $x_axis $y $series)

    let stack = match $style {
        "stacked" => true
        "overlay" => null
        "normalized" => "normalize"
        "stream" => "center"
        _ => { error make {msg: $"plot area: unknown --style '($style)'; use one of: (complete area-style | str join ', ')"} }
    }

    let interp = smooth-interp $smooth
    mut mark = {type: "area", opacity: ($opacity | default (if $style == "overlay" { 0.55 } else { 1.0 }))}
    if ($interp != null) { $mark = ($mark | insert interpolate $interp) }
    if $outline { $mark = ($mark | insert line true) }

    # Normalized bands read as percentages unless the user forces a y format.
    let yfmt = if ($yformat == null) and ($style == "normalized") { "%" } else { $yformat }

    vega {
        data: $data
        mark: $mark
        transform: $s.transform
        encoding: {
            x: {field: $x_axis, type: (col-type $data $x_axis)}
            y: {field: $s.value_field, type: "quantitative", stack: $stack}
            color: {field: $s.series_field, type: "nominal", title: null}
        }
        x_channel: "x"
        y_channel: "y"
        appearance: (appearance $title $xlabel ($ylabel | default-ylabel $y) $xrange $yrange $width $height $grid $no_legend $logx $logy $legend_pos $xformat $yfmt $s.n_series)
        out: $out
    }
}

# Heatmap: a grid of cells coloured by a value.
#
# `--x-axis` and `--y-axis` name the two grouping columns (the grid's columns and
# rows); `--value` is the numeric column that colours each cell. Rows landing in
# the same cell are combined with `--agg` (sum by default) — so raw event rows
# heatmap without a pre-aggregation step. Drop `--value` to colour cells by row
# count instead.
#
# Cells are discrete: numeric axes are treated as ordinal (one column per
# distinct value), not binned. `--labels` prints each cell's value on it, in a
# colour picked per cell so it stays readable at both ends of the ramp.
@category plot
@search-terms plot heatmap rect matrix grid density crosstab
@example "Hour-of-day by weekday activity, drawn in the terminal" {
    ["mon" "tue" "wed" "thu" "fri"]
    | each {|d| 0..23 | each {|h| {day: $d, hour: $h, hits: (random int 0..100)}}}
    | flatten
    | plot heatmap -x hour -y day --value hits --title "hits by hour"
}
@example "Labelled confusion matrix, written to a file" {
    [
        {actual: cat, predicted: cat,  n: 42}
        {actual: cat, predicted: dog,  n: 3}
        {actual: dog, predicted: cat,  n: 7}
        {actual: dog, predicted: dog,  n: 38}
    ] | plot heatmap -x predicted -y actual --value n --labels --out /tmp/plot-heatmap.png
}
@example "Cell = row count, no value column" {
    seq 1 400
    | each {|_| {a: (["x" "y" "z"] | get (random int 0..2)), b: (["p" "q"] | get (random int 0..1))}}
    | plot heatmap -x a -y b --labels --out /tmp/plot-counts.png
}
export def heatmap [
    --x-axis (-x): string,                          # column for the grid's columns (required)
    --y-axis (-y): string,                          # column for the grid's rows (required)
    --value (-v): string,                           # numeric column to colour by (default: row count)
    --agg: string@"complete agg" = "sum",           # how to combine rows sharing a cell
    --scheme: string@"complete color-scheme",       # Vega color scheme (default: the plot theme's ramp)
    --labels,                                       # print each cell's value on it
    --title (-t): string,                           # plot title
    --xlabel: string,                               # x-axis label
    --ylabel: string,                               # y-axis label
    --width: int = 800,                             # plotting-area width in px
    --height: int = 600,                            # plotting-area height in px
    --no-legend,                                    # hide the colour legend
    --legend-pos: string@"complete legend-pos",     # legend position, e.g. "top-right"
    --vformat: string,                              # d3-format spec for the legend + cell labels
    --out (-o): path,                               # write an image file instead of drawing (format from extension)
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot heatmap" "--x-axis" $x_axis
    require-flag "plot heatmap" "--y-axis" $y_axis
    $data | validate assert columns [$x_axis $y_axis] | ignore
    if ($value != null) {
        $data | validate assert columns [$value] | ignore
        $data | validate assert numeric $value | ignore
    }

    # Aggregate here rather than in the color channel: the cell value needs a
    # name (`__v`) so the label layer can both print it and test it to choose a
    # readable text colour.
    let op = if ($value == null) { {op: "count", as: "__v"} } else { {op: $agg, field: $value, as: "__v"} }
    let tf = [
        {aggregate: [$op], groupby: [$x_axis $y_axis]}
        {joinaggregate: [{op: "min", field: "__v", as: "__lo"} {op: "max", field: "__v", as: "__hi"}]}
        {calculate: "datum.__hi == datum.__lo ? 1 : (datum.__v - datum.__lo) / (datum.__hi - datum.__lo)", as: "__norm"}
    ]

    mut color = {field: "__v", type: "quantitative", title: ($value | default "count")}
    if ($scheme != null) { $color = ($color | insert scale {scheme: $scheme}) }
    if ($vformat != null) { $color = ($color | insert legend {format: $vformat}) }

    let layers = if $labels {
        let t = theme
        let fmt = if ($vformat != null) { $vformat } else if ($value == null) { "d" } else { ".3~f" }
        # A closure, so the cell text scales with the pane exactly like the axis
        # text does — a fixed size would leave it conspicuously smaller.
        {|a| [
            {mark: "rect"}
            {
                mark: {type: "text", fontSize: (11 * $a.font_scale), fontWeight: 600}
                encoding: {
                    text: {field: "__v", type: "quantitative", format: $fmt}
                    # Cream on the dark end of the ramp, ink on the bright end.
                    # The ramp turns light early (lavender sits at its midpoint),
                    # so the flip is well below 0.5.
                    color: {condition: {test: "datum.__norm > 0.38", value: $t.bg}, value: $t.text}
                }
            }
        ] }
    } else { null }

    vega {
        data: $data
        mark: "rect"
        layers: $layers
        transform: $tf
        encoding: {
            x: (cell-channel $data $x_axis)
            y: (cell-channel $data $y_axis)
            color: $color
        }
        x_channel: "x"
        y_channel: "y"
        # The colour legend IS the value scale here, so it stays unless refused.
        appearance: (appearance $title $xlabel $ylabel null null $width $height false $no_legend false false $legend_pos null null 2)
        out: $out
    }
}

# Pie (or donut) chart of one value per category.
#
# `--label` names the category column and `--value` the numeric column; rows
# sharing a category are combined with `--agg` (sum by default). Drop `--value`
# to size slices by row count instead.
#
# `--donut` cuts a hole in the middle (`--hole` sets its size as a fraction of
# the radius). Slices run alphabetically by category unless `--sort` puts the
# largest first.
#
# Two flags write text just outside the ring, and they compose:
#   --render-values  → each slice's value (a share of the total, with `--percent`)
#   --render-labels  → each slice's category
# Together, the category sits above its value. The ring shrinks to make room, so
# a `--title` and long category names still fit.
#
# Text is placed radially, which means adjacent thin slices crowd each other. So
# a slice is labelled only when its own arc is long enough to hold its own text —
# measured per slice, against the ring's actual size, so a short name on a thin
# slice still gets one. The rest are named by the legend alone. `--min-share`
# replaces that rule with a flat fraction of the total, `--min-share 0` labels
# every slice however thin, and `--font-size` scales the text.
@category plot
@search-terms plot pie donut arc share proportion breakdown render values labels
@example "Share of disk by file type, drawn in the terminal" {
    ls | where type == file | plot pie --label name --value size --sort
}
@example "Filename above its size on every slice" {
    ls | where type == file | plot pie --label name --value size --donut --render-values --render-labels
}
@example "Donut with percentage labels, written to a file" {
    [
        {browser: chrome,  users: 640}
        {browser: safari,  users: 210}
        {browser: firefox, users: 95}
        {browser: other,   users: 55}
    ] | plot pie -l browser -v users --donut --render-values --percent --title "market share" --out /tmp/plot-donut.png
}
@example "Slices sized by row count, no value column" {
    ls | plot pie --label type --render-values --render-labels --out /tmp/plot-types.png
}
export def pie [
    --label (-l): string,                           # category column (required) — one slice per value
    --value (-v): string,                            # numeric column to size slices by (default: row count)
    --agg: string@"complete agg" = "sum",           # how to combine rows sharing a category
    --donut,                                        # cut a hole in the middle
    --hole: float,                                  # hole size as a fraction of the radius (implies --donut)
    --render-values,                                # print each slice's value outside the ring
    --render-labels,                                # print each slice's category outside the ring
    --percent,                                      # values read as a share of the total instead of the raw number
    --min-share: float,                             # unlabel slices below this share of the total (default: whatever the ring geometry allows; 0 labels all)
    --font-size: float = 1.0,                       # scale the text drawn around the ring
    --sort,                                         # order slices largest-first
    --title (-t): string,                           # plot title
    --width: int = 800,                             # plotting-area width in px
    --height: int = 600,                            # plotting-area height in px
    --no-legend,                                    # hide the category legend
    --legend-pos: string@"complete legend-pos",     # legend position, e.g. "top-right"
    --vformat: string,                              # d3-format spec for the rendered values
    --out (-o): path,                               # write an image file instead of drawing (format from extension)
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot pie" "--label" $label
    $data | validate assert columns [$label] | ignore
    if ($value != null) {
        $data | validate assert columns [$value] | ignore
        $data | validate assert numeric $value | ignore
    }

    # One slice per category, so fold the rows down first — and carry the share
    # of the total along, for `--percent` labels.
    let op = if ($value == null) { {op: "count", as: "__v"} } else { {op: $agg, field: $value, as: "__v"} }
    let tf = [
        {aggregate: [$op], groupby: [$label]}
        {joinaggregate: [{op: "sum", field: "__v", as: "__total"}]}
        {calculate: "datum.__total == 0 ? 0 : datum.__v / datum.__total", as: "__share"}
    ]

    let frac = if ($hole != null) { $hole } else if $donut { 0.55 } else { 0.0 }
    if ($frac < 0) or ($frac >= 1) {
        error make {msg: $"plot pie: --hole must be in [0, 1), got ($frac)"}
    }

    let value_ch = if $percent {
        {field: "__share", type: "quantitative", format: ($vformat | default ".1%")}
    } else {
        {field: "__v", type: "quantitative", format: ($vformat | default (if ($value == null) { "d" } else { ".3~f" }))}
    }
    let label_ch = {field: $label, type: "nominal"}
    let fg = (theme).text

    # How much of the shorter side the ring may claim. Text outside it needs the
    # rest, and category names run longer than formatted numbers.
    let radius_frac = if $render_labels { 0.68 } else if $render_values { 0.76 } else { 0.94 }

    mut color = {field: $label, type: "nominal", title: null}
    if $sort { $color = ($color | insert sort {field: "__v", op: "sum", order: "descending"}) }
    # Slice order is set EXPLICITLY, not left to the stack default: the text
    # layers override `color` with a flat colour, and without an `order` channel
    # that alone is enough to make it stack differently from the arcs — putting
    # every label on the wrong slice.
    let order = if $sort {
        {field: "__v", type: "quantitative", sort: "descending"}
    } else {
        {field: $label, type: "nominal"}
    }
    let enc = {theta: {field: "__v", type: "quantitative", stack: true}, color: $color, order: $order}

    vega {
        data: $data
        # Radii are pixels, and inline drawing only settles the pixel size after
        # this spec is built — so hand the backend a closure over the final size.
        mark: {|a| arc-mark (arc-outer $a $radius_frac) $frac}
        layers: (if ($render_values or $render_labels) {
            {|a|
                let outer = arc-outer $a $radius_frac
                # Text is in device pixels, like the chart — so it scales with the
                # pane, and the gap and line spacing scale with the text.
                let size = 11 * $a.font_scale * $font_size
                let r = $outer + ($size * 0.8 | math round)
                let line = $size * 0.62
                let both = $render_values and $render_labels

                # Whether two neighbouring labels collide comes down to how much
                # of the circumference each one covers. Around the top and bottom
                # of the ring that is the text's WIDTH — the dominant term, and
                # the reason a share-based cutoff alone is not enough — while at
                # the sides it is its height. Take the larger, per slice, and
                # compare it against the arc that slice actually owns.
                let circ = 2 * 3.14159265 * $r
                let tall = (if $both { 2 } else { 1 }) * 1.25 * $size
                # `length()` is evaluated per row, so slices are judged on their
                # own name rather than the longest one in the table. 0.45em per
                # character is measured off rendered labels in Vega's default
                # sans, not guessed — at 0.58 the criterion rejects slices that
                # would in fact have fitted.
                let wide = if $render_labels {
                    $"length\('' + datum['($label)']) * 0.45 * ($size)"
                } else {
                    $"6 * 0.45 * ($size)"
                }
                let test = if ($min_share == null) {
                    $"datum.__share * ($circ) >= max\(($tall), ($wide))"
                } else if ($min_share > 0) {
                    $"datum.__share >= ($min_share)"
                } else { null }
                let vals = gate-text $value_ch $test
                let labs = gate-text $label_ch $test

                # Both kinds of text: the category rides above its value, each
                # nudged half a line off the shared radial position.
                let texts = if $both {
                    (arc-text $r $size $labs ($line * -1) $fg)
                    | append (arc-text $r $size $vals $line $fg)
                } else if $render_labels {
                    arc-text $r $size $labs null $fg
                } else {
                    arc-text $r $size $vals null $fg
                }
                [{mark: (arc-mark $outer $frac)}] | append $texts
            }
        } else { null })
        transform: $tf
        encoding: $enc
        appearance: (appearance $title null null null null $width $height false $no_legend false false $legend_pos null null 2)
        out: $out
    }
}

# Box plot of a numeric column's distribution: median, quartile box, whiskers
# and outlier points, computed for you.
#
# `--col` is the value column. With `--by` you get one box per distinct value of
# that column, and `--series` splits each of those into side-by-side boxes.
#
# `--extent` sets how far the whiskers reach: "1.5" or "3" for that multiple of
# the interquartile range (points beyond are drawn as outliers), or "min-max" to
# stretch to the extremes and draw none.
#
# Boxes stand vertically — categories along x, values up y — unless `--horizontal`
# turns them on their side. The axis flags always name the AXIS, not the role, so
# `--ylabel` labels the value axis when upright and the category axis when not.
@category plot
@search-terms plot boxplot box whisker quartile distribution iqr outlier
@example "Latency distribution per endpoint, drawn in the terminal" {
    ["/api" "/login" "/static"]
    | each {|e| 1..80 | each {|_| {route: $e, ms: (random int 5..400)}}}
    | flatten
    | plot boxplot --col ms --by route --title "latency by route" --grid
}
@example "One box for the whole column" {
    seq 1 300 | each {|_| {v: (random float 0..1)}} | plot boxplot -c v --out /tmp/plot-box.png
}
@example "Split each category in two, whiskers out to the extremes" {
    ["mon" "tue" "wed"]
    | each {|d| ["cold" "warm"] | each {|k| 1..40 | each {|_| {day: $d, cache: $k, ms: (random int 1..90)}}}}
    | flatten | flatten
    | plot boxplot -c ms --by day --series cache --extent min-max --horizontal --out /tmp/plot-box2.png
}
export def boxplot [
    --col (-c): string,                             # numeric column whose distribution to draw (required)
    --by: string,                                   # category column — one box per distinct value
    --series: string,                               # second grouping: side-by-side boxes, coloured
    --extent: string@"complete box-extent" = "1.5", # whisker reach: 1.5, 3 (× IQR) or min-max
    --horizontal (-H),                              # lay the boxes out sideways
    --box-width: float,                             # box thickness in px
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
    --out (-o): path,                               # write an image file instead of drawing (format from extension)
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot boxplot" "--col" $col
    $data | validate assert columns [$col] | ignore
    $data | validate assert numeric $col | ignore
    for c in ([$by $series] | compact) { $data | validate assert columns [$c] | ignore }

    # A lone box gets a width: with no category axis to divide up, Vega-Lite's
    # default leaves a hairline box floating in an empty canvas.
    let bw = if ($box_width != null) { $box_width } else if ($by == null) { 60.0 } else { null }
    mut mark = {type: "boxplot", extent: (box-extent $extent)}
    if ($bw != null) { $mark = ($mark | insert size $bw) }

    let val = {field: $col, type: "quantitative"}
    let cat = if ($by != null) { {field: $by, type: "nominal"} } else { null }
    let val_ch = if $horizontal { "x" } else { "y" }
    let cat_ch = if $horizontal { "y" } else { "x" }

    mut enc = {} | insert $val_ch $val
    if ($cat != null) { $enc = ($enc | insert $cat_ch $cat) }
    if ($series != null) {
        $enc = ($enc | insert color {field: $series, type: "nominal", title: null})
        # Side by side rather than on top of each other, but only when there is
        # a category axis to offset along.
        if ($cat != null) {
            $enc = ($enc | insert (if $horizontal { "yOffset" } else { "xOffset" }) {field: $series, type: "nominal"})
        }
    }
    let n_series = if ($series == null) { 1 } else { $data | get $series | uniq | length }

    vega {
        data: $data
        mark: $mark
        encoding: $enc
        x_channel: "x"
        y_channel: "y"
        appearance: (appearance $title $xlabel ($ylabel | default (if $horizontal { $by } else { $col })) $xrange $yrange $width $height $grid $no_legend $logx $logy $legend_pos $xformat $yformat $n_series)
        out: $out
    }
}

# Error bars (or a shaded error band) around a central value.
#
# Two ways to feed it:
#   • RAW rows, several per x — the spread is computed for you, `--extent`
#     choosing what it measures: "ci" (95% confidence interval on the mean),
#     "stderr", "stdev", or "iqr".
#   • PRE-COMPUTED bounds — pass `--lo` and `--hi` and the columns are used as
#     they are, with `--y` as the centre.
#
# `--style band` shades the interval instead of drawing whiskers, which reads
# better over many x values. `--line` joins the centres, `--no-points` drops the
# centre markers, and `--caps` puts crossbars on the whisker ends.
@category plot
@search-terms plot errorbar errorband confidence interval stdev stderr ci variance uncertainty
@example "95% CI from repeated measurements, drawn in the terminal" {
    ["a" "b" "c" "d"]
    | each {|g| 1..30 | each {|_| {group: $g, score: (random float 0..10)}}}
    | flatten
    | plot errorbar -x group --y score --line --title "score by group" --grid
}
@example "Shaded band over a noisy time series, written to a file" {
    1..40
    | each {|i| 1..12 | each {|_| {t: $i, v: ($i + (random float (-6)..6))}}}
    | flatten
    | plot errorbar -x t --y v --style band --extent stdev --line --no-points --out /tmp/plot-band.png
}
@example "Pre-computed bounds" {
    [
        {day: mon, mean: 10, lo: 8,  hi: 13}
        {day: tue, mean: 14, lo: 11, hi: 18}
        {day: wed, mean: 9,  lo: 7,  hi: 10}
    ] | plot errorbar -x day --y mean --lo lo --hi hi --caps --out /tmp/plot-err.png
}
export def errorbar [
    --x-axis (-x): string,                          # x column (required)
    --y: string,                                    # centre value column (required)
    --lo: string,                                   # pre-computed lower bound column
    --hi: string,                                   # pre-computed upper bound column
    --extent: string@"complete error-extent" = "ci",  # what the interval measures, when --lo/--hi are absent
    --center: string@"complete agg",                # how to reduce raw rows to a centre (default: mean, or median for iqr)
    --style: string@"complete error-style" = "bar", # whiskers ("bar") or a shaded "band"
    --series: string,                               # colour grouping
    --line,                                         # join the centres with a line
    --no-points,                                    # hide the centre markers
    --caps,                                         # crossbars on the whisker ends (--style bar only)
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
    --out (-o): path,                               # write an image file instead of drawing (format from extension)
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot errorbar" "--x-axis" $x_axis
    require-flag "plot errorbar" "--y" $y
    if (($lo == null) != ($hi == null)) {
        error make {msg: "plot errorbar: --lo and --hi go together — pass both, or neither to compute the interval from the rows"}
    }
    let explicit = ($lo != null)
    $data | validate assert columns ([$x_axis $y] | append ([$lo $hi $series] | compact)) | ignore
    for c in ([$y $lo $hi] | compact) { $data | validate assert numeric $c | ignore }

    let interval_mark = match $style {
        # Caps need an explicit size: left to Vega-Lite they span the whole
        # category band, reading as full-width rules across the chart.
        "bar" => (if $caps { {type: "errorbar", ticks: {size: 14}} } else { {type: "errorbar"} })
        "band" => {type: "errorband", borders: true}
        _ => { error make {msg: $"plot errorbar: unknown --style '($style)'; use one of: (complete error-style | str join ', ')"} }
    }
    # `extent` only means something when the mark is doing the aggregating.
    let interval_mark = if $explicit { $interval_mark } else { $interval_mark | insert extent $extent }

    # Raw rows need reducing to one centre per x; pre-computed rows already are
    # one per x, so they inherit the shared y untouched.
    let centre = if $explicit { null } else {
        {field: $y, type: "quantitative", aggregate: ($center | default (if $extent == "iqr" { "median" } else { "mean" }))}
    }
    let centre_enc = if ($centre == null) { {} } else { {encoding: {y: $centre}} }

    let layers = [
        ({mark: $interval_mark} | merge (if $explicit { {encoding: {y: {field: $lo, type: "quantitative"}, y2: {field: $hi}}} } else { {} }))
    ]
    | append (if $line { [({mark: {type: "line"}} | merge $centre_enc)] } else { [] })
    | append (if $no_points { [] } else { [({mark: {type: "point", size: 45, filled: true}} | merge $centre_enc)] })

    let xt = col-type $data $x_axis
    mut enc = {
        x: {field: $x_axis, type: $xt}
        y: {field: $y, type: "quantitative"}
    }
    if ($series != null) {
        $enc = ($enc | insert color {field: $series, type: "nominal", title: null})
        # Nudge whiskers apart so series do not hide behind each other. Only over
        # a category axis: a continuous x has no band to offset within, and bands
        # are meant to overlap anyway.
        if ($xt == "nominal") and ($style == "bar") {
            $enc = ($enc | insert xOffset {field: $series, type: "nominal"})
        }
    }
    let n_series = if ($series == null) { 1 } else { $data | get $series | uniq | length }

    vega {
        data: $data
        layers: $layers
        encoding: $enc
        x_channel: "x"
        y_channel: "y"
        appearance: (appearance $title $xlabel ($ylabel | default $y) $xrange $yrange $width $height $grid $no_legend $logx $logy $legend_pos $xformat $yformat $n_series)
        out: $out
    }
}

# Text plot: each row's label printed at its x/y position.
#
# On its own this is a labelled map of the data — country names, host names,
# commit hashes — placed where a scatter would put dots. With `--points` it
# becomes an ANNOTATED SCATTER: markers plus their labels, nudged clear of the
# marker by `--dy`.
#
# The label column can hold anything; numbers are formatted with `--lformat`.
@category plot
@search-terms plot text label annotate annotated scatter callout name
@example "Annotated scatter of releases, drawn in the terminal" {
    [
        {version: "1.0", size: 12, users: 40}
        {version: "1.1", size: 15, users: 95}
        {version: "2.0", size: 31, users: 210}
    ] | plot text -x size -y users --label version --points --title "adoption vs size"
}
@example "Label-only map, written to a file" {
    ls | first 12 | plot text -x size -y modified --label name --out /tmp/plot-text.png
}
@example "Labels coloured by series" {
    [
        {x: 1, y: 3, name: alpha, team: red}
        {x: 2, y: 5, name: beta,  team: blue}
        {x: 3, y: 2, name: gamma, team: red}
    ] | plot text -x x -y y --label name --series team --points --out /tmp/plot-anno.png
}
export def text [
    --x-axis (-x): string,                          # x column (required)
    --y-axis (-y): string,                          # y column (required)
    --label (-l): string,                           # column holding the text to print (required)
    --series: string,                               # colour grouping
    --points,                                       # draw a marker under each label
    --shape: string@"complete point-shape" = "circle",  # marker shape, with --points
    --point-size: float = 1.0,                      # marker size multiplier, with --points
    --font-size: float = 1.0,                       # label size, as a multiple of the base 11px
    --angle: float,                                 # rotate the labels, in degrees
    --dx: float,                                    # nudge the labels sideways, in px
    --dy: float,                                    # nudge the labels vertically, in px (default: clear of the marker, with --points)
    --lformat: string,                              # d3-format spec for numeric labels
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
    --out (-o): path,                               # write an image file instead of drawing (format from extension)
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot text" "--x-axis" $x_axis
    require-flag "plot text" "--y-axis" $y_axis
    require-flag "plot text" "--label" $label
    $data | validate assert columns ([$x_axis $y_axis $label] | append ([$series] | compact)) | ignore

    let ltype = col-type $data $label
    mut text_ch = {field: $label, type: $ltype}
    if ($lformat != null) and ($lformat | is-not-empty) { $text_ch = ($text_ch | insert format $lformat) }

    # Unmarked labels ARE the data, so they take the series colours. With no
    # series to colour by they read better as plain annotation text.
    let text_enc = if ($series != null) { {text: $text_ch} } else { {text: $text_ch, color: {value: (theme).text}} }
    let point_layer = if $points {
        [{mark: {type: "point", shape: $shape, size: ($point_size * 40 | math round), filled: true}}]
    } else { [] }

    # A closure: the label size — and the nudge that lifts it clear of its
    # marker — are both in the device pixels the chart is rendered at.
    let layers = {|a|
        let size = 11 * $a.font_scale * $font_size
        let nudge = if ($dy != null) { $dy } else if $points { $size * -0.9 } else { null }
        let mark = {type: "text", fontSize: $size, fontWeight: 600}
            | merge (if ($angle != null) { {angle: $angle} } else { {} })
            | merge (if ($dx != null) { {dx: $dx} } else { {} })
            | merge (if ($nudge != null) { {dy: $nudge} } else { {} })
        $point_layer | append (haloed $mark $text_enc (theme).bg $size)
    }

    mut enc = {
        x: {field: $x_axis, type: (col-type $data $x_axis)}
        y: {field: $y_axis, type: (col-type $data $y_axis)}
    }
    if ($series != null) {
        # Here the series colour lands on TEXT, where the palette's darker
        # entries fall below a readable contrast — so the whole range is lifted
        # to a legibility floor. Done on the shared scale, not the text layer, so
        # the legend swatches and the markers keep matching the labels.
        $enc = ($enc | insert color {
            field: $series
            type: "nominal"
            title: null
            scale: {range: ((theme).series | each {|c| theme legible $c 0.55 })}
        })
    }
    let n_series = if ($series == null) { 1 } else { $data | get $series | uniq | length }

    vega {
        data: $data
        layers: $layers
        encoding: $enc
        x_channel: "x"
        y_channel: "y"
        appearance: (appearance $title $xlabel ($ylabel | default $y_axis) $xrange $yrange $width $height $grid $no_legend $logx $logy $legend_pos $xformat $yformat $n_series)
        out: $out
    }
}

# Strip plot: one short tick per row, at its value.
#
# Where a histogram bins and a box plot summarises, this shows every observation —
# so gaps, clusters and duplicates stay visible. `--by` splits the rows into one
# column of ticks per category, `--jitter` spreads overlapping rows sideways so a
# dense pile reads as a cloud rather than a single line.
#
# Values run up the y axis with categories along x, unless `--horizontal` turns
# the plot on its side.
@category plot
@search-terms plot strip tick rug jitter distribution swarm every point
@example "Every measurement per host, drawn in the terminal" {
    ["db" "web" "cache"]
    | each {|h| 1..60 | each {|_| {host: $h, ms: (random int 1..120)}}}
    | flatten
    | plot strip --col ms --by host --jitter --title "latency samples"
}
@example "One-dimensional rug of a single column" {
    seq 1 120 | each {|_| {v: (random float 0..1)}} | plot strip -c v --jitter --out /tmp/plot-strip.png
}
@example "Split by a second grouping, laid out sideways" {
    ["mon" "tue"]
    | each {|d| ["hit" "miss"] | each {|k| 1..40 | each {|_| {day: $d, kind: $k, ms: (random int 1..90)}}}}
    | flatten | flatten
    | plot strip -c ms --by day --series kind --horizontal --out /tmp/plot-strip2.png
}
export def strip [
    --col (-c): string,                             # numeric column to spread out (required)
    --by: string,                                   # category column — one strip per distinct value
    --series: string,                               # colour grouping
    --jitter,                                       # spread overlapping rows across the strip
    --horizontal (-H),                              # lay the strips out sideways
    --thickness: float = 2.0,                       # tick line weight
    --tick-size: float,                             # tick length in px
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
    --out (-o): path,                               # write an image file instead of drawing (format from extension)
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot strip" "--col" $col
    $data | validate assert columns ([$col] | append ([$by $series] | compact)) | ignore
    $data | validate assert numeric $col | ignore

    mut mark = {type: "tick", thickness: $thickness}
    if ($tick_size != null) { $mark = ($mark | insert size $tick_size) }

    let val_ch = if $horizontal { "x" } else { "y" }
    let cat_ch = if $horizontal { "y" } else { "x" }
    mut enc = {} | insert $val_ch {field: $col, type: "quantitative"}
    if ($by != null) { $enc = ($enc | insert $cat_ch {field: $by, type: "nominal"}) }
    if ($series != null) { $enc = ($enc | insert color {field: $series, type: "nominal", title: null}) }

    # Jitter is a random coordinate along the CATEGORY axis: an offset within the
    # band when there are categories, and the axis itself when there are none —
    # which is what turns a lone overplotted line into a readable cloud.
    if $jitter {
        if ($by != null) {
            $enc = ($enc | insert $"($cat_ch)Offset" {field: "__j", type: "quantitative"})
        } else {
            $enc = ($enc | insert $cat_ch {field: "__j", type: "quantitative", axis: null})
        }
    }
    # The jitter axis carries no meaning, so keep the appearance flags off it.
    let jitter_axis = $jitter and ($by == null)
    let n_series = if ($series == null) { 1 } else { $data | get $series | uniq | length }

    vega {
        data: $data
        mark: $mark
        transform: (if $jitter { [{calculate: "random()", as: "__j"}] } else { [] })
        encoding: $enc
        x_channel: (if ($jitter_axis and ($cat_ch == "x")) { null } else { "x" })
        y_channel: (if ($jitter_axis and ($cat_ch == "y")) { null } else { "y" })
        appearance: (appearance $title $xlabel ($ylabel | default (if $horizontal { $by } else { $col })) $xrange $yrange $width $height $grid $no_legend $logx $logy $legend_pos $xformat $yformat $n_series)
        out: $out
    }
}

# Trail: a line whose WIDTH varies along its length.
#
# The extra channel is worth it when the y value is not the only thing that
# matters — trade volume behind a price, sample count behind an average. By
# default the width follows the plotted value; `--size <col>` drives it from a
# different column instead, and `--max-width` caps the thickest point.
#
# `--series <col>` takes long/tidy input (one trail per distinct value of that
# column, the single `--y` as the value) instead of wide `--y` columns.
@category plot
@search-terms plot trail line width weighted volume tapered series long tidy
@example "Price with volume as thickness, drawn in the terminal" {
    seq 1 40
    | each {|i| {t: $i, price: (100 + ($i * 2) + (random float (-8)..8)), vol: (random int 1..500)}}
    | plot trail -x t --y [price] --size vol --title "price, weighted by volume"
}
@example "Width follows the value, written to a file" {
    seq 1 60
    | each {|i| {x: $i, y: (($i * 0.2 | math sin) * 10 + 12)}}
    | plot trail -x x --y [y] --smooth monotone --max-width 20 --out /tmp/plot-trail.png
}
export def trail [
    --x-axis (-x): string,                          # x column (required)
    --y: list<string>,                              # y columns (wide); with --series, the single value column
    --series: string,                               # long input: column whose values name each trail
    --size (-s): string,                            # column driving the width (default: the plotted value)
    --max-width: float = 12.0,                      # width in px at the largest value
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
    --xformat: string,                              # d3-format spec for x tics
    --yformat: string,                              # d3-format spec for y tics
    --out (-o): path,                               # write an image file instead of drawing (format from extension)
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot trail" "--x-axis" $x_axis
    let s = (series-shape "plot trail" $data $x_axis $y $series)
    if ($size != null) {
        $data | validate assert columns [$size] | ignore
        $data | validate assert numeric $size | ignore
    }

    let interp = smooth-interp $smooth
    mut mark = {type: "trail"}
    if ($interp != null) { $mark = ($mark | insert interpolate $interp) }

    vega {
        data: $data
        mark: $mark
        transform: $s.transform
        encoding: {
            x: {field: $x_axis, type: (col-type $data $x_axis)}
            y: {field: $s.value_field, type: "quantitative"}
            # The width is decoration, not a scale to read off — no legend.
            size: {field: ($size | default $s.value_field), type: "quantitative", scale: {range: [0 $max_width]}, legend: null}
            color: {field: $s.series_field, type: "nominal", title: null}
        }
        x_channel: "x"
        y_channel: "y"
        appearance: (appearance $title $xlabel ($ylabel | default-ylabel $y) $xrange $yrange $width $height $grid $no_legend $logx $logy $legend_pos $xformat $yformat $s.n_series)
        out: $out
    }
}

# Bubble chart: a scatter with a third value in the marker AREA.
#
# `--size` names that third column; bubbles are scaled between `--min-size` and
# `--max-size` (areas in px², so the eye compares them by area, not radius).
# `--series` colours them by category, giving four dimensions on one chart.
#
# Bubbles are drawn semi-transparent so overlaps stay readable — `--opacity 1`
# turns that off.
@category plot
@search-terms plot bubble scatter size area third dimension weighted points
@example "Population against income, sized by area, drawn in the terminal" {
    [
        {country: it, income: 34, life: 83, pop: 59}
        {country: us, income: 76, life: 79, pop: 331}
        {country: jp, income: 42, life: 85, pop: 125}
        {country: br, income: 17, life: 76, pop: 214}
    ] | plot bubble -x income -y life --size pop --title "life vs income"
}
@example "Coloured by series, written to a file" {
    ["eu" "us"]
    | each {|r| 1..25 | each {|_| {region: $r, x: (random float 0..10), y: (random float 0..10), w: (random float 1..40)}}}
    | flatten
    | plot bubble -x x -y y --size w --series region --grid --out /tmp/plot-bubble.png
}
export def bubble [
    --x-axis (-x): string,                          # x column (required)
    --y-axis (-y): string,                          # y column (required)
    --size (-s): string,                            # numeric column driving bubble area (required)
    --series: string,                               # colour grouping
    --shape: string@"complete point-shape" = "circle",  # marker shape
    --min-size: float = 20.0,                       # area in px² at the smallest value
    --max-size: float = 900.0,                      # area in px² at the largest value
    --opacity: float = 0.7,                         # marker opacity
    --title (-t): string,                           # plot title
    --xlabel: string,                               # x-axis label
    --ylabel: string,                               # y-axis label
    --xrange: list<any>,                            # [min max] for x axis
    --yrange: list<any>,                            # [min max] for y axis
    --width: int = 800,                             # plotting-area width in px
    --height: int = 600,                            # plotting-area height in px
    --grid,                                         # draw a background grid
    --no-legend,                                    # hide the legends
    --logx,                                         # log scale on x axis
    --logy,                                         # log scale on y axis
    --legend-pos: string@"complete legend-pos",     # legend position, e.g. "top-right"
    --xformat: string,                              # d3-format spec for x tics
    --yformat: string,                              # d3-format spec for y tics
    --out (-o): path,                               # write an image file instead of drawing (format from extension)
]: list -> any {
    let data = $in | validate assert table
    require-flag "plot bubble" "--x-axis" $x_axis
    require-flag "plot bubble" "--y-axis" $y_axis
    require-flag "plot bubble" "--size" $size
    $data | validate assert columns ([$x_axis $y_axis $size] | append ([$series] | compact)) | ignore
    $data | validate assert numeric $size | ignore

    mut size_ch = {field: $size, type: "quantitative", scale: {range: [$min_size $max_size]}}
    # Unlike a trail's width, the bubble scale is meant to be read — so it keeps
    # its legend unless legends are refused outright.
    if $no_legend { $size_ch = ($size_ch | insert legend null) }

    mut enc = {
        x: {field: $x_axis, type: (col-type $data $x_axis)}
        y: {field: $y_axis, type: (col-type $data $y_axis)}
        size: $size_ch
    }
    if ($series != null) { $enc = ($enc | insert color {field: $series, type: "nominal", title: null}) }
    let n_series = if ($series == null) { 1 } else { $data | get $series | uniq | length }

    vega {
        data: $data
        mark: {type: "point", shape: $shape, filled: true, opacity: $opacity}
        encoding: $enc
        x_channel: "x"
        y_channel: "y"
        appearance: (appearance $title $xlabel ($ylabel | default $y_axis) $xrange $yrange $width $height $grid $no_legend $logx $logy $legend_pos $xformat $yformat $n_series)
        out: $out
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

# Resolve the two input layouts the folded-series marks (line/scatter/bar/step/
# impulses) accept into one common shape, and validate it.
#
# WIDE (default): `--y` lists one column per series; a `fold` transform melts those
# columns into synthetic `series`/`value` fields that the encoding reads.
# LONG (`--series <col>` given): the table is ALREADY tidy — one value column (the
# single `--y`) plus a column whose VALUES name the lines — so no fold is needed and
# the encoding reads those real fields directly. This is what lets a grouped source
# (a pivot-free `mole-victorialogs hits --field level`, a VM range query, …) pipe
# straight in. Returns {transform, series_field, value_field, n_series}: the caller
# drops the fields into its x/y/color channels, the transform into the spec, and
# n_series into the legend heuristic (distinct series count in long mode).
# `y` is typed `any`, not `list<string>`: a missing --y arrives as null, and a
# typed annotation would reject it with nushell's opaque "Can't convert to
# list<string>" before require-non-empty could name the flag.
def series-shape [cmd: string, data: list, x_axis: string, y: any, series: any]: nothing -> record {
    if ($series | is-not-empty) {
        if (($y | default [] | length) != 1) {
            error make {msg: $"($cmd): with --series, pass a single --y column as the value to measure; got (($y | default [] | length))"}
        }
        let value = ($y | first)
        $data | validate assert columns [$x_axis $series $value] | ignore
        $data | validate assert numeric $value | ignore
        {transform: [], series_field: $series, value_field: $value, n_series: ($data | get $series | uniq | length)}
    } else {
        require-non-empty $cmd "--y" $y
        $data | validate assert columns ([$x_axis] | append $y) | ignore
        for col in $y { $data | validate assert numeric $col | ignore }
        {transform: [{fold: $y, as: ["series" "value"]}], series_field: "series", value_field: "value", n_series: ($y | length)}
    }
}

# Whisker reach for a box plot: a number is a multiple of the IQR, "min-max"
# stretches to the extremes.
def box-extent [e: string]: nothing -> any {
    if ($e == "min-max") { return "min-max" }
    try { $e | into float } catch {
        error make {msg: $"plot boxplot: unknown --extent '($e)'; use a number or one of: (complete box-extent | str join ', ')"}
    }
}

# Outer radius of a pie/donut, in px: `frac` of the shorter side's half, leaving
# the remainder for whatever is printed outside the ring.
def arc-outer [a: record, frac: float]: nothing -> int {
    ([$a.width, $a.height] | math min) / 2 * $frac | math round
}

# Blank out a text channel on rows failing `test` (a Vega expression), leaving
# the mark in place but empty. A null test draws every row's text.
def gate-text [channel: record, test: any]: nothing -> record {
    if ($test == null) { return $channel }
    {condition: ($channel | merge {test: $test}), value: ""}
}

# A text layer plus a dark under-copy of itself, so a label keeps its contrast
# wherever it lands — over a pale mark as readily as over the background. White
# is as bright as text gets, so past that point contrast has to come from what is
# behind the glyphs. Vega offers no paint-order control inside a mark (a `stroke`
# on the glyph paints OVER its own fill), hence a second, fatter layer drawn
# first. Returns both layers, halo first.
def haloed [mark: record, encoding: record, bg: string, size: float]: nothing -> list {
    let halo = $mark | merge {stroke: $bg, strokeWidth: ($size * 0.22), strokeJoin: "round"}
    [
        {mark: $halo, encoding: ($encoding | merge {color: {value: $bg}})}
        {mark: $mark, encoding: $encoding}
    ]
}

# One ring of text at radius `r`, optionally nudged vertically by `dy` px so two
# rings can share the same radial position without colliding. Two layers, haloed.
def arc-text [r: int, size: float, channel: record, dy: any, fg: string]: nothing -> list {
    # Semibold: a data label has to hold its own against the marks, and the
    # terminal's downscale thins strokes. Axis furniture stays regular weight.
    let base = {type: "text", radius: $r, fontSize: $size, fontWeight: 600}
    let mark = if ($dy == null) { $base } else { $base | insert dy $dy }
    haloed $mark {text: $channel, color: {value: $fg}} (theme).bg $size
}

# An arc mark of the given radius; `hole` > 0 turns the pie into a donut. A
# hairline in the background colour keeps adjacent slices from bleeding together.
def arc-mark [outer: int, hole: float]: nothing -> record {
    let m = {type: "arc", outerRadius: $outer, stroke: (theme).bg, strokeWidth: 1}
    if ($hole > 0) { $m | insert innerRadius (($outer * $hole) | math round) } else { $m }
}

# A `rect` cell needs a DISCRETE position, so a numeric (or datetime) axis column
# becomes ordinal — one cell per distinct value — rather than a continuous scale
# that would collapse every cell to a hairline.
def cell-channel [data: list, col: string]: nothing -> record {
    let ty = col-type $data $col
    {field: $col, type: (if $ty == "nominal" { "nominal" } else { "ordinal" })}
}

# Map a column's detected kind to a Vega-Lite encoding type.
def col-type [data: list, col: string]: nothing -> string {
    match ($data | validate detect axis type $col) {
        "numeric" => "quantitative"
        "datetime" => "temporal"
        "categorical" => "nominal"
        $other => { error make {msg: $"plot: unsupported type '($other)' for column '($col)'"} }
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
