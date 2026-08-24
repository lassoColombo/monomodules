# Shared fixtures for the plot test suites.

# Run a closure with plot's state redirected to a throwaway directory, so tests
# never touch (or race on) the real completion cache in ~/.local/state/plot.
export def isolated [c: closure]: nothing -> any {
    let d = mktemp --tmpdir --directory
    let out = with-env {PLOT_STATE: $d} { do $c }
    rm --recursive --force $d
    $out
}

# Wide/untidy: one column per series.
export def "sample wide" []: nothing -> list {
    seq 1 12 | each {|i| {x: $i, a: ($i * $i), b: ($i * 3), label: $"n($i)"} }
}

# Categorical x, for bars.
export def "sample cat" []: nothing -> list {
    [
        {fruit: "apple",  q1: 12, q2: 18}
        {fruit: "pear",   q1: 7,  q2: 9}
        {fruit: "banana", q1: 20, q2: 15}
    ]
}

# Long/tidy: a column whose VALUES name each series.
export def "sample long" []: nothing -> list {
    [
        {t: 0, sensor: "a", v: 1}
        {t: 0, sensor: "b", v: 4}
        {t: 1, sensor: "a", v: 2}
        {t: 1, sensor: "b", v: 3}
    ]
}

export def "sample nums" []: nothing -> list {
    seq 1 100 | each {|i| {v: ($i mod 17 | into float)} }
}

# The message a closure fails with, for asserting on error text.
export def "error message" [c: closure]: nothing -> string {
    try { do $c; "NO ERROR RAISED" } catch {|e| $e.msg }
}
