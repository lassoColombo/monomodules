# Session-scoped state on disk.
#
# Small on purpose: today it only remembers the columns of the last table that
# was plotted, so flags like `-x` / `--y` can offer real completions (a completer
# cannot see pipeline input, so the previous run is the only source of truth we
# have). This is deliberately the same layout the data plane will use later —
# see ARCHITECTURE.md.

# Root of all plot state. Override with $env.PLOT_STATE.
export def root []: nothing -> path {
    let e = $env.PLOT_STATE? | default ""
    if ($e | is-not-empty) { $e | path expand } else { $nu.home-dir | path join ".local" "state" "plot" }
}

# Datasets are keyed by zellij session so sibling panes share them and separate
# sessions never collide.
export def session []: nothing -> string {
    let z = $env.ZELLIJ_SESSION_NAME? | default ""
    if ($z | is-not-empty) { return $z }
    let p = $env.PLOT_SESSION? | default ""
    if ($p | is-not-empty) { $p } else { "default" }
}

export def dir []: nothing -> path {
    let d = root | path join (session)
    if not ($d | path exists) { mkdir $d }
    $d
}

def columns-file []: nothing -> path { dir | path join "last-columns.nuon" }

# Record the shape of a table so the next command line can complete against it.
# Split by type: --y wants numbers, --series wants labels.
export def "remember columns" [data: list]: nothing -> nothing {
    let head = $data | first
    # `columns` needs a statically-known record/table; a `list` parameter erases
    # that, so it would quietly return []. transpose works on a runtime record.
    let all = $head | transpose key value | get key
    let numeric = $all | where {|c| ($head | get $c | describe) in ["int" "float"] }
    {
        all: $all
        numeric: $numeric
        other: ($all | where {|c| $c not-in $numeric })
    } | to nuon | save -f (columns-file)
}

# Read back a remembered column list. Never errors: completion must not explode.
export def "recall columns" [kind: string = "all"]: nothing -> list<string> {
    try {
        let f = columns-file
        if not ($f | path exists) { return [] }
        open --raw $f | from nuon | get $kind
    } catch { [] }
}
