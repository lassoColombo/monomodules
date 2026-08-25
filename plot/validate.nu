# Input + column validation. No magic — every check errors loudly.

# Assert pipeline input is a non-empty list of records. Returns the list unchanged.
export def "assert table" []: any -> list {
    let input = $in
    let kind = $input | describe
    let is_listy = ($kind | str starts-with "list") or ($kind | str starts-with "table")
    if not $is_listy {
        error make {msg: $"plot: expected a table on input, got ($kind)"}
    }
    if ($input | is-empty) {
        error make {msg: "plot: input table is empty"}
    }
    let first_kind = $input | first | describe
    if not ($first_kind | str starts-with "record") {
        error make {msg: $"plot: expected list<record>, got list of ($first_kind)"}
    }
    $input
}

# Assert every name in `cols` exists in the table's first row.
export def "assert columns" [cols: list<string>]: list -> list {
    let input = $in
    let available = $input | first | columns
    for col in $cols {
        if not ($col in $available) {
            error make {
                msg: $"plot: column '($col)' not found. Available: ($available | str join ', ')"
            }
        }
    }
    $input
}

# Classify a column's type — used for any positional channel, not just x. Returns "numeric" | "datetime" | "categorical".
# Errors on unsupported types (lists, records, etc.).
#
# `filesize` and `duration` count as numeric: they serialize to JSON as plain
# numbers (bytes and nanoseconds), so `ls | plot ...` plots without a conversion.
export def "detect axis type" [col: string]: list -> string {
    let input = $in
    let sample = $input | first | get $col
    let kind = $sample | describe
    match $kind {
        "int" | "float" | "filesize" | "duration" => "numeric"
        "datetime" => "datetime"
        "string" => "categorical"
        _ => {
            error make {msg: $"plot: unsupported type '($kind)' for column '($col)'"}
        }
    }
}

# Assert a column contains only numbers (or null, treated as missing data).
export def "assert numeric" [col: string]: list -> list {
    let input = $in
    let bad = $input | enumerate | where {|e|
        let v = $e.item | get $col
        let k = $v | describe
        not ($k in ["int" "float" "filesize" "duration" "nothing"])
    }
    if ($bad | is-not-empty) {
        let row = $bad | first
        let k = $row.item | get $col | describe
        error make {
            msg: $"plot: column '($col)' must be numeric; row ($row.index) has type ($k)"
        }
    }
    $input
}
