# Turning flags and a table into the pieces a Vega-Lite encoding needs.

use ../../lib/validate.nu
use ../../lib/complete.nu

export def "require flag" [cmd: string, flag: string, value: any]: nothing -> nothing {
    let kind = $value | describe
    if ($value == null) or ($kind == "string" and ($value | is-empty)) {
        error make {msg: $"($cmd): ($flag) is required"}
    }
}

# Resolve the two input layouts the folded-series marks accept into one shape.
#
# WIDE (default): `--y` lists one column per series; a `fold` transform melts
# those columns into synthetic series/value fields the encoding reads.
# LONG (`--series <col>`): the table is ALREADY tidy — one value column (the
# single `--y`) plus a column whose VALUES name the series — so no fold is
# needed and the encoding reads those real fields directly. That is what lets a
# grouped source pipe straight in without a manual pivot.
#
# Returns {transform, series_field, value_field, n_series}.
export def "series shape" [cmd: string, data: list, x: string, y: list<string>, series: any]: nothing -> record {
    if ($series | is-not-empty) {
        if (($y | default [] | length) != 1) {
            error make {msg: $"($cmd): with --series, pass a single --y column as the value to measure; got (($y | default [] | length))"}
        }
        let value = $y | first
        $data | validate assert columns [$x $series $value] | ignore
        $data | validate assert numeric $value | ignore
        {transform: [], series_field: $series, value_field: $value, n_series: ($data | get $series | uniq | length)}
    } else {
        if ($y == null) or ($y | is-empty) {
            error make {msg: $"($cmd): --y is required and must be non-empty"}
        }
        $data | validate assert columns ([$x] | append $y) | ignore
        for col in $y { $data | validate assert numeric $col | ignore }
        {transform: [{fold: $y, as: ["series" "value"]}], series_field: "series", value_field: "value", n_series: ($y | length)}
    }
}

# A column's detected kind -> a Vega-Lite encoding type.
export def "x type" [data: list, col: string]: nothing -> string {
    match ($data | validate detect axis type $col) {
        "numeric" => "quantitative"
        "datetime" => "temporal"
        "categorical" => "nominal"
        $other => { error make {msg: $"plot: unsupported x-axis type '($other)'"} }
    }
}

# Default the y-axis label to the column name when there is a single series.
export def "default ylabel" [y: any]: any -> any {
    let given = $in
    if ($given != null) { return $given }
    let cols = $y | default []
    if ($cols | length) == 1 { $cols | first } else { null }
}

# --smooth -> Vega-Lite line `interpolate` (null = straight segments).
export def "smooth interp" [s: string]: nothing -> any {
    match $s {
        "none" | "linear" => null
        _ => $s
    }
}

# --where -> Vega-Lite step `interpolate`.
export def "step interp" [w: string]: nothing -> string {
    match $w {
        "pre" => "step-before"
        "post" => "step-after"
        "mid" => "step"
        _ => { error make {msg: $"plot step: unknown --where '($w)'; use one of: (complete step-where | get value | str join ', ')"} }
    }
}
