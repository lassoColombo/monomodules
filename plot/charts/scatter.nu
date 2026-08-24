use ./common *
use ../lib/complete.nu

# Scatter plot of one or more y-series against x.
#
# `--shape` picks the marker and `--point-size` scales it. `--series <col>` takes
# long/tidy input (one point-series per distinct value of that column, the single
# `--y` as the value) instead of wide `--y` columns.
@category plot
@search-terms plot scatter points marker series long tidy
@example "Random cloud, drawn in the terminal" {
    seq 1 200 | each {|_| {x: (random float (-5)..5), y: (random float (-5)..5)}} | plot scatter -x x --y [y]
}
@example "Two series with grid" {
    seq 1 50 | each {|i| {i: $i, a: (random float 0..10), b: (random float 5..15)}}
    | plot scatter -x i --y [a b] --grid --shape diamond --point-size 1.4
}
export def main [
    --x-axis (-x): string@"complete columns",       # x column (required)
    --y: list<string>@"complete numeric-columns",   # y columns (wide); with --series, the single value column
    --series: string@"complete label-columns",      # long input: column whose values name each series
    --shape: string@"complete point-shape" = "circle",  # marker shape
    --point-size: float = 1.0,                      # point size multiplier
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
    let mark = {type: "point", shape: $shape, size: ($point_size * 40 | math round), filled: true}

    $data | folded "plot scatter" $x_axis ($y | default []) $series $mark (common {
        title: $title, xlabel: $xlabel, ylabel: $ylabel
        xrange: $xrange, yrange: $yrange, width: $width, height: $height
        grid: $grid, legend: (not $no_legend), legend_pos: $legend_pos
        logx: $logx, logy: $logy, xformat: $xformat, yformat: $yformat
        out: $out, spec: $spec
    })
}
