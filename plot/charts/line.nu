use ./common *
use ../lib/complete.nu

# Line plot of one or more y-series against x.
#
# The x column may be numeric, datetime, or categorical. Multiple y columns are
# drawn as overlaid series sharing one x axis. `--smooth` interpolates the curve
# through the points.
#
# `--series <col>` takes LONG/tidy input instead of wide: each distinct value of
# that column becomes its own line, with the single `--y` column as the value —
# so grouped data pipes in without a manual pivot.
@category plot
@search-terms plot line chart timeseries series long tidy
@example "Sine wave, drawn in the terminal" {
    seq 0 60 | each {|i| {x: $i, y: ($i * 0.1 | math sin)}} | plot line -x x --y [y]
}
@example "Long/tidy input: one line per series value, no pivot" {
    [[t, sensor, v]; [0, a, 1], [0, b, 4], [1, a, 2], [1, b, 3], [2, a, 5], [2, b, 2]]
    | plot line -x t --series sensor --y [v] --title "two sensors" --grid
}
@example "Two series, written to a file instead" {
    seq 1 20 | each {|i| {t: $i, a: ($i * $i), b: ($i * 3)}}
    | plot line -x t --y [a b] --title "quadratic vs linear" --grid --out /tmp/plot-line.png
}
export def main [
    --x-axis (-x): string@"complete columns",       # x column (required)
    --y: list<string>@"complete numeric-columns",   # y columns (wide); with --series, the single value column
    --series: string@"complete label-columns",      # long input: column whose values name each series
    --smooth: string@"complete smooth" = "none",    # curve interpolation
    --title (-t): string,                           # plot title
    --xlabel: string,                               # x-axis label
    --ylabel: string,                               # y-axis label
    --xrange: list<any>,                            # [min max] for x axis
    --yrange: list<any>,                            # [min max] for y axis
    --width: int = 800,                             # image width in px (--out only)
    --height: int = 600,                            # image height in px (--out only)
    --grid,                                         # draw a background grid
    --no-legend,                                    # hide the series legend
    --logx,                                         # log scale on x axis
    --logy,                                         # log scale on y axis
    --legend-pos: string@"complete legend-pos",     # legend position, e.g. "top-right"
    --xformat: string@"complete format",            # d3-format spec for x ticks
    --yformat: string@"complete format",            # d3-format spec for y ticks
    --out (-o): path,                               # write an image file instead of drawing
    --spec,                                         # return the Vega-Lite spec instead of drawing
]: list -> any {
    let data = $in
    let interp = smooth interp $smooth
    let mark = if ($interp == null) { "line" } else { {type: "line", interpolate: $interp} }

    $data | folded "plot line" $x_axis ($y | default []) $series $mark (common {
        title: $title, xlabel: $xlabel, ylabel: $ylabel
        xrange: $xrange, yrange: $yrange, width: $width, height: $height
        grid: $grid, legend: (not $no_legend), legend_pos: $legend_pos
        logx: $logx, logy: $logy, xformat: $xformat, yformat: $yformat
        out: $out, spec: $spec
    })
}
