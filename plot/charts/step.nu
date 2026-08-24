use ./common *
use ../lib/complete.nu

# Step plot of one or more y-series against x.
#
# `--where` controls where the step happens between two samples: `pre` steps
# before the point (default), `post` after it, `mid` halfway between.
#
# `--series <col>` takes long/tidy input instead of wide `--y` columns.
@category plot
@search-terms plot step staircase piecewise series long tidy
@example "Staircase signal" {
    [{t: 0, level: 0}, {t: 1, level: 1}, {t: 2, level: 1}, {t: 3, level: 3}, {t: 4, level: 2}]
    | plot step -x t --y [level] --grid
}
@example "Mid-step variant" {
    seq 1 12 | each {|i| {x: $i, y: (($i mod 3) + 1)}} | plot step -x x --y [y] --where mid
}
export def main [
    --x-axis (-x): string@"complete columns",       # x column (required)
    --y: list<string>@"complete numeric-columns",   # y columns (wide); with --series, the single value column
    --series: string@"complete label-columns",      # long input: column whose values name each series
    --where: string@"complete step-where" = "pre",  # step placement: pre, post, or mid
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
    let mark = {type: "line", interpolate: (step interp $where)}

    $data | folded "plot step" $x_axis ($y | default []) $series $mark (common {
        title: $title, xlabel: $xlabel, ylabel: $ylabel
        xrange: $xrange, yrange: $yrange, width: $width, height: $height
        grid: $grid, legend: (not $no_legend), legend_pos: $legend_pos
        logx: $logx, logy: $logy, xformat: $xformat, yformat: $yformat
        out: $out, spec: $spec
    })
}
