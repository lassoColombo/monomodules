use ./common *
use ../lib/complete.nu

# Impulse plot: vertical sticks from y=0 to each y value.
#
# Good for sparse spikes (counts, deltas) where lines or bars would be noisy.
# `--linewidth` controls stick thickness.
@category plot
@search-terms plot impulses sticks spikes lollipop series long tidy
@example "Sparse spikes" {
    seq 1 25 | each {|i| {x: $i, hits: (if (random int 0..4) == 0 { random int 1..10 } else { 0 })}}
    | plot impulses -x x --y [hits] --grid
}
@example "Thicker sticks" {
    seq 1 15 | each {|i| {i: $i, v: ($i mod 5)}} | plot impulses -x i --y [v] --linewidth 4
}
export def main [
    --x-axis (-x): string@"complete columns",       # x column (required)
    --y: list<string>@"complete numeric-columns",   # y columns (wide); with --series, the single value column
    --series: string@"complete label-columns",      # long input: column whose values name each series
    --linewidth (-w): float = 2.0,                  # stick thickness
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
    let mark = {type: "rule", size: $linewidth}

    $data | folded "plot impulses" $x_axis ($y | default []) $series $mark (common {
        title: $title, xlabel: $xlabel, ylabel: $ylabel
        xrange: $xrange, yrange: $yrange, width: $width, height: $height
        grid: $grid, legend: (not $no_legend), legend_pos: $legend_pos
        logx: $logx, logy: $logy, xformat: $xformat, yformat: $yformat
        out: $out, spec: $spec
    }) {|s| {y2: {datum: 0}} }
}
