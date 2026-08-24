use ./common *
use ../lib/complete.nu
use ../lib/validate.nu
use ../lib/state.nu
use ../render

# Histogram of a single numeric column's distribution.
#
# Values are binned into ~`--bins` equal-width buckets. With `--normalize` the y
# axis shows relative frequency (bucket count / N) instead of raw counts.
#
# This is the one chart with a single series, so it draws no legend.
@category plot
@search-terms plot histogram distribution density
@example "Normal-ish distribution" {
    seq 1 500 | each {|_| {v: ((random float (-1)..1) + (random float (-1)..1) + (random float (-1)..1))}}
    | plot histogram --col v --bins 40
}
@example "Normalized histogram" {
    seq 1 1000 | each {|_| {x: (random float 0..10)}}
    | plot histogram --col x --bins 25 --normalize --title "uniform[0,10]"
}
export def main [
    --col (-c): string@"complete numeric-columns",  # numeric column to histogram (required)
    --bins: int@"complete bins" = 30,               # approximate number of bins
    --normalize,                                    # plot relative frequency instead of counts
    --title (-t): string,                           # plot title
    --xlabel: string,                               # x-axis label
    --ylabel: string,                               # y-axis label
    --xrange: list<any>,                            # [min max] for x axis
    --yrange: list<any>,                            # [min max] for y axis
    --width: int = 800,                             # image width in px (--out only)
    --height: int = 600,                            # image height in px (--out only)
    --grid,                                         # draw a background grid
    --logx,                                         # log scale on x axis
    --logy,                                         # log scale on y axis
    --xformat: string@"complete format",            # d3-format spec for x ticks
    --yformat: string@"complete format",            # d3-format spec for y ticks
    --out (-o): path,                               # write an image file instead of drawing
    --spec,                                         # return the Vega-Lite spec instead of drawing
]: list -> any {
    let data = $in | validate assert table
    require flag "plot histogram" "--col" $col
    $data | validate assert columns [$col] | ignore
    $data | validate assert numeric $col | ignore
    state remember columns $data

    let base_tf = [
        {bin: {maxbins: $bins}, field: $col, as: ["__b0" "__b1"]}
        {aggregate: [{op: "count", as: "__count"}], groupby: ["__b0" "__b1"]}
    ]
    let tf = if $normalize {
        $base_tf | append [
            {joinaggregate: [{op: "sum", field: "__count", as: "__total"}]}
            {calculate: "datum.__count / datum.__total", as: "__freq"}
        ]
    } else {
        $base_tf
    }

    render {
        data: $data
        mark: "bar"
        transform: $tf
        encoding: {
            x: {field: "__b0", type: "quantitative", bin: "binned"}
            x2: {field: "__b1"}
            y: {field: (if $normalize { "__freq" } else { "__count" }), type: "quantitative"}
        }
        x_channel: "x"
        y_channel: "y"
    } (common {
        title: $title
        xlabel: ($xlabel | default $col)
        ylabel: (if ($ylabel != null) { $ylabel } else if $normalize { "frequency" } else { "count" })
        xrange: $xrange, yrange: $yrange, width: $width, height: $height
        grid: $grid, legend: false, legend_pos: null
        logx: $logx, logy: $logy, xformat: $xformat, yformat: $yformat
        out: $out, spec: $spec
    })
}
