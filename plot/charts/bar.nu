use ./common *
use ../lib/complete.nu

# Bar plot of one or more y-series against a categorical x.
#
# `--style` chooses the layout:
#   clustered  → side-by-side bars per category (default)
#   stacked    → bars stacked by series
#   normalized → stacked to 100% (relative share)
#
# `--series <col>` takes long/tidy input instead of wide `--y` columns, so a
# grouped result stacks without a manual pivot.
@category plot
@search-terms plot bar column clustered stacked normalized series long tidy
@example "Clustered bars from a categorical table" {
    [{fruit: apple, q1: 12, q2: 18}, {fruit: pear, q1: 7, q2: 9}, {fruit: banana, q1: 20, q2: 15}]
    | plot bar -x fruit --y [q1 q2] --title "fruit sales" --grid
}
@example "Stacked bars" {
    seq 1 6 | each {|i| {label: $"day-($i)", reads: ($i * 10), writes: ($i * 4)}}
    | plot bar -x label --y [reads writes] --style stacked
}
export def main [
    --x-axis (-x): string@"complete columns",       # x column (required) — the bar label
    --y: list<string>@"complete numeric-columns",   # y columns (wide); with --series, the single value column
    --series: string@"complete label-columns",      # long input: column whose values name each series
    --style: string@"complete bar-style" = "clustered",  # clustered, stacked, or normalized
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
    let styles = complete bar-style | get value
    if $style not-in $styles {
        error make {msg: $"plot bar: unknown --style '($style)'; use one of: ($styles | str join ', ')"}
    }

    # Normalized bars read as percentages unless a y format was forced.
    let yfmt = if ($yformat == null) and ($style == "normalized") { "%" } else { $yformat }

    # x is always categorical here, and the stacking mode lives on the y channel.
    let encoding = {|s|
        let y_ch = match $style {
            "clustered" => {field: $s.value_field, type: "quantitative", stack: null}
            "stacked" => {field: $s.value_field, type: "quantitative", stack: true}
            _ => {field: $s.value_field, type: "quantitative", stack: "normalize"}
        }
        let base = {x: {field: $x_axis, type: "nominal"}, y: $y_ch}
        if $style == "clustered" {
            $base | insert xOffset {field: $s.series_field, type: "nominal"}
        } else {
            $base
        }
    }

    $data | folded "plot bar" $x_axis ($y | default []) $series "bar" (common {
        title: $title, xlabel: $xlabel, ylabel: $ylabel
        xrange: $xrange, yrange: $yrange, width: $width, height: $height
        grid: $grid, legend: (not $no_legend), legend_pos: $legend_pos
        logx: $logx, logy: $logy, xformat: $xformat, yformat: $yfmt
        out: $out, spec: $spec
    }) $encoding
}
