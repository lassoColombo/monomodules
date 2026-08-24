# The shared body of every multi-series chart.
#
# line, scatter, bar, step and impulses differ ONLY in their mark and (for bar)
# a couple of encoding channels. Everything else — validating the table,
# resolving wide vs long input, building the x/y/color encoding, deciding
# whether a legend is worth drawing, and handing off to the renderer — is here,
# once.

use ../../lib/validate.nu
use ../../lib/state.nu
use ../../render
use ./series.nu *

# `enc_override` is an optional closure {|s| record } whose result is merged over
# the default encoding — it receives the resolved series shape, so a chart can
# reference the synthetic series/value fields (bar uses it for stacking).
export def folded [
    cmd: string,
    x: any,          # typed `any`, not `string`: a missing --x-axis arrives as
                     # null, and a `string` annotation would reject it with
                     # nushell's opaque "Can't convert to string" before
                     # `require flag` could say which flag is actually missing.
    y: list<string>,
    series: any,
    mark: any,
    look: record,
    enc_override: any = null,
]: list -> any {
    let data = $in | validate assert table
    require flag $cmd "--x-axis" $x
    state remember columns $data

    let s = series shape $cmd $data $x $y $series

    let base = {
        x: {field: $x, type: (x type $data $x)}
        y: {field: $s.value_field, type: "quantitative"}
        color: {field: $s.series_field, type: "nominal", title: null}
    }
    let encoding = if $enc_override == null { $base } else { $base | merge (do $enc_override $s) }

    render {
        data: $data
        mark: $mark
        transform: $s.transform
        encoding: $encoding
        x_channel: "x"
        y_channel: "y"
    } ($look | merge {
        ylabel: ($look.ylabel | default ylabel $y)
        # A one-series legend is just noise, so only draw it for 2+ series.
        legend: ($look.legend and ($s.n_series > 1))
    })
}
